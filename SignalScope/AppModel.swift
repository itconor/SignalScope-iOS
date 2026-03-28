import Foundation
import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import UIKit

struct AudioQueueItem: Identifiable, Hashable, Codable {
    let url: URL
    let title: String
    let subtitle: String?

    var id: String { url.absoluteString }
}

struct RecentFaultSnapshot: Identifiable, Codable, Hashable {
    let id: String
    let chainID: String
    let chainName: String
    let reason: String
    let faultAt: String?
    let capturedAt: Date

    init(chain: ChainSummary) {
        self.id = chain.id + "|" + ISO8601DateFormatter().string(from: Date())
        self.chainID = chain.id
        self.chainName = chain.name
        self.reason = chain.headlineReason
        self.faultAt = chain.fault_at
        self.capturedAt = Date()
    }
}

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("SignalScope.baseURL") private var baseURLString: String = ""
    @AppStorage("SignalScope.token") private var storedToken: String = ""
    @AppStorage("SignalScope.refreshInterval") private var storedRefresh: Double = 5
    @AppStorage("SignalScope.lastSelectedTab") var lastSelectedTab: Int = 0
    @AppStorage("SignalScope.faultFirst") var faultFirstSortEnabled: Bool = true
    @AppStorage("SignalScope.ackFaults") private var storedAcknowledgedFaultIDs: String = "[]"
    @AppStorage("SignalScope.recentFaults") private var storedRecentFaults: String = "[]"
    @AppStorage("SignalScope.apnsToken") private var storedAPNSToken: String = ""
    @AppStorage("SignalScope.watchlist") private var storedWatchlist: String = "[]"
    @AppStorage("SignalScope.chainNotifEnabled") var chainNotificationsEnabled: Bool = true
    @AppStorage("SignalScope.silenceNotifEnabled") var silenceNotificationsEnabled: Bool = false
    @AppStorage("SignalScope.silenceNodes") private var storedSilenceNodes: String = "[]"

    @Published var deepLinkChainID: String?
    @Published var watchlistIDs: Set<String> = []
    @Published var silenceWatchedNodes: Set<String> = []

    // Cooldown: avoid repeated silence alerts for the same node within 10 min
    private var silenceAlertCooldown: [String: Date] = [:]
    private let silenceThresholdDbfs: Double = -45.0
    private let silenceCooldown: TimeInterval = 10 * 60

    @Published var chains: [ChainSummary] = []
    @Published var activeFaults: [ChainSummary] = []
    @Published var isLoading: Bool = false
    @Published var isInitialLoad: Bool = true
    @Published var errorMessage: String?

    @Published var currentAudioItem: AudioQueueItem?
    @Published var audioPlaylist: [AudioQueueItem] = []
    @Published var currentAudioIndex: Int = 0
    @Published var isAudioPlaying: Bool = false
    @Published var audioStatusText: String = ""
    @Published var isPreparingClipPlayback: Bool = false
    @Published var clipPlaybackStatusText: String = ""
    @Published var preparingClipEventID: String?

    @Published var recentFaults: [RecentFaultSnapshot] = []
    @Published var acknowledgedFaultIDs: Set<String> = []
    @Published var reportEvents: [ReportEvent] = []
    @Published var reportsSummary: ReportsSummaryResponse?
    @Published var reportsErrorMessage: String?
    @Published var hasMoreReports: Bool = false
    @Published var isLoadingMoreReports: Bool = false

    @Published var hubOverview: HubOverviewResponse?
    @Published var hubOverviewError: String?

    @Published var abGroups: [ABGroup] = []
    @Published var abGroupsError: String? = nil

    @Published var loadingAudioURL: URL?   // set while AVPlayer is buffering, cleared when .playing
    @Published var loggerDayViewActive: Bool = false   // true only when LoggerDayView is on screen
    @Published var loggerInstalled: Bool = false

    let api = APIClient()
    private var pollTask: Task<Void, Never>?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var temporaryAudioFiles: Set<URL> = []
    private var currentPlaybackTask: Task<Void, Never>?

    init() {
        api.baseURL = URL(string: baseURLString.trimmed)
        api.token = storedToken
        acknowledgedFaultIDs = Self.decodeAcknowledgedIDs(from: storedAcknowledgedFaultIDs)
        recentFaults = Self.decodeRecentFaults(from: storedRecentFaults)
        watchlistIDs = Self.decodeWatchlist(from: storedWatchlist)
        silenceWatchedNodes = Self.decodeStringSet(from: storedSilenceNodes)
        NotificationManager.shared.requestAuthorization()
        startPolling()
        observeNotificationEvents()
    }

    deinit {
        currentPlaybackTask?.cancel()

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil

        for url in temporaryAudioFiles {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryAudioFiles.removeAll()
    }

    var sortedChains: [ChainSummary] {
        chains.sorted { lhs, rhs in
            if faultFirstSortEnabled, lhs.sortPriority != rhs.sortPriority { return lhs.sortPriority < rhs.sortPriority }
            if lhs.isStale != rhs.isStale { return !lhs.isStale && rhs.isStale }
            if lhs.age_secs != rhs.age_secs { return lhs.age_secs < rhs.age_secs }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var displayedFaults: [ChainSummary] {
        let source = activeFaults.isEmpty ? chains : activeFaults
        return source
            .filter { $0.displayStatus == .fault }   // exclude pending/adbreak — not confirmed faults
            .filter { !acknowledgedFaultIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.age_secs != rhs.age_secs { return lhs.age_secs < rhs.age_secs }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var hasActiveFaults: Bool { !displayedFaults.isEmpty }

    var activeFaultBannerText: String {
        guard let first = displayedFaults.first else { return "All clear" }
        if let faultAt = first.fault_at, !faultAt.isEmpty {
            return "\(displayedFaults.count) active fault\(displayedFaults.count == 1 ? "" : "s") · \(first.name) at \(faultAt)"
        }
        return "\(displayedFaults.count) active fault\(displayedFaults.count == 1 ? "" : "s") · \(first.name)"
    }

    func updateSettings(baseURL: String, token: String, refresh: Double) {
        baseURLString = baseURL
        storedToken = token
        storedRefresh = max(5, refresh)
        api.baseURL = URL(string: baseURL.trimmed)
        api.token = token
        restartPolling()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refreshAll()
                let refresh = max(5, storedRefresh)
                try? await Task.sleep(nanoseconds: UInt64(refresh * 1_000_000_000))
            }
        }
    }

    func restartPolling() { startPolling() }
    func stopPolling() { pollTask?.cancel() }
    func refreshAll() async {
        await fetchChains()
        await refreshHubOverview()
        await refreshABGroups()
        writeWidgetData()
    }

    func checkLoggerInstalled() async {
        guard api.baseURL != nil, !api.token.isEmpty else { return }
        do {
            _ = try await api.fetchLoggerStatus()
            loggerInstalled = true
        } catch {
            loggerInstalled = false
        }
    }

    // MARK: - Watchlist

    func toggleWatchlist(_ chainID: String) {
        if watchlistIDs.contains(chainID) {
            watchlistIDs.remove(chainID)
        } else {
            watchlistIDs.insert(chainID)
        }
        persistWatchlist()
    }

    func isWatched(_ chainID: String) -> Bool {
        watchlistIDs.contains(chainID)
    }

    private func persistWatchlist() {
        if let data = try? JSONEncoder().encode(Array(watchlistIDs).sorted()),
           let string = String(data: data, encoding: .utf8) {
            storedWatchlist = string
        }
    }

    // MARK: - Widget data sharing

    /// Writes fault summary to the App Group shared UserDefaults so the home-screen
    /// widget can display current status without making network calls.
    /// NOTE: The App Group entitlement "group.com.signalscope.app" must be added
    /// to both the SignalScope and SignalScopeWidgets targets in Xcode for this to
    /// work on device. The code compiles cleanly without the entitlement.
    private func writeWidgetData() {
        // Prefer the App Group suite; fall back gracefully if entitlement not configured.
        let defaults = UserDefaults(suiteName: "group.com.signalscope.app") ?? UserDefaults.standard
        let faults = displayedFaults
        defaults.set(faults.count, forKey: "faultCount")
        defaults.set(faults.first?.name ?? "", forKey: "worstChainName")
        defaults.set(faults.first?.displayStatus.label ?? "ok", forKey: "worstChainStatus")
        defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdated")
    }

    func fetchChains() async {
        guard api.baseURL != nil else {
            errorMessage = "Enter your SignalScope Hub URL in Settings."
            isInitialLoad = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let chainsTask = api.fetchChains()
            async let faultsTask = api.fetchActiveFaults()
            let (newChains, fetchedFaults) = try await (chainsTask, faultsTask)
            handleNotifications(old: chains, new: newChains)
            chains = newChains
            activeFaults = fetchedFaults
            checkSilenceAlerts()
            errorMessage = nil
            isInitialLoad = false
            await refreshReports()
        } catch {
            // Don't treat task cancellation (e.g. pull-to-refresh interrupted) as an error
            if error is CancellationError { return }
            do {
                let newChains = try await api.fetchChains()
                handleNotifications(old: chains, new: newChains)
                chains = newChains
                activeFaults = newChains.filter { $0.displayStatus == .fault }
                checkSilenceAlerts()
                errorMessage = nil
                isInitialLoad = false
                await refreshReports()
            } catch {
                if error is CancellationError { return }
                errorMessage = error.localizedDescription
                isInitialLoad = false
            }
        }
    }

    func acknowledgeFault(_ chainID: String) {
        acknowledgedFaultIDs.insert(chainID)
        persistAcknowledgedFaultIDs()
    }

    func clearAcknowledgedFaults() {
        acknowledgedFaultIDs.removeAll()
        persistAcknowledgedFaultIDs()
    }


    func refreshReports() async {
        guard api.baseURL != nil else {
            reportsErrorMessage = "Enter your SignalScope Hub URL in Settings."
            return
        }
        do {
            async let eventsTask = api.fetchReportEvents(limit: 100)
            async let summaryTask = api.fetchReportsSummary()
            let (events, summary) = try await (eventsTask, summaryTask)
            reportEvents = events
            reportsSummary = summary
            hasMoreReports = events.count >= 100
            reportsErrorMessage = nil
        } catch {
            reportsErrorMessage = error.localizedDescription
        }
    }

    func loadMoreReports() async {
        guard !isLoadingMoreReports, hasMoreReports else { return }
        guard let cursor = reportEvents.last?.timestampDate?.timeIntervalSince1970 else { return }
        isLoadingMoreReports = true
        defer { isLoadingMoreReports = false }
        do {
            let more = try await api.fetchReportEvents(limit: 100, before: cursor)
            // Deduplicate by id before appending
            let existingIDs = Set(reportEvents.map(\.id))
            let fresh = more.filter { !existingIDs.contains($0.id) }
            reportEvents.append(contentsOf: fresh)
            hasMoreReports = more.count >= 100
        } catch {
            // Non-fatal — existing events remain visible
        }
    }

    func refreshHubOverview() async {
        guard api.baseURL != nil else { return }
        do {
            let overview = try await api.fetchHubOverview()
            hubOverview = overview
            hubOverviewError = nil
        } catch {
            if error is CancellationError { return }
            hubOverviewError = error.localizedDescription
        }
    }

    func refreshABGroups() async {
        guard api.baseURL != nil else { return }
        do {
            let groups = try await api.fetchABGroups()
            abGroups = groups
            abGroupsError = nil
        } catch {
            if error is CancellationError { return }
            abGroupsError = error.localizedDescription
        }
    }

    func playClip(for event: ReportEvent) {
        guard let rawURL = event.clipResolvedURL else { return }
        let remoteURL: URL
        if rawURL.scheme == nil, let base = api.baseURL {
            remoteURL = URL(string: rawURL.absoluteString, relativeTo: base)?.absoluteURL ?? rawURL
        } else {
            remoteURL = rawURL
        }

        let title = event.stream.isEmpty ? (event.chain.isEmpty ? event.site : event.chain) : event.stream
        let subtitle = event.site
        currentPlaybackTask?.cancel()
        teardownPlayer()
        cleanupTemporaryAudioFiles()
        audioPlaylist = []
        currentAudioIndex = 0
        currentAudioItem = nil
        audioStatusText = "Downloading clip…"
        clipPlaybackStatusText = "Downloading clip…"
        isPreparingClipPlayback = true
        preparingClipEventID = event.id
        isAudioPlaying = false
        currentPlaybackTask = Task { [weak self] in
            guard let self else { return }
            do {
                let localURL = try await self.api.downloadAuthorizedFile(from: remoteURL, suggestedFilename: event.clip_name ?? event.clip_id)
                await MainActor.run {
                    self.clipPlaybackStatusText = "Preparing playback…"
                    self.audioStatusText = "Preparing playback…"
                    self.temporaryAudioFiles.insert(localURL)
                    let item = AudioQueueItem(url: localURL, title: title, subtitle: subtitle)
                    self.audioPlaylist = [item]
                    self.currentAudioIndex = 0
                    self.currentAudioItem = item
                    self.startPlayback(item: item)
                    self.audioStatusText = "Playing downloaded clip"
                    self.clipPlaybackStatusText = ""
                    self.isPreparingClipPlayback = false
                    self.preparingClipEventID = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.audioStatusText = ""
                    self.clipPlaybackStatusText = ""
                    self.isPreparingClipPlayback = false
                    self.preparingClipEventID = nil
                }
            } catch {
                await MainActor.run {
                    self.audioStatusText = "Clip download failed"
                    self.clipPlaybackStatusText = ""
                    self.isPreparingClipPlayback = false
                    self.preparingClipEventID = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func playAudio(url: URL, title: String, subtitle: String?, playlist: [AudioQueueItem], index: Int) {
        currentPlaybackTask?.cancel()
        isPreparingClipPlayback = false
        clipPlaybackStatusText = ""
        preparingClipEventID = nil
        teardownPlayer()
        cleanupTemporaryAudioFiles()
        loadingAudioURL = url   // store pre-auth URL so NodeTreeView comparison works
        let authorizedURL = api.authorizedPlaybackURL(for: url)
        let effectivePlaylist = playlist.isEmpty ? [AudioQueueItem(url: authorizedURL, title: title, subtitle: subtitle)] : playlist.map {
            AudioQueueItem(url: api.authorizedPlaybackURL(for: $0.url), title: $0.title, subtitle: $0.subtitle)
        }
        audioPlaylist = effectivePlaylist
        currentAudioIndex = min(max(index, 0), effectivePlaylist.count - 1)
        let selected = effectivePlaylist[currentAudioIndex]
        currentAudioItem = selected
        startPlayback(item: selected)
    }

    func togglePlayback() {
        guard let player else { return }
        if isAudioPlaying {
            player.pause()
            isAudioPlaying = false
            audioStatusText = "Paused"
        } else {
            player.play()
            isAudioPlaying = true
            audioStatusText = "Streaming"
        }
    }

    func playPrevious() {
        guard !audioPlaylist.isEmpty else { return }
        currentAudioIndex = max(0, currentAudioIndex - 1)
        let item = audioPlaylist[currentAudioIndex]
        currentAudioItem = item
        startPlayback(item: item)
    }

    func playNext() {
        guard !audioPlaylist.isEmpty else { return }
        currentAudioIndex = min(audioPlaylist.count - 1, currentAudioIndex + 1)
        let item = audioPlaylist[currentAudioIndex]
        currentAudioItem = item
        startPlayback(item: item)
    }

    func stopAudio() {
        currentPlaybackTask?.cancel()
        isPreparingClipPlayback = false
        clipPlaybackStatusText = ""
        preparingClipEventID = nil
        teardownPlayer()
        loadingAudioURL = nil
        isAudioPlaying = false
        audioStatusText = "Stopped"
        currentAudioItem = nil
        audioPlaylist = []
        currentAudioIndex = 0
        cleanupTemporaryAudioFiles()
    }

    private func teardownPlayer() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        // Note: loadingAudioURL is NOT cleared here — callers that need to set a
        // new loading URL do so immediately after teardownPlayer(), and clearing it
        // here would race against that assignment. It is cleared by the KVO observer
        // once playback starts, and by stopAudio() on explicit stop.
    }

    private func cleanupTemporaryAudioFiles(except preserved: Set<URL> = []) {
        for url in temporaryAudioFiles where !preserved.contains(url) {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryAudioFiles = temporaryAudioFiles.intersection(preserved)
    }

    private func startPlayback(item: AudioQueueItem) {
        teardownPlayer()
        cleanupTemporaryAudioFiles(except: [item.url])
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            audioStatusText = "Audio session failed"
        }

        let newPlayer = AVPlayer(url: item.url)
        player = newPlayer
        currentAudioItem = item
        let isClip = temporaryAudioFiles.contains(item.url)
        audioStatusText = isClip ? "Playing downloaded clip" : "Connecting to hub relay…"
        if isClip {
            clipPlaybackStatusText = ""
            isPreparingClipPlayback = false
            preparingClipEventID = nil
        }
        isAudioPlaying = true
        newPlayer.play()

        // Clear loadingAudioURL as soon as playback rate becomes non-zero (buffering done)
        statusObserver?.invalidate()
        statusObserver = newPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if player.timeControlStatus == .playing {
                    self.loadingAudioURL = nil
                    self.audioStatusText = "Streaming"
                } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.audioStatusText = "Buffering…"
                }
            }
        }
    }

    private func handleNotifications(old: [ChainSummary], new: [ChainSummary]) {
        let oldMap = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newFaultIDs = Set(new.filter { $0.displayStatus == .fault }.map { $0.id })
        let oldFaultIDs = Set(old.filter { $0.displayStatus == .fault }.map { $0.id })

        for item in new {
            if let previous = oldMap[item.id] {
                if previous.displayStatus != .fault && item.displayStatus == .fault {
                    // Newly faulted
                    if chainNotificationsEnabled {
                        NotificationManager.shared.scheduleFaultNotification(chain: item)
                    }
                    captureRecentFault(item)
                    if #available(iOS 16.2, *) {
                        LiveActivityManager.shared.startOrUpdate(for: item)
                    }
                } else if item.displayStatus == .fault {
                    // Still faulted — update the Live Activity with fresh data
                    if #available(iOS 16.2, *) {
                        LiveActivityManager.shared.startOrUpdate(for: item)
                    }
                }
            } else if item.displayStatus == .fault {
                // New chain we haven't seen before, already faulted
                if chainNotificationsEnabled {
                    NotificationManager.shared.scheduleFaultNotification(chain: item)
                }
                captureRecentFault(item)
                if #available(iOS 16.2, *) {
                    LiveActivityManager.shared.startOrUpdate(for: item)
                }
            }
        }

        // End Live Activities for chains that have recovered
        for chainID in oldFaultIDs.subtracting(newFaultIDs) {
            if #available(iOS 16.2, *) {
                LiveActivityManager.shared.end(chainID: chainID, recovered: true)
            }
        }
    }

    // MARK: - Silence monitoring

    func toggleSilenceNode(_ label: String) {
        if silenceWatchedNodes.contains(label) {
            silenceWatchedNodes.remove(label)
        } else {
            silenceWatchedNodes.insert(label)
        }
        persistSilenceNodes()
    }

    private func checkSilenceAlerts() {
        guard silenceNotificationsEnabled, !silenceWatchedNodes.isEmpty else { return }
        let now = Date()
        for chain in chains {
            for node in chain.nodes.flattenedAll() {
                guard silenceWatchedNodes.contains(node.label) else { continue }
                guard let level = node.level_dbfs, level < silenceThresholdDbfs else { continue }
                let key = "\(chain.id)/\(node.label)"
                if let last = silenceAlertCooldown[key], now.timeIntervalSince(last) < silenceCooldown { continue }
                silenceAlertCooldown[key] = now
                NotificationManager.shared.scheduleSilenceNotification(
                    nodeName: node.label,
                    chainName: chain.name,
                    site: node.site ?? chain.dominantSite ?? "",
                    level: node.level_dbfs
                )
            }
        }
    }

    private func persistSilenceNodes() {
        if let data = try? JSONEncoder().encode(Array(silenceWatchedNodes).sorted()),
           let string = String(data: data, encoding: .utf8) {
            storedSilenceNodes = string
        }
    }

    private static func decodeStringSet(from stored: String) -> Set<String> {
        guard let data = stored.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    /// All unique node labels across all chains — used by the silence node picker.
    var allNodeLabels: [String] {
        Array(Set(chains.flatMap { $0.nodes.flattenedAll().map(\.label) })).sorted()
    }

    private func captureRecentFault(_ chain: ChainSummary) {
        let snapshot = RecentFaultSnapshot(chain: chain)
        recentFaults.insert(snapshot, at: 0)
        recentFaults = Array(recentFaults.prefix(25))
        persistRecentFaults()
    }

    private func persistAcknowledgedFaultIDs() {
        if let data = try? JSONEncoder().encode(Array(acknowledgedFaultIDs).sorted()),
           let string = String(data: data, encoding: .utf8) {
            storedAcknowledgedFaultIDs = string
        }
    }

    private func persistRecentFaults() {
        if let data = try? JSONEncoder().encode(recentFaults),
           let string = String(data: data, encoding: .utf8) {
            storedRecentFaults = string
        }
    }

    private func observeNotificationEvents() {
        NotificationCenter.default.addObserver(
            forName: .deviceTokenReceived, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let token = note.object as? String else { return }
            Task { await self.uploadAPNSToken(token) }
        }
        NotificationCenter.default.addObserver(
            forName: .navigateToChain, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let chainID = note.object as? String else { return }
            self.deepLinkChainID = chainID
            self.lastSelectedTab = 1  // switch to Faults tab
        }
        // Clear the app icon badge whenever the user brings the app to the foreground.
        // Without this, the badge persists indefinitely even after the user has read the alerts.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task {
                try? await UNUserNotificationCenter.current().setBadgeCount(0)
            }
        }
    }

    func uploadAPNSToken(_ token: String) async {
        guard !token.isEmpty, api.baseURL != nil else { return }
        // Always re-register on every launch. The server stores sandbox:false and
        // auto-corrects the environment on the first push via BadEnvironmentKeyInToken,
        // so re-uploading the same token is harmless and ensures stale/corrected
        // entries are always refreshed with the latest token from iOS.
        do {
            try await api.registerDeviceToken(token)
            storedAPNSToken = token
        } catch {
            print("[APNs] Token upload failed: \(error)")
        }
    }

    private static func decodeAcknowledgedIDs(from raw: String) -> Set<String> {
        guard let data = raw.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    private static func decodeRecentFaults(from raw: String) -> [RecentFaultSnapshot] {
        guard let data = raw.data(using: .utf8),
              let items = try? JSONDecoder().decode([RecentFaultSnapshot].self, from: data) else { return [] }
        return items
    }

    private static func decodeWatchlist(from raw: String) -> Set<String> {
        guard let data = raw.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
