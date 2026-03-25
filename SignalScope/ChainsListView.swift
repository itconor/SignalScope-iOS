import SwiftUI

struct ChainsListView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var searchText = ""
    @State private var selectedGroup: GroupMode = .none
    @State private var activeFilters: Set<ChainFilter> = []

    enum GroupMode: String, CaseIterable, Identifiable {
        case none = "None"
        case site = "Site"
        case status = "Status"
        var id: String { rawValue }
    }

    enum ChainFilter: String, CaseIterable, Identifiable {
        case fault = "Fault"
        case flapping = "Flapping"
        case maintenance = "Maintenance"
        case adbreak = "Adbreak"
        case stale = "Stale"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .fault: return "exclamationmark.triangle"
            case .flapping: return "arrow.triangle.2.circlepath"
            case .maintenance: return "wrench.and.screwdriver"
            case .adbreak: return "play.rectangle"
            case .stale: return "clock.badge.exclamationmark"
            }
        }
    }

    private var watchedChains: [ChainSummary] {
        appModel.sortedChains.filter { appModel.isWatched($0.id) }
    }

    private var filteredChains: [ChainSummary] {
        appModel.sortedChains.filter { chain in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty || [
                chain.name,
                chain.fault_at ?? "",
                chain.fault_reason ?? "",
                chain.siteGroups.joined(separator: " "),
                chain.nodes.flatMap { [$0.label, $0.stream ?? "", $0.machine ?? ""] }.joined(separator: " ")
            ].joined(separator: " ").localizedCaseInsensitiveContains(query)

            let matchesFilters = activeFilters.allSatisfy { filter in
                switch filter {
                case .fault: return chain.displayStatus == .fault
                case .flapping: return chain.flapping
                case .maintenance: return chain.maintenance
                case .adbreak: return chain.adbreak || chain.pending
                case .stale: return chain.isStale
                }
            }
            return matchesSearch && matchesFilters
        }
    }

    private var groupedChains: [(String, [ChainSummary])] {
        switch selectedGroup {
        case .none:
            return [("All Chains", filteredChains)]
        case .site:
            let grouped = Dictionary(grouping: filteredChains) { $0.dominantSite ?? "Unassigned" }
            return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
        case .status:
            let grouped = Dictionary(grouping: filteredChains) { $0.displayStatus.label }
            return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if filteredChains.isEmpty, !appModel.isLoading {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12, pinnedViews: []) {
                            headerSummary
                            controlPanel

                            if let error = appModel.errorMessage {
                                errorBanner(error)
                            }

                            // Pinned / watchlist section (Feature 9)
                            if !watchedChains.isEmpty {
                                sectionHeader("Pinned", count: watchedChains.count)
                                ForEach(watchedChains) { chain in
                                    NavigationLink(value: chain) {
                                        ChainRowView(chain: chain, isWatched: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            ForEach(groupedChains, id: \.0) { section in
                                if selectedGroup != .none {
                                    sectionHeader(section.0, count: section.1.count)
                                }
                                ForEach(section.1) { chain in
                                    NavigationLink(value: chain) {
                                        ChainRowView(chain: chain, isWatched: appModel.isWatched(chain.id))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await appModel.fetchChains()
                    }
                }
            }
            .navigationTitle("Chains")
            .navigationDestination(for: ChainSummary.self) { chain in
                ChainDetailView(chainID: chain.id, initialChain: chain)
            }
            .navigationDestination(for: HubStreamRef.self) { ref in
                SignalHistoryView(streamName: ref.stream.name, siteName: ref.siteName)
            }
            .searchable(text: $searchText, prompt: "Search chains, sites, nodes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if appModel.isLoading {
                        ProgressView().tint(Theme.brandBlue)
                    }
                }
            }
        }
        .task {
            if appModel.chains.isEmpty {
                await appModel.fetchChains()
            }
        }
    }

    private var headerSummary: some View {
        PanelCard {
            HStack(spacing: 10) {
                summaryBubble(title: "Faults", value: "\(appModel.displayedFaults.count)", color: Theme.faultRed)
                summaryBubble(title: "Flapping", value: "\(appModel.chains.filter { $0.flapping }.count)", color: Theme.pendingAmber)
                summaryBubble(title: "Maintenance", value: "\(appModel.chains.filter { $0.maintenance }.count)", color: Theme.mutedText)
                summaryBubble(title: "Stale", value: "\(appModel.chains.filter { $0.isStale }.count)", color: Theme.brandBlue)
            }
        }
    }

    private var controlPanel: some View {
        PanelCard(title: "View") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Fault-first sorting", isOn: $appModel.faultFirstSortEnabled)
                    .tint(Theme.brandBlue)
                    .foregroundStyle(Theme.primaryText)

                Picker("Group", selection: $selectedGroup) {
                    ForEach(GroupMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ChainFilter.allCases) { filter in
                            let isOn = activeFilters.contains(filter)
                            Button {
                                if isOn { activeFilters.remove(filter) } else { activeFilters.insert(filter) }
                            } label: {
                                Label(filter.rawValue, systemImage: filter.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isOn ? Color.black : Theme.primaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(isOn ? Theme.brandBlue : Theme.panelSecondary.opacity(0.8)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func summaryBubble(title: String, value: String, color: Color) -> some View {
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 46))
                .foregroundStyle(Theme.brandBlue)

            Text("No matching chains")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)

            Text(appModel.errorMessage ?? "Try changing filters or add your Hub URL and token in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal)
        }
        .padding()
    }

    private func errorBanner(_ text: String) -> some View {
        PanelCard {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.faultRed.opacity(0.8), lineWidth: 1))
    }
}

private struct ChainRowView: View {
    @EnvironmentObject private var appModel: AppModel
    let chain: ChainSummary
    var isWatched: Bool = false

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chain.name)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)

                        Text(chain.dominantSite ?? chain.healthLabel)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Spacer()
                    StatusPill(status: chain.displayStatus)

                    Button {
                        appModel.toggleWatchlist(chain.id)
                    } label: {
                        Image(systemName: isWatched ? "star.fill" : "star")
                            .font(.subheadline)
                            .foregroundStyle(isWatched ? Theme.pendingAmber : Theme.mutedText)
                    }
                    .buttonStyle(.plain)
                }

                ChainDiagramStrip(nodes: chain.diagramNodes)

                HStack(spacing: 8) {
                    MetricChip(icon: "clock", text: chain.isStale ? "Stale \(chain.age_secs.formattedSeconds())" : "Age \(chain.age_secs.formattedSeconds())")
                    MetricChip(icon: "chart.line.uptrend.xyaxis", text: "SLA \(chain.sla_pct.formattedPercent())")
                    if let healthDisplay = chain.healthScoreDisplay {
                        MetricChip(icon: "heart.text.square", text: healthDisplay)
                    }
                }

                if !chain.activeFlags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(chain.activeFlags, id: \.self) { flag in
                            MetricChip(icon: iconName(for: flag), text: chipText(for: flag, chain: chain))
                        }
                    }
                }

                Text(chain.headlineReason)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.mutedText)
            }
        }
    }

    private func iconName(for flag: String) -> String {
        switch flag {
        case "Pending": return "hourglass"
        case "Adbreak": return "play.rectangle"
        case "Maintenance": return "wrench.and.screwdriver"
        case "Flapping": return "arrow.triangle.2.circlepath"
        default: return "circle"
        }
    }

    private func chipText(for flag: String, chain: ChainSummary) -> String {
        if flag == "Adbreak" {
            let remaining = chain.adbreak_remaining.map { $0.formattedSeconds() } ?? "Live"
            return "Adbreak \(remaining)"
        }
        return flag
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
            Spacer(minLength: 0)
        }
    }
}
