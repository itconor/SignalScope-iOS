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
    private let sampleRate:  Double = 48_000
    private let bytesPerSample: Int = 2
    private let channelCount: AVAudioChannelCount = 1

    // Chunk size: 0.1 s = 4800 frames = 9600 bytes
    private let framesPerBlock: AVAudioFrameCount = 4800
    private var bytesPerBlock: Int { Int(framesPerBlock) * bytesPerSample }

    // Pre-buffer: wait for 1 s of data before starting playback
    private var preBufferBlocks: Int { 10 }

    private var dataTask: URLSessionDataTask?
    private var urlSession: URLSession?
    private var receivedData = Data()
    private var scheduledBlockCount = 0
    private var startedPlayback = false
    private let lock = NSLock()

    // MARK: - Init

    override init() {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!
        super.init()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Public API

    func start(url: URL) {
        stop()
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
        config.timeoutIntervalForResource = 3_600  // 1 hour max stream
        let delegate = SessionDelegate(player: self)
        urlSession = URLSession(configuration: config,
                                delegate: delegate,
                                delegateQueue: nil)

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
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
        scheduledBlockCount = 0
        startedPlayback = false
        lock.unlock()

        playerNode.stop()
        if engine.isRunning { engine.stop() }
        updateStatus(.stopped)
    }

    // MARK: - Internal (called by SessionDelegate)

    fileprivate func didReceive(data: Data) {
        lock.lock()
        receivedData.append(data)
        let snapshot = receivedData
        lock.unlock()

        scheduleAvailable(from: snapshot)
    }

    fileprivate func didComplete(error: Error?) {
        if let err = error as? URLError, err.code == .cancelled { return }
        updateStatus(error != nil ? .error(error!.localizedDescription) : .stopped)
    }

    // MARK: - Scheduling

    private func scheduleAvailable(from data: Data) {
        lock.lock()
        var offset = data.count - receivedData.count  // bytes already consumed
        // Work on a local window of receivedData
        var localData = receivedData
        lock.unlock()

        _ = offset  // suppress warning; we work on localData directly

        lock.lock()
        localData = receivedData
        lock.unlock()

        var consumed = 0
        while localData.count - consumed >= bytesPerBlock {
            let blockData = localData.subdata(in: consumed ..< consumed + bytesPerBlock)
            consumed += bytesPerBlock

            guard let pcmBuf = pcmBuffer(from: blockData) else { continue }

            lock.lock()
            scheduledBlockCount += 1
            let count = scheduledBlockCount
            lock.unlock()

            playerNode.scheduleBuffer(pcmBuf, completionHandler: nil)

            if !startedPlayback && count >= preBufferBlocks {
                startedPlayback = true
                playerNode.play()
                updateStatus(.playing)
            } else if !startedPlayback {
                updateStatus(.buffering)
            }
        }

        // Remove consumed bytes from the shared buffer
        if consumed > 0 {
            lock.lock()
            if receivedData.count >= consumed {
                receivedData.removeFirst(consumed)
            }
            lock.unlock()
        }
    }

    // MARK: - PCM conversion (Int16 LE → Float32)

    private func pcmBuffer(from data: Data) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: framesPerBlock) else { return nil }
        buf.frameLength = framesPerBlock
        guard let ch = buf.floatChannelData?[0] else { return nil }

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0 ..< Int(framesPerBlock) {
                ch[i] = Float(samples[i]) / 32768.0
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
