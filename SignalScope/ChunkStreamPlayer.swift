import Foundation
import Combine
import AVFoundation
import AudioToolbox

/// Live-stream player for the mobile `/chunks` short-poll API (4.2.27+).
///
/// Replaces AVPlayer-on-`/live` for live listening: `/live` holds one hub
/// Waitress thread for the whole listen; `/chunks` holds a thread for at
/// most ~1.5 s per poll. The server returns base64 MP3 chunks:
///   • hub proxy  — first call (no slot_id) returns a slot_id + warmup,
///     then poll with ?slot_id=…  (410 = slot expired → new handshake)
///   • local node — poll with ?consumer_id=…&since=N, track next_since
/// This player sends both shapes (each impl ignores the other's params),
/// single-flights the polls, parses MP3 with AudioFileStream, converts to
/// PCM with AVAudioConverter and schedules onto an AVAudioEngine node —
/// the same engine pattern as PCMStreamPlayer.
final class ChunkStreamPlayer: NSObject, ObservableObject {

    enum Status: String { case idle, connecting, buffering, playing, error }

    @Published private(set) var status: Status = .idle
    @Published private(set) var statusText: String = ""

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var pollTask: Task<Void, Never>?
    private var session: URLSession { URLSession.shared }

    // request state
    private var chunksURL: URL?
    private var headers: [String: String] = [:]
    private var slotID: String?
    private var since: Int = 0
    private let consumerID = "ios-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(28)

    // mp3 parse / convert state
    private var fileStream: AudioFileStreamID?
    private var srcFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat?
    private var scheduledBuffers = 0
    private var engineStarted = false
    private let audioQueue = DispatchQueue(label: "chunkplayer.audio")

    // MARK: - control

    func start(chunksURL: URL, headers: [String: String]) {
        stop()
        self.chunksURL = chunksURL
        self.headers = headers
        self.slotID = nil
        self.since = 0
        setStatus(.connecting, "Connecting…")
        openParser()
        pollTask = Task { [weak self] in await self?.pollLoop() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        audioQueue.sync {
            if let fs = fileStream { AudioFileStreamClose(fs); fileStream = nil }
            srcFormat = nil; converter = nil
            scheduledBuffers = 0
        }
        playerNode.stop()
        if engineStarted { engine.stop(); engineStarted = false }
        setStatus(.idle, "")
    }

    // MARK: - polling

    private func pollLoop() async {
        var failures = 0
        while !Task.isCancelled {
            guard let base = chunksURL else { return }
            var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            var items = comps.queryItems ?? []
            items.append(URLQueryItem(name: "timeout", value: "1500"))
            items.append(URLQueryItem(name: "max_chunks", value: "16"))
            items.append(URLQueryItem(name: "consumer_id", value: String(consumerID)))
            items.append(URLQueryItem(name: "since", value: String(since)))
            if let slotID { items.append(URLQueryItem(name: "slot_id", value: slotID)) }
            comps.queryItems = items
            guard let url = comps.url else { return }

            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            do {
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 410 {          // slot expired → re-handshake
                    slotID = nil; since = 0
                    continue
                }
                guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                let body = try JSONDecoder().decode(ChunkPollResponse.self, from: data)
                failures = 0
                if let s = body.slot_id { slotID = s }
                since = body.next_since ?? since
                if body.eof == true {
                    slotID = nil; since = 0          // stream restarted server-side
                    continue
                }
                if !body.chunks.isEmpty {
                    for c in body.chunks {
                        if let d = Data(base64Encoded: c.data) { feed(d) }
                    }
                } else if body.slot_id != nil && status == .connecting {
                    setStatus(.buffering, "Buffering…")   // handshake done, relay warming
                }
            } catch is CancellationError {
                return
            } catch {
                failures += 1
                if failures >= 5 {
                    setStatus(.error, "Stream lost")
                    return
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    // MARK: - mp3 parsing (AudioFileStream)

    private func openParser() {
        audioQueue.sync {
            var fs: AudioFileStreamID?
            let client = Unmanaged.passUnretained(self).toOpaque()
            AudioFileStreamOpen(client, { inClient, streamID, propertyID, _ in
                let me = Unmanaged<ChunkStreamPlayer>.fromOpaque(inClient).takeUnretainedValue()
                me.parserProperty(streamID, propertyID)
            }, { inClient, byteCount, packetCount, bytes, packetDescs in
                let me = Unmanaged<ChunkStreamPlayer>.fromOpaque(inClient).takeUnretainedValue()
                me.parserPackets(byteCount: byteCount, packetCount: packetCount,
                                 bytes: bytes, descs: packetDescs)
            }, kAudioFileMP3Type, &fs)
            fileStream = fs
        }
    }

    private func feed(_ data: Data) {
        audioQueue.async { [weak self] in
            guard let self, let fs = self.fileStream else { return }
            data.withUnsafeBytes { raw in
                _ = AudioFileStreamParseBytes(fs, UInt32(raw.count),
                                              raw.baseAddress, [])
            }
        }
    }

    private func parserProperty(_ streamID: AudioFileStreamID, _ propertyID: AudioFileStreamPropertyID) {
        guard propertyID == kAudioFileStreamProperty_DataFormat else { return }
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(streamID, propertyID, &size, &asbd) == noErr,
              let src = AVAudioFormat(streamDescription: &asbd) else { return }
        srcFormat = src
        let out = AVAudioFormat(standardFormatWithSampleRate: src.sampleRate,
                                channels: src.channelCount)!
        outFormat = out
        converter = AVAudioConverter(from: src, to: out)
        DispatchQueue.main.async { [weak self] in self?.setupEngine(format: out) }
    }

    private func parserPackets(byteCount: UInt32, packetCount: UInt32,
                               bytes: UnsafeRawPointer,
                               descs: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard let src = srcFormat, let conv = converter, let out = outFormat,
              packetCount > 0 else { return }

        let comp = AVAudioCompressedBuffer(format: src,
                                           packetCapacity: AVAudioPacketCount(packetCount),
                                           maximumPacketSize: 4096)
        memcpy(comp.data, bytes, Int(byteCount))
        comp.byteLength = byteCount
        comp.packetCount = AVAudioPacketCount(packetCount)
        if let descs, let dst = comp.packetDescriptions {
            for i in 0..<Int(packetCount) { dst[i] = descs[i] }
        }

        // MP3: 1152 frames per packet
        let frames = AVAudioFrameCount(packetCount * 1152)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: frames) else { return }
        var fed = false
        var err: NSError?
        let st = conv.convert(to: pcm, error: &err) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return comp
        }
        guard st != .error, pcm.frameLength > 0 else { return }

        DispatchQueue.main.async { [weak self] in self?.schedule(pcm) }
    }

    // MARK: - engine

    private func setupEngine(format: AVAudioFormat) {
        guard !engineStarted else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .default)
        try? audio.setActive(true)
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            engineStarted = true
        } catch {
            setStatus(.error, "Audio engine failed")
        }
    }

    private func schedule(_ buf: AVAudioPCMBuffer) {
        guard engineStarted else { return }
        scheduledBuffers += 1
        playerNode.scheduleBuffer(buf) { [weak self] in
            DispatchQueue.main.async { self?.scheduledBuffers -= 1 }
        }
        // small pre-buffer (~3 buffers) before starting playback
        if !playerNode.isPlaying && scheduledBuffers >= 3 {
            playerNode.play()
            setStatus(.playing, "Streaming")
        } else if !playerNode.isPlaying && status != .playing {
            setStatus(.buffering, "Buffering…")
        }
    }

    private func setStatus(_ s: Status, _ text: String) {
        if Thread.isMainThread {
            status = s; statusText = text
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.status = s; self?.statusText = text
            }
        }
    }
}

// MARK: - wire model

private struct ChunkPollResponse: Decodable {
    struct Chunk: Decodable {
        let seq: Int
        let data: String
    }
    let ok: Bool?
    let chunks: [Chunk]
    let next_since: Int?
    let slot_id: String?
    let eof: Bool?

    enum CodingKeys: String, CodingKey { case ok, chunks, next_since, slot_id, eof }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? c.decode(Bool.self, forKey: .ok)
        chunks = (try? c.decode([Chunk].self, forKey: .chunks)) ?? []
        next_since = try? c.decode(Int.self, forKey: .next_since)
        slot_id = try? c.decode(String.self, forKey: .slot_id)
        eof = try? c.decode(Bool.self, forKey: .eof)
    }
}
