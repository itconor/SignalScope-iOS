import SwiftUI

struct FaultsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if appModel.displayedFaults.isEmpty, !appModel.isLoading {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            faultSummary

                            if !appModel.recentFaults.isEmpty {
                                recentFaultsCard
                            }

                            ForEach(appModel.displayedFaults) { chain in
                                NavigationLink(value: chain) {
                                    FaultRowView(chain: chain) {
                                        appModel.acknowledgeFault(chain.id)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await appModel.fetchChains() }
                }
            }
            .navigationTitle("Active Faults")
            .navigationDestination(for: ChainSummary.self) { chain in
                ChainDetailView(chainID: chain.id, initialChain: chain)
            }
            .navigationDestination(for: HubStreamRef.self) { ref in
                SignalHistoryView(streamName: ref.stream.name, siteName: ref.siteName)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if appModel.isLoading {
                        ProgressView().tint(Theme.brandBlue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !appModel.acknowledgedFaultIDs.isEmpty {
                        Button("Show all") {
                            appModel.clearAcknowledgedFaults()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
        // Handle notification tap → navigate to the specific chain
        .onChange(of: appModel.deepLinkChainID) { _, chainID in
            guard let chainID else { return }
            navigationPath.removeLast(navigationPath.count)
            if let chain = appModel.chains.first(where: { $0.id == chainID })
                          ?? appModel.activeFaults.first(where: { $0.id == chainID }) {
                navigationPath.append(chain)
            }
            appModel.deepLinkChainID = nil
        }
    }

    private var faultSummary: some View {
        PanelCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(appModel.displayedFaults.count) active fault\(appModel.displayedFaults.count == 1 ? "" : "s")")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text("Youngest issue first. You can acknowledge a fault locally on this device.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.faultRed)
            }
        }
    }

    private var recentFaultsCard: some View {
        PanelCard(title: "Recent Faults") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(appModel.recentFaults.prefix(5)) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.chainName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(item.reason)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Text(item.capturedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(Theme.mutedText)
                    }
                    if item.id != appModel.recentFaults.prefix(5).last?.id {
                        Divider().overlay(Theme.panelBorder.opacity(0.35))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 46))
                .foregroundStyle(Theme.okGreen)

            Text("No active faults")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)

            Text(appModel.errorMessage ?? "Everything currently looks healthy.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal)
        }
        .padding()
    }
}

private struct FaultRowView: View {
    let chain: ChainSummary
    let acknowledge: () -> Void

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chain.name)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        if let faultAt = chain.fault_at, !faultAt.isEmpty {
                            Text("Fault at \(faultAt)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Spacer()
                    StatusPill(status: chain.displayStatus)
                }

                HStack(spacing: 8) {
                    MetricChip(icon: "clock", text: chain.age_secs.formattedSeconds())
                    MetricChip(icon: "chart.line.uptrend.xyaxis", text: "SLA \(chain.sla_pct.formattedPercent())")
                    if chain.flapping { MetricChip(icon: "arrow.triangle.2.circlepath", text: "Flapping") }
                    if chain.isStale { MetricChip(icon: "clock.badge.exclamationmark", text: "Stale") }
                }

                Text(chain.headlineReason)
                    .font(.footnote)
                    .foregroundStyle(Theme.primaryText)

                HStack {
                    Spacer()
                    Button("Acknowledge") {
                        acknowledge()
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.brandBlue)
                    .font(.footnote.weight(.semibold))
                }
            }
        }
    }
}


struct ReportsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var searchText = ""
    @State private var selectedSite = "All Sites"
    @State private var selectedType = "All Types"
    @State private var clipsOnly = false

    private var filteredEvents: [ReportEvent] {
        appModel.reportEvents.filter { event in
            let matchesSearch: Bool = {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return [event.site, event.chain, event.stream, event.type, event.message].joined(separator: " ").localizedCaseInsensitiveContains(query)
            }()
            let matchesSite = selectedSite == "All Sites" || event.site == selectedSite
            let matchesType = selectedType == "All Types" || event.type == selectedType
            let matchesClip = !clipsOnly || event.clip
            return matchesSearch && matchesSite && matchesType && matchesClip
        }
    }

    private var siteOptions: [String] {
        let values = Set(appModel.reportEvents.map(\.site).filter { !$0.isEmpty })
        return ["All Sites"] + values.sorted()
    }

    private var typeOptions: [String] {
        let values = Set(appModel.reportEvents.map(\.type).filter { !$0.isEmpty })
        return ["All Types"] + values.sorted()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if filteredEvents.isEmpty, !appModel.isLoading {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 46))
                            .foregroundStyle(Theme.brandBlue)
                        Text("No reports to show")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(appModel.reportsErrorMessage ?? "Pull to refresh or adjust your filters.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            reportsSummaryCard
                            filtersCard

                            if let error = appModel.reportsErrorMessage {
                                PanelCard {
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.primaryText)
                                }
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.faultRed.opacity(0.8), lineWidth: 1))
                            }

                            ForEach(filteredEvents) { event in
                                ReportEventCard(
                                    event: event,
                                    isPreparingClip: appModel.isPreparingClipPlayback && appModel.preparingClipEventID == event.id,
                                    preparingText: appModel.clipPlaybackStatusText,
                                    playClip: {
                                        appModel.playClip(for: event)
                                    }
                                )
                            }

                            // Load More — only visible when no active filters narrow the list
                            if appModel.hasMoreReports, searchText.isEmpty,
                               selectedSite == "All Sites", selectedType == "All Types", !clipsOnly {
                                Button {
                                    Task { await appModel.loadMoreReports() }
                                } label: {
                                    if appModel.isLoadingMoreReports {
                                        HStack(spacing: 8) {
                                            ProgressView().tint(Theme.brandBlue)
                                            Text("Loading…")
                                                .font(.subheadline)
                                                .foregroundStyle(Theme.secondaryText)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                    } else {
                                        Text("Load more events")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.brandBlue)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(appModel.isLoadingMoreReports)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await appModel.refreshReports() }
                }
            }
            .navigationTitle("Reports")
            .searchable(text: $searchText, prompt: "Search sites, streams, messages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if appModel.isLoading {
                        ProgressView().tint(Theme.brandBlue)
                    }
                }
            }
        }
        .task {
            if appModel.reportEvents.isEmpty {
                await appModel.refreshReports()
            }
        }
    }

    private var reportsSummaryCard: some View {
        PanelCard(title: "Summary") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    reportBubble(title: "Events", value: "\(appModel.reportsSummary?.total ?? appModel.reportEvents.count)", color: Theme.brandBlue)
                    reportBubble(title: "Clips", value: "\(appModel.reportsSummary?.with_clips ?? appModel.reportEvents.filter(\.clip).count)", color: Theme.pendingAmber)
                    reportBubble(title: "Sites", value: "\(appModel.reportsSummary?.sites.count ?? Set(appModel.reportEvents.map(\.site)).count)", color: Theme.okGreen)
                }
                if let counts = appModel.reportsSummary?.counts, !counts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(counts.keys.sorted(), id: \.self) { key in
                                MetricChip(icon: "chart.bar.doc.horizontal", text: "\(key) \(counts[key] ?? 0)")
                            }
                        }
                    }
                }
            }
        }
    }

    private var filtersCard: some View {
        PanelCard(title: "Filters") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Site", selection: $selectedSite) {
                    ForEach(siteOptions, id: \.self) { site in
                        Text(site).tag(site)
                    }
                }
                .pickerStyle(.menu)

                Picker("Type", selection: $selectedType) {
                    ForEach(typeOptions, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Clips only", isOn: $clipsOnly)
                    .tint(Theme.brandBlue)
                    .foregroundStyle(Theme.primaryText)
            }
        }
    }

    private func reportBubble(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.55), lineWidth: 1))
    }
}

private struct ReportEventCard: View {
    let event: ReportEvent
    let isPreparingClip: Bool
    let preparingText: String
    let playClip: () -> Void

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.headlineText)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text([event.site, event.stream.isEmpty ? nil : event.stream].compactMap { $0 }.joined(separator: " • "))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Text(event.type.replacingOccurrences(of: "_", with: " "))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(event.clip ? Theme.pendingAmber : Theme.brandBlue))
                }

                if !event.chain.isEmpty {
                    Text(event.chain)
                        .font(.footnote)
                        .foregroundStyle(Theme.primaryText)
                }

                Text(event.timestampLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)

                if !event.metrics.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(event.metrics, id: \.self) { metric in
                                MetricChip(icon: metric.icon, text: metric.text)
                            }
                        }
                    }
                }

                HStack {
                    if let ptpState = event.ptp_state, !ptpState.isEmpty {
                        Text("PTP: \(ptpState)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if event.clip {
                        Button {
                            playClip()
                        } label: {
                            HStack(spacing: 8) {
                                if isPreparingClip {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "play.circle.fill")
                                }
                                Text(isPreparingClip ? (preparingText.isEmpty ? "Preparing clip…" : preparingText) : "Play clip")
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandBlue)
                        .disabled(isPreparingClip)
                    }
                }
            }
        }
    }
}
