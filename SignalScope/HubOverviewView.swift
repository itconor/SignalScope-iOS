import SwiftUI

struct HubOverviewView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var expandedSites: Set<String> = []
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            Group {
                if appModel.isInitialLoad && appModel.hubOverview == nil {
                    loadingView
                } else if let error = appModel.hubOverviewError, appModel.hubOverview == nil {
                    errorView(message: error)
                } else {
                    contentList
                }
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Sites")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: HubStreamRef.self) { ref in
                SignalHistoryView(streamName: ref.stream.name, siteName: ref.siteName)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if appModel.isLoading {
                        ProgressView().tint(Theme.brandBlue)
                    } else {
                        Button {
                            Task { await appModel.refreshHubOverview() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Theme.brandBlue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Content

    private var contentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let overview = appModel.hubOverview {
                    summaryCard(overview.summary)

                    if overview.sites.isEmpty {
                        emptyState
                    } else {
                        ForEach(overview.sites) { site in
                            SiteCard(
                                site: site,
                                isExpanded: expandedSites.contains(site.id),
                                baseURL: appModel.api.baseURL
                            ) {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    if expandedSites.contains(site.id) {
                                        expandedSites.remove(site.id)
                                    } else {
                                        expandedSites.insert(site.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await appModel.refreshHubOverview()
        }
    }

    // MARK: - Summary Card

    private func summaryCard(_ s: HubSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                summaryTile(
                    value: "\(s.online_sites)",
                    label: "Online",
                    color: Theme.okGreen
                )
                Divider().frame(height: 44).background(Theme.panelBorder)
                summaryTile(
                    value: "\(s.offline_sites)",
                    label: "Offline",
                    color: s.offline_sites > 0 ? Theme.mutedText : Theme.secondaryText
                )
                Divider().frame(height: 44).background(Theme.panelBorder)
                summaryTile(
                    value: "\(s.total_alert)",
                    label: "Alerts",
                    color: s.total_alert > 0 ? Theme.faultRed : Theme.secondaryText
                )
                Divider().frame(height: 44).background(Theme.panelBorder)
                summaryTile(
                    value: "\(s.total_warn)",
                    label: "Warnings",
                    color: s.total_warn > 0 ? Theme.pendingAmber : Theme.secondaryText
                )
                Divider().frame(height: 44).background(Theme.panelBorder)
                summaryTile(
                    value: "\(s.total_streams)",
                    label: "Streams",
                    color: Theme.brandBlue
                )
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.panelBorder, lineWidth: 1)
        )
    }

    private func summaryTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Theme.brandBlue).scaleEffect(1.4)
            Text("Loading sites…")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(Theme.mutedText)
            Text("Could not load sites")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await appModel.refreshHubOverview() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brandBlue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundStyle(Theme.mutedText)
            Text("No sites connected")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Client sites will appear here once they connect to this hub.")
                .font(.caption)
                .foregroundStyle(Theme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Site Card

private struct SiteCard: View {
    @EnvironmentObject private var appModel: AppModel
    let site: HubSite
    let isExpanded: Bool
    let baseURL: URL?
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ────────────────────────────────────────────────
            Button(action: onTap) {
                HStack(spacing: 10) {
                    // Status dot
                    Circle()
                        .fill(site.statusColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: site.statusColor.opacity(0.6), radius: 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.site)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(site.lastSeenLabel)
                                .font(.caption2)
                                .foregroundStyle(Theme.mutedText)
                            if let lat = site.latencyLabel {
                                Text("·")
                                    .foregroundStyle(Theme.mutedText)
                                Text(lat)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.mutedText)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    // Health percentage (Feature 6)
                    if let health = site.health_pct {
                        Text(String(format: "%.0f%%", health))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(healthColor(health))
                    }

                    // Alert/warn/ok counts
                    HStack(spacing: 5) {
                        if site.alert_count > 0 {
                            countBadge("\(site.alert_count)", color: Theme.faultRed)
                        }
                        if site.warn_count > 0 {
                            countBadge("\(site.warn_count)", color: Theme.pendingAmber)
                        }
                        if site.ok_count > 0 {
                            countBadge("\(site.ok_count)", color: Theme.okGreen)
                        }
                        if !site.online {
                            Text("OFFLINE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.mutedText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Theme.mutedText.opacity(0.15))
                                )
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.mutedText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // ── Expanded stream list ───────────────────────────────────────
            if isExpanded {
                Divider()
                    .background(Theme.panelBorder)
                    .padding(.horizontal, 12)

                if site.streams.isEmpty {
                    Text("No streams")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(site.streams) { stream in
                            HStack(spacing: 0) {
                                NavigationLink(value: HubStreamRef(siteName: site.site, stream: stream)) {
                                    StreamRow(stream: stream)
                                }
                                .buttonStyle(.plain)

                                // Quick-listen play button (Feature 2)
                                if let liveURLPath = stream.live_url {
                                    quickListenButton(for: stream, urlPath: liveURLPath, siteName: site.site)
                                }
                            }
                            if stream.id != site.streams.last?.id {
                                Divider()
                                    .background(Theme.panelBorder.opacity(0.5))
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    site.alert_count > 0 ? Theme.faultRed.opacity(0.5) :
                    site.warn_count  > 0 ? Theme.pendingAmber.opacity(0.4) :
                    Theme.panelBorder,
                    lineWidth: 1
                )
        )
        .shadow(
            color: site.alert_count > 0 ? Theme.faultRed.opacity(0.12) : .black.opacity(0.08),
            radius: site.alert_count > 0 ? 8 : 4
        )
    }

    private func quickListenButton(for stream: HubStream, urlPath: String, siteName: String) -> some View {
        Button {
            guard let base = baseURL,
                  let url = URL(string: urlPath, relativeTo: base)?.absoluteURL else { return }
            appModel.playAudio(
                url: url,
                title: stream.name,
                subtitle: siteName,
                playlist: [],
                index: 0
            )
        } label: {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.brandBlue)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 14)
    }

    private func healthColor(_ pct: Double) -> Color {
        if pct >= 90 { return Theme.okGreen }
        if pct >= 70 { return Theme.pendingAmber }
        return Theme.faultRed
    }

    private func countBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
    }
}

// MARK: - Stream Row

private struct StreamRow: View {
    let stream: HubStream

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stream.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.mutedText)
                }

                // RDS / DAB station name
                if let station = stream.stationName {
                    Text(station)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.brandBlue)
                        .lineLimit(1)
                }

                // Now-playing / DLS text
                if let nowPlaying = stream.nowPlayingText {
                    Text(nowPlaying)
                        .font(.caption2)
                        .foregroundStyle(Theme.mutedText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    if !stream.format.isEmpty {
                        Text(stream.format.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.brandBlue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.brandBlue.opacity(0.12))
                            )
                    }
                    if let sla = stream.sla_pct {
                        Text(String(format: "SLA %.1f%%", sla))
                            .font(.caption2)
                            .foregroundStyle(sla >= 99 ? Theme.okGreen : Theme.pendingAmber)
                    }
                    if let rtpLabel = stream.rtpLossLabel {
                        Text(rtpLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(stream.rtpLossColor)
                    }
                    // RTP Jitter (Feature 3)
                    if let jitterLabel = stream.rtpJitterLabel {
                        Text(jitterLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(stream.rtpJitterColor)
                    }
                    if let glitchLabel = stream.glitchLabel {
                        Text(glitchLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.orange)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                // Level bar
                levelBar

                // AI badge
                Text(stream.aiStatusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(stream.aiStatusColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(stream.aiStatusColor.opacity(0.15))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var levelBar: some View {
        VStack(alignment: .trailing, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.07))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(stream.levelColor)
                        .frame(width: geo.size.width * stream.levelFraction)
                }
            }
            .frame(width: 72, height: 5)
            .clipShape(RoundedRectangle(cornerRadius: 2))

            if let level = stream.level_dbfs {
                Text(String(format: "%.1f dB", level))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.mutedText)
            } else {
                Text("—")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.mutedText)
            }
        }
    }
}
