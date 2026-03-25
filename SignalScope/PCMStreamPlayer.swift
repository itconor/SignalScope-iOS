import AVFoundation
import Combine
import Foundation

/// Streams raw 16-bit signed LE mono 48 kHz PCM from an HTTP endpoint
/// using AVAudioEngine + AVAudioPlayerNode — the same approach the web
/// browser uses with Web Audio API.  AVPlayer cannot handle raw PCM streams
/// (no container, no duration header) so this player is used instead.
final class PCMStreamPlayer: NSObject, ObservableObject {

    // MARK: - Public state

    enum Status: Equatable {
        case idle
        case connecting
        case buffering
        case playing
        case stopped
        case error(String)

        var label: String {
            switch self {
            case .idle:              return "Idle"
            case .connecting:        return "Connecting…"
            case .buffering:         return "Buffering…"
            case .playing:           return "Streaming"
            case .stopped:           return "Stopped"
            case .error(let msg):    return "Error: \(msg)"
            }
        }
    }

    @Published var status: Status = .idle
    var onStatusChange: ((Status) -> Void)?

    // MARK: - Private

    private let engine        = AVAudioEngine()
    private let playerNode    = AVAudioPlayerNode()
    private let format: AVAudioFormat

    // 16-bit signed LE, mono, 48 kHz
    private let sampleRate:     Double            = 48_000
    private let bytesPerSample: Int               = 2
    private let channelCount:   AVAudioChannelCount = 1

    // Chunk size: 0.1 s = 4800 frames = 9600 bytes
    private let framesPerBlock: AVAudioFrameCount = 4_800
    private var bytesPerBlock:  Int { Int(framesPerBlock) * bytesPerSample }

    // Pre-buffer: wait for 1 s of data before starting playback
    private let preBufferBlocks = 10

    private var dataTask:      URLSessionDataTask?
    private var urlSession:    URLSession?

    // All mutable state below is protected by `lock`
    private let lock            = NSLock()
    private var receivedData    = Data()
    private var scheduledBlocks = 0
    private var playbackStarted = false
    private var stopped         = false   // set true by stop(); lets delegate thread bail early

    // MARK: - Init

    override init() {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate:   sampleRate,
            channels:     channelCount,
            interleaved:  false
        )!
        super.init()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Public API

    func start(url: URL) {
        stop()

        lock.lock()
        stopped = false
        lock.unlock()

        updateStatus(.connecting)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            try engine.start()
        } catch {
            updateStatus(.error("Audio engine: \(error.localizedDescription)"))
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 3_600
        let delegate = SessionDelegate(player: self)
        urlSession = URLSession(configuration: config,
                                delegate: delegate,
                                delegateQueue: nil)

        var req = URLRequest(url: url,
                             cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 30)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        dataTask = urlSession?.dataTask(with: req)
        dataTask?.resume()
    }

    func stop() {
        dataTask?.cancel()
        dataTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        lock.lock()
        receivedData.removeAll()
        scheduledBlocks  = 0
        playbackStarted  = false
        stopped          = true
        lock.unlock()

        // Stop audio nodes on the main thread to avoid races with the
        // delegate queue calling scheduleBuffer / play.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.playerNode.stop()
            if self.engine.isRunning { self.engine.stop() }
        }

        updateStatus(.stopped)
    }

    // MARK: - Internal (called by SessionDelegate)

    fileprivate func didReceive(data: Data) {
        // Bail immediately if stop() was called
        lock.lock()
        let isStopped = stopped
        if !isStopped { receivedData.append(data) }
        lock.unlock()

        guard !isStopped else { return }
        processBuffer()
    }

    fileprivate func didComplete(error: Error?) {
        if let err = error as? URLError, err.code == .cancelled { return }
        updateStatus(error != nil ? .error(error!.localizedDescription) : .stopped)
    }

    // MARK: - Buffer processing (runs on URLSession delegate queue)

    private func processBuffer() {
        // Drain as many complete blocks as possible from receivedData
        while true {
            // Take one block under lock
            lock.lock()
            guard !stopped, receivedData.count >= bytesPerBlock else {
                lock.unlock()
                return
            }
            let blockData = receivedData.prefix(bytesPerBlock)
            receivedData.removeFirst(bytesPerBlock)
            lock.unlock()

            guard let pcmBuf = pcmBuffer(from: blockData) else { continue }

            // Determine whether to start playback — read + write under lock
            lock.lock()
            let isStopped = stopped
            guard !isStopped else {
                lock.unlock()
                return
            }
            scheduledBlocks += 1
            let count = scheduledBlocks
            let alreadyPlaying = playbackStarted
            if count >= preBufferBlocks && !playbackStarted {
                playbackStarted = true
            }
            lock.unlock()

            guard engine.isRunning else { return }

            playerNode.scheduleBuffer(pcmBuf, completionHandler: nil)

            if !alreadyPlaying && count >= preBufferBlocks {
                playerNode.play()
                updateStatus(.playing)
            } else if !alreadyPlaying {
                updateStatus(.buffering)
            }
        }
    }

    // MARK: - PCM conversion (Int16 LE → Float32)

    private func pcmBuffer(from data: Data) -> AVAudioPCMBuffer? {
        guard data.count == bytesPerBlock else { return nil }
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: framesPerBlock) else { return nil }
        buf.frameLength = framesPerBlock
        guard let ch = buf.floatChannelData?[0] else { return nil }

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0 ..< Int(framesPerBlock) {
                ch[i] = Float(samples[i]) / 32_768.0
            }
        }
        return buf
    }

    // MARK: - Status helper

    private func updateStatus(_ newStatus: Status) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.status = newStatus
            self.onStatusChange?(newStatus)
        }
    }
}

// MARK: - URLSession delegate (separate class to avoid retain cycle)

private final class SessionDelegate: NSObject, URLSessionDataDelegate {
    weak var player: PCMStreamPlayer?
    init(player: PCMStreamPlayer) { self.player = player }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        player?.didReceive(data: data)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        player?.didComplete(error: error)
    }
}
