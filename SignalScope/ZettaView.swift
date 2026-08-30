import SwiftUI

// MARK: - ZettaView

struct ZettaView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var response: ZettaStatusResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPluginMissing = false
    @State private var lastUpdated: Date?

    private let refreshInterval: TimeInterval = 5

    /// True when the app is connected to a client-only node (Zetta lives on the hub)
    private var isClientNode: Bool {
        guard let mode = appModel.hubOverview?.mode else { return false }
        return mode == "client"
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            Group {
                if isClientNode {
                    VStack(spacing: 16) {
                        Image(systemName: "network")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.brandBlue)
                        Text("Hub connection required")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("Zetta is a hub-only feature. Your app is currently pointed at a client node.\n\nUpdate your hub URL in Settings to connect directly to your SignalScope hub.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Open Settings") { appModel.lastSelectedTab = 4 }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.brandBlue)
                    }
                } else if isLoading && response == nil {
                    VStack(spacing: 12) {
                        ProgressView().tint(Theme.brandBlue).scaleEffect(1.3)
                        Text("Loading sequencers…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedText)
                    }
                } else if isPluginMissing {
                    VStack(spacing: 16) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.brandBlue)
                        Text("Zetta plugin not installed")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("Install or update the Zetta plugin to v2.1.27 or later via Settings → Plugins on your SignalScope hub.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Retry") { Task { await loadData() } }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.brandBlue)
                    }
                } else if let err = errorMessage, response == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.pendingAmber)
                        Text("Zetta unavailable")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Theme.mutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Retry") { Task { await loadData() } }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.brandBlue)
                    }
                } else if let resp = response {
                    if resp.instances.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "radio")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.mutedText)
                            Text("No Zetta instances configured")
                                .font(.subheadline)
                                .foregroundStyle(Theme.mutedText)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                if let updated = lastUpdated {
                                    HStack {
                                        Spacer()
                                        Text("Updated \(updated, style: .relative) ago")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.mutedText)
                                    }
                                    .padding(.horizontal, 2)
                                }
                                ForEach(resp.instances) { inst in
                                    ZettaInstanceCard(instance: inst)
                                }
                            }
                            .padding()
                        }
                        .refreshable { await loadData() }
                    }
                }
            }
        }
        .navigationTitle("Zetta")
        .navigationBarTitleDisplayMode(.inline)
        .task { await startPolling() }
    }

    // MARK: - Polling

    private func startPolling() async {
        while !Task.isCancelled {
            // Skip fetch entirely when connected to a client node — Zetta lives on the hub
            if !isClientNode {
                await loadData()
            }
            // Back off to 30 s when the plugin is missing — no need to spam 404s
            // Use 10 s when on a client node so we react quickly if the user changes hub URL
            let interval: TimeInterval
            if isClientNode          { interval = 10.0 }
            else if isPluginMissing  { interval = 30.0 }
            else                     { interval = refreshInterval }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func loadData() async {
        guard appModel.api.baseURL != nil else {
            errorMessage = "No hub URL configured"
            return
        }
        if response == nil { isLoading = true }
        do {
            let result   = try await appModel.api.fetchZettaStatus()
            response     = result
            errorMessage = nil
            isPluginMissing = false
            lastUpdated  = Date()
        } catch APIClient.ZettaError.pluginNotInstalled {
            isPluginMissing = true
            errorMessage    = nil
        } catch {
            if !(error is CancellationError) {
                isPluginMissing = false
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}

// MARK: - ZettaInstanceCard

private struct ZettaInstanceCard: View {
    let instance: ZettaInstance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Instance header
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.brandBlue)
                Text(instance.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                // Connected badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(instance.connected ? Theme.okGreen : Theme.faultRed)
                        .frame(width: 7, height: 7)
                    Text(instance.connected ? "Connected" : "Disconnected")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(instance.connected ? Theme.okGreen : Theme.faultRed)
                }
            }

            if let err = instance.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(Theme.pendingAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.pendingAmber.opacity(0.12))
                    )
            }

            if instance.stations.isEmpty {
                Text("No stations configured")
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)
                    .padding(.vertical, 6)
            } else {
                ForEach(instance.stations) { station in
                    ZettaStationRow(station: station)
                    if station.id != instance.stations.last?.id {
                        Divider()
                            .background(Theme.panelBorder)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.panelBorder, lineWidth: 1)
        )
    }
}

// MARK: - ZettaStationRow

private struct ZettaStationRow: View {
    let station: ZettaStation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Station header row
            HStack(spacing: 8) {
                Text(station.stationName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)

                Spacer()

                // Ad break badge — ALWAYS uses asset_type == 2 check
                if station.isAdBreakActive {
                    Text("AD BREAK")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.pendingAmber))
                } else {
                    // Mode pill
                    Text(station.modeName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.brandBlue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Theme.brandBlue.opacity(0.15))
                        )
                }
            }

            // Computer name
            if let computer = station.computerName, !computer.isEmpty {
                Text(computer)
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedText)
            }

            // Now playing
            if let np = station.nowPlaying {
                ZettaNowPlayingRow(track: np, isCurrentlyPlaying: true)
            } else if let err = station.error, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)
                    .italic()
            }

            // Progress bar (only when something is playing and duration > 0)
            if station.nowPlaying != nil && station.durationSeconds > 0 {
                ZettaProgressBar(
                    fraction: station.progressFraction,
                    remaining: station.remainingSeconds,
                    isAdBreak: station.isAdBreakActive
                )
            }

            // GAP / ETM row
            HStack(spacing: 16) {
                ZettaMetricPair(label: "GAP", value: station.gap)
                ZettaMetricPair(label: "ETM", value: station.etm)
                Spacer()
                Text(station.statusName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(station.statusName == "PLAYING" ? Theme.okGreen : Theme.mutedText)
            }

            // Queue
            if !station.queue.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT UP")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.mutedText)
                    ForEach(Array(station.queue.enumerated()), id: \.offset) { _, item in
                        ZettaNowPlayingRow(track: item, isCurrentlyPlaying: false)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ZettaNowPlayingRow

private struct ZettaNowPlayingRow: View {
    let track: ZettaTrack
    let isCurrentlyPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Playing indicator or queue dot
            if isCurrentlyPlaying {
                Image(systemName: "music.note")
                    .font(.caption2)
                    .foregroundStyle(track.isAdBreak ? Theme.pendingAmber : Theme.brandBlue)
                    .frame(width: 14)
            } else {
                Circle()
                    .fill(Theme.mutedText.opacity(0.4))
                    .frame(width: 5, height: 5)
                    .padding(.leading, 4)
                    .frame(width: 14)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title.isEmpty ? "—" : track.title)
                    .font(isCurrentlyPlaying ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(isCurrentlyPlaying ? Theme.primaryText : Theme.secondaryText)
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.caption2)
                        .foregroundStyle(Theme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if track.durationSeconds > 0 {
                Text(formatDuration(track.durationSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.mutedText)
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - ZettaProgressBar

private struct ZettaProgressBar: View {
    let fraction: Double
    let remaining: Double
    let isAdBreak: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.panelSecondary)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isAdBreak ? Theme.pendingAmber : Theme.brandBlue)
                        .frame(width: max(4, geo.size.width * fraction), height: 4)
                }
            }
            .frame(height: 4)

            Text(formatRemaining(remaining))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.mutedText)
        }
    }

    private func formatRemaining(_ secs: Double) -> String {
        let total = Int(max(0, secs))
        let m = total / 60
        let s = total % 60
        return String(format: "-%d:%02d", m, s)
    }
}

// MARK: - ZettaMetricPair

private struct ZettaMetricPair: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.mutedText)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.primaryText)
        }
    }
}
