import SwiftUI
import AVFoundation

struct ChainDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    let chainID: String
    let initialChain: ChainSummary

    @State private var chain: ChainSummary
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var jumpTargetID: String?
    @State private var expandAll = true

    // Fault history & notes
    @State private var faultLog: [FaultLogEntry] = []
    @State private var faultLogLoaded = false
    @State private var faultLogExpanded = false
    @State private var noteEntry: FaultLogEntry?
    @State private var noteText = ""
    @State private var noteSaving = false
    @State private var noteError: String?

    // Maintenance toggle (Feature 8)
    @State private var showMaintenanceConfirm = false
    @State private var isTogglingMaintenance = false
    @State private var maintenanceError: String?

    init(chainID: String, initialChain: ChainSummary) {
        self.chainID = chainID
        self.initialChain = initialChain
        _chain = State(initialValue: initialChain)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summaryCard(proxy: proxy)
                    nodesCard
                    faultHistoryCard
                }
                .padding()
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(chain.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if chain.displayStatus == .fault {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.faultRed)
                            .labelStyle(.titleAndIcon)
                    }

                    // Star / watchlist toggle (Feature 9)
                    Button {
                        appModel.toggleWatchlist(chainID)
                    } label: {
                        Image(systemName: appModel.isWatched(chainID) ? "star.fill" : "star")
                            .foregroundStyle(appModel.isWatched(chainID) ? Theme.pendingAmber : Theme.mutedText)
                    }

                    // Maintenance toggle (Feature 8)
                    Button {
                        showMaintenanceConfirm = true
                    } label: {
                        Image(systemName: chain.maintenance ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                            .foregroundStyle(chain.maintenance ? Theme.pendingAmber : Theme.mutedText)
                    }
                    .disabled(isTogglingMaintenance)

                    Button(expandAll ? "Collapse" : "Expand") {
                        expandAll.toggle()
                    }
                    .font(.footnote.weight(.semibold))

                    if isLoading || isTogglingMaintenance {
                        ProgressView().tint(Theme.brandBlue)
                    }
                }
            }
            .confirmationDialog(
                chain.maintenance ? "Clear Maintenance Mode?" : "Enable Maintenance Mode?",
                isPresented: $showMaintenanceConfirm,
                titleVisibility: .visible
            ) {
                Button(chain.maintenance ? "Clear maintenance" : "Enable for 1 hour", role: chain.maintenance ? .destructive : .none) {
                    Task { await toggleMaintenance() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(chain.maintenance
                     ? "This will resume normal fault monitoring for all nodes in \(chain.name)."
                     : "This will suppress faults for all nodes in \(chain.name) for 1 hour.")
            }
            .refreshable { await loadDetail() }
            // Poll every 3 s while this view is open — user is actively watching.
            .task {
                await loadDetail()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if !Task.isCancelled { await loadDetail() }
                }
            }
            // Also pick up list-level updates from the AppModel background poll immediately.
            .onChange(of: appModel.chains) { _, newChains in
                if let updated = newChains.first(where: { $0.id == chainID }) {
                    // Merge top-level status — detail fetch keeps the richer node data
                    chain = chain.merging(summary: updated)
                }
            }
            .onChange(of: jumpTargetID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func summaryCard(proxy: ScrollViewProxy) -> some View {
        PanelCard(title: "Chain Summary") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chain.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(chain.healthLabel)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    StatusPill(status: chain.displayStatus)
                }

                ChainDiagramStrip(nodes: chain.diagramNodes)
                FlowChipRow(items: summaryChips)

                if chain.isStale {
                    Label("Telemetry is stale (\(chain.age_secs.formattedSeconds()))", systemImage: "clock.badge.exclamationmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.pendingAmber)
                }

                if let faultAt = chain.fault_at, !faultAt.isEmpty {
                    HStack(spacing: 10) {
                        Label("Fault at \(faultAt)", systemImage: "bolt.trianglebadge.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        if let targetID = chain.faultNodeID {
                            Button("Jump to node") {
                                jumpTargetID = targetID
                                withAnimation(.easeInOut) { proxy.scrollTo(targetID, anchor: .center) }
                            }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.brandBlue)
                        }
                    }
                }

                Text(chain.headlineReason)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.faultRed)
                }

                if let maintenanceError {
                    Text(maintenanceError)
                        .font(.footnote)
                        .foregroundStyle(Theme.faultRed)
                }
            }
        }
    }

    private var nodesCard: some View {
        PanelCard(title: "Nodes") {
            if chain.nodes.isEmpty {
                Text("No node data returned by the API.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Use offset as the ForEach key — stack nodes have no stream/site/machine
                    // so node.id is identical for all stacks, causing SwiftUI to reuse the
                    // first view for every subsequent stack.  Position in the chain is the
                    // true identity; the .id(node.id) modifier on NodeTreeView is kept so
                    // scrollTo(faultNodeID) continues to work correctly.
                    ForEach(Array(chain.nodes.enumerated()), id: \.offset) { _, node in
                        NodeTreeView(
                            node: node,
                            depth: 0,
                            baseURL: appModel.api.baseURL,
                            faultLabel: chain.fault_at,
                            maintenanceNodes: Set(chain.maintenance_nodes),
                            expandAll: expandAll,
                            loadingAudioURL: appModel.loadingAudioURL,
                            onPlayAudio: handlePlayAudio
                        )
                    }
                }
            }
        }
    }

    private func handlePlayAudio(_ node: ChainNode, _ url: URL) {
        let playableNodes = chain.nodes.flatMap { $0.flattenedPlayableNodes(baseURL: appModel.api.baseURL) }
        let current = playableNodes.firstIndex { $0.url == url } ?? 0
        appModel.playAudio(
            url: url,
            title: node.label,
            subtitle: node.site ?? node.stream,
            playlist: playableNodes,
            index: current
        )
    }

    private var summaryChips: [MetricChipData] {
        var items: [MetricChipData] = [
            .init(icon: "clock", text: "Age \(chain.age_secs.formattedSeconds())"),
            .init(icon: "chart.line.uptrend.xyaxis", text: "SLA \(chain.sla_pct.formattedPercent())"),
            .init(icon: "point.3.connected.trianglepath.dotted", text: "\(chain.nodeCount) nodes")
        ]
        if let healthDisplay = chain.healthScoreDisplay {
            items.append(.init(icon: "heart.text.square", text: healthDisplay))
        }
        if chain.pending { items.append(.init(icon: "hourglass", text: "Pending")) }
        if chain.adbreak {
            let remaining = chain.adbreak_remaining.map { $0.formattedSeconds() } ?? "Live"
            items.append(.init(icon: "play.rectangle", text: "Adbreak \(remaining)"))
        }
        if chain.maintenance { items.append(.init(icon: "wrench.and.screwdriver", text: "Maintenance")) }
        if chain.flapping { items.append(.init(icon: "arrow.triangle.2.circlepath", text: "Flapping")) }
        return items
    }

    private func loadDetail() async {
        guard appModel.api.baseURL != nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            chain = try await appModel.api.fetchChainDetail(id: chainID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleMaintenance() async {
        isTogglingMaintenance = true
        defer { isTogglingMaintenance = false }
        do {
            _ = try await appModel.api.toggleMaintenance(chainID: chainID, enable: !chain.maintenance)
            maintenanceError = nil
            // Refresh chain to reflect new state
            await loadDetail()
        } catch {
            maintenanceError = "Maintenance toggle failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Fault History & Engineer Notes

    private var faultHistoryCard: some View {
        PanelCard(title: "Fault History") {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    faultLogExpanded.toggle()
                    if faultLogExpanded && !faultLogLoaded {
                        Task { await loadFaultLog() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: faultLogExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.mutedText)
                        Text(faultLogLoaded
                             ? "\(faultLog.count) fault event\(faultLog.count == 1 ? "" : "s")"
                             : "Show fault history")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if faultLogExpanded {
                    if faultLog.isEmpty && faultLogLoaded {
                        Text("No faults recorded yet.")
                            .font(.footnote)
                            .foregroundStyle(Theme.mutedText)
                            .padding(.top, 10)
                    } else if faultLog.isEmpty {
                        HStack { Spacer(); ProgressView().tint(Theme.brandBlue); Spacer() }
                            .padding(.top, 10)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(faultLog) { entry in
                                FaultLogRow(entry: entry) {
                                    noteEntry = entry
                                    noteText = entry.note ?? ""
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
        .sheet(item: $noteEntry) { entry in
            NoteEditorSheet(
                entry: entry,
                noteText: $noteText,
                isSaving: $noteSaving,
                errorMessage: $noteError
            ) { text in
                await saveNote(for: entry, text: text)
            }
        }
    }

    private func loadFaultLog() async {
        do {
            faultLog = try await appModel.api.fetchChainFaultLog(chainId: chainID)
            faultLogLoaded = true
        } catch {
            faultLogLoaded = true  // stop spinner even on failure
        }
    }

    private func saveNote(for entry: FaultLogEntry, text: String) async {
        noteSaving = true
        noteError = nil
        do {
            _ = try await appModel.api.saveChainNote(faultLogId: entry.id, text: text)
            // Rebuild the entry with the saved note text
            if let idx = faultLog.firstIndex(where: { $0.id == entry.id }) {
                faultLog[idx] = FaultLogEntry(
                    id: entry.id, chain_id: entry.chain_id,
                    ts_start: entry.ts_start, ts_recovered: entry.ts_recovered,
                    fault_node_label: entry.fault_node_label, fault_site: entry.fault_site,
                    fault_stream: entry.fault_stream, rtp_loss_pct: entry.rtp_loss_pct,
                    clips: entry.clips, note: text, note_by: "app", note_ts: nil
                )
            }
            noteSaving = false
            noteEntry = nil
        } catch {
            noteError = "Failed to save note — check your connection."
            noteSaving = false
        }
    }
}

// MARK: - Fault Log Row

private struct FaultLogRow: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: FaultLogEntry
    let onTapNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── Header ───────────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.startLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.faultRed)
                        Text(entry.fault_node_label)
                            .font(.caption)
                            .foregroundStyle(Theme.faultRed)
                        Text("·")
                            .foregroundStyle(Theme.mutedText)
                        Text(entry.fault_site)
                            .font(.caption)
                            .foregroundStyle(Theme.mutedText)
                    }
                }
                Spacer()
                Text(entry.isOngoing ? "Ongoing" : entry.durationLabel)
                    .font(.caption.weight(entry.isOngoing ? .semibold : .regular))
                    .foregroundStyle(entry.isOngoing ? Theme.faultRed : Theme.secondaryText)
            }

            // ── Audio clips ──────────────────────────────────────────────────
            if !entry.clips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clips")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.mutedText)
                        .textCase(.uppercase)
                    ForEach(entry.clips) { clip in
                        ClipPlayerRow(clip: clip, api: appModel.api)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }

            // ── Engineer note ────────────────────────────────────────────────
            if let note = entry.note, !note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(Theme.brandBlue)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { onTapNote() } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(Theme.brandBlue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.brandBlue.opacity(0.08))
                )
            } else {
                Button { onTapNote() } label: {
                    Label("Add Note", systemImage: "note.text.badge.plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.brandBlue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }
}

// MARK: - Clip Player Row

private struct ClipPlayerRow: View {
    let clip: FaultLogClip
    let api: APIClient

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = false
    @State private var playError: String?

    private var statusColor: Color {
        switch clip.status {
        case "fault":     return Theme.faultRed
        case "last_good": return Theme.okGreen
        default:          return Theme.secondaryText
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: clip.statusIcon)
                .font(.caption)
                .foregroundStyle(statusColor)
                .frame(width: 16)

            Text(clip.displayName)
                .font(.caption)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            Spacer()

            if let error = playError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.faultRed)
                    .lineLimit(1)
            } else if isLoading {
                ProgressView().scaleEffect(0.7)
            } else {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isPlaying ? Theme.faultRed : Theme.brandBlue)
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear { stopPlayback() }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }
        guard let base = api.baseURL else { playError = "No server"; return }
        let rawURL = base.appendingPathComponent(clip.url)
        let playURL = api.authorizedPlaybackURL(for: rawURL)
        isLoading = true
        playError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let item = AVPlayerItem(url: playURL)
            let p = AVPlayer(playerItem: item)
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                   object: item, queue: .main) { _ in
                self.isPlaying = false
                self.player = nil
            }
            DispatchQueue.main.async {
                self.player = p
                self.isLoading = false
                self.isPlaying = true
                p.play()
            }
        }
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
        isPlaying = false
    }
}

// MARK: - Note Editor Sheet

private struct NoteEditorSheet: View {
    let entry: FaultLogEntry
    @Binding var noteText: String
    @Binding var isSaving: Bool
    @Binding var errorMessage: String?
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Fault Event") {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(entry.fault_node_label, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.faultRed)
                        Text("\(entry.fault_site) · \(entry.startLabel)")
                            .font(.caption)
                            .foregroundStyle(Theme.mutedText)
                        if entry.isOngoing {
                            Text("Ongoing")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.faultRed)
                        } else {
                            Text("Duration: \(entry.durationLabel)")
                                .font(.caption)
                                .foregroundStyle(Theme.mutedText)
                        }
                    }
                }

                Section {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 100)
                        .focused($textFocused)
                } header: {
                    Text("Engineer Note")
                } footer: {
                    if let error = errorMessage {
                        Text(error).foregroundStyle(Theme.faultRed)
                    }
                }
            }
            .navigationTitle(entry.hasNote ? "Edit Note" : "Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await onSave(noteText) }
                        }
                        .fontWeight(.semibold)
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { textFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct NodeTreeView: View {
    let node: ChainNode
    let depth: Int
    let baseURL: URL?
    let faultLabel: String?
    let maintenanceNodes: Set<String>
    let expandAll: Bool
    let loadingAudioURL: URL?
    let onPlayAudio: (ChainNode, URL) -> Void

    @State private var isExpanded = true

    private var isFaultTarget: Bool {
        guard let faultLabel else { return false }
        return node.label.caseInsensitiveCompare(faultLabel) == .orderedSame
    }

    private var isMaintenanceTarget: Bool {
        maintenanceNodes.contains(node.label) || node.isMaintenance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(accentColor).frame(width: 4).clipShape(Capsule())

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if !node.childNodes.isEmpty {
                                    Button {
                                        isExpanded.toggle()
                                    } label: {
                                        Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Image(systemName: node.isStack ? "square.stack.3d.up.fill" : "dot.radiowaves.left.and.right")
                                    .foregroundStyle(Theme.brandBlue)
                                Text(node.label)
                                    .font(.headline)
                                    .foregroundStyle(Theme.primaryText)
                            }

                            if let stream = node.stream, !stream.isEmpty {
                                Text(stream)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }

                        Spacer()
                        NodeStatusPill(status: node.status)
                    }

                    HStack(spacing: 8) {
                        SignalMeterView(level: node.displayLevelDbfs, label: node.signalLabel)
                        if isFaultTarget { MetricChip(icon: "exclamationmark.triangle", text: "Fault focus") }
                        if isMaintenanceTarget { MetricChip(icon: "wrench.and.screwdriver", text: "Maintenance") }
                    }

                    FlowChipRow(items: node.chips)

                    if let stale = node.staleLabel {
                        Text(stale)
                            .font(.caption)
                            .foregroundStyle(Theme.pendingAmber)
                    }

                    if let reason = node.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    if let url = node.resolvedLiveURL(baseURL: baseURL) {
                        let isLoadingThis = loadingAudioURL == url
                        Button {
                            if !isLoadingThis { onPlayAudio(node, url) }
                        } label: {
                            HStack(spacing: 6) {
                                if isLoadingThis {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Theme.brandBlue)
                                    Text("Connecting…")
                                } else {
                                    Image(systemName: "play.circle")
                                    Text(node.isStack ? "Play stack audio" : "Play audio")
                                }
                            }
                            .font(.footnote.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .tint(Theme.brandBlue)
                        .disabled(isLoadingThis)
                    }

                    // Signal history link (Feature 5) — available for leaf nodes with stream + site
                    if let stream = node.stream, !stream.isEmpty,
                       let site = node.site, !site.isEmpty {
                        let fakeStream = HubStream(
                            name: stream, format: "", level_dbfs: nil, sla_pct: nil,
                            ai_status: "ok", ai_phase: "", rtp_loss_pct: nil,
                            rtp_jitter_ms: nil, fm_rds_ps: nil, fm_rds_rt: nil,
                            dab_service: nil, dab_dls: nil, dab_ensemble: nil, live_url: nil
                        )
                        NavigationLink(value: HubStreamRef(siteName: site, stream: fakeStream)) {
                            Label("Signal history", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.brandBlue)
                        }
                        .buttonStyle(.plain)
                    }

                    if isExpanded && !node.childNodes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            // Offset-keyed ForEach for the same reason as the top-level nodes:
                            // stack child nodes share the same synthesised id when they have
                            // no stream/site, causing duplicate-ID rendering bugs.
                            ForEach(Array(node.childNodes.enumerated()), id: \.offset) { _, child in
                                NodeTreeView(
                                    node: child,
                                    depth: depth + 1,
                                    baseURL: baseURL,
                                    faultLabel: faultLabel,
                                    maintenanceNodes: maintenanceNodes,
                                    expandAll: expandAll,
                                    loadingAudioURL: loadingAudioURL,
                                    onPlayAudio: onPlayAudio
                                )
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .onAppear { isExpanded = expandAll }
        .onChange(of: expandAll) { _, newValue in isExpanded = newValue }
        .id(node.id)
        .padding(.leading, CGFloat(depth) * 8)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(backgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(borderColor, lineWidth: isFaultTarget ? 1.5 : 1))
    }

    private var accentColor: Color {
        if isFaultTarget || node.isFaultLike { return Theme.faultRed }
        if isMaintenanceTarget { return Theme.mutedText }
        if node.isStale { return Theme.pendingAmber }
        return depth == 0 ? Theme.brandBlue.opacity(0.8) : Theme.panelBorder
    }

    private var backgroundColor: Color {
        if isFaultTarget || node.isFaultLike { return Theme.faultRed.opacity(0.12) }
        if isMaintenanceTarget { return Theme.panelSecondary.opacity(0.12) }
        if node.isStale { return Theme.pendingAmber.opacity(0.10) }
        return Theme.panelSecondary.opacity(depth == 0 ? 0.35 : 0.2)
    }

    private var borderColor: Color {
        if isFaultTarget || node.isFaultLike { return Theme.faultRed.opacity(0.75) }
        if isMaintenanceTarget { return Theme.mutedText.opacity(0.6) }
        if node.isStale { return Theme.pendingAmber.opacity(0.7) }
        return Theme.panelBorder.opacity(0.55)
    }
}

private struct NodeStatusPill: View {
    let status: String

    private var color: Color {
        switch status.lowercased() {
        case "ok": return Theme.okGreen
        case "maintenance": return Theme.pendingAmber
        case "down", "offline": return Theme.faultRed
        default: return Theme.mutedText
        }
    }

    var body: some View {
        Text(status.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
    }
}

struct MetricChipData: Hashable {
    let icon: String
    let text: String
}

struct FlowChipRow: View {
    let items: [MetricChipData]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                MetricChip(icon: item.icon, text: item.text)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SignalMeterView: View {
    let level: Double?
    let label: String

    private var fillColor: Color {
        guard let level else { return Theme.mutedText }
        if level >= -12 { return Theme.pendingAmber }
        if level >= -30 { return Theme.okGreen }
        return Theme.faultRed
    }

    private var fraction: Double {
        guard let level else { return 0 }
        let clamped = min(max(level, -60), 0)
        return (clamped + 60) / 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(level?.formattedDbfs() ?? "No level")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 0)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999).fill(Theme.panel.opacity(0.95))
                    RoundedRectangle(cornerRadius: 999)
                        .fill(fillColor)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 10 : 0))
                }
            }
            .frame(height: 8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.panelBorder.opacity(0.45), lineWidth: 1))
    }
}

struct ChainDiagramStrip: View {
    let nodes: [ChainNode]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Use \.offset as the key — \.element.id duplicates for stacks (no stream/site)
                ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                    DiagramNodeChip(node: node)
                    if index < nodes.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.mutedText)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct DiagramNodeChip: View {
    let node: ChainNode

    private var color: Color {
        switch node.normalizedStatus {
        case "ok": return Theme.okGreen
        case "maintenance": return Theme.pendingAmber
        case "down", "offline": return Theme.faultRed
        default: return Theme.mutedText
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(node.label)
                .font(.caption)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panelSecondary.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(color.opacity(0.55), lineWidth: 1))
    }
}

private extension ChainNode {
    var chips: [MetricChipData] {
        var items: [MetricChipData] = []
        if let site, !site.isEmpty { items.append(.init(icon: "building.2", text: site)) }
        if let machine, !machine.isEmpty { items.append(.init(icon: "macpro.gen3", text: machine)) }
        if let mode, !mode.isEmpty, isStack { items.append(.init(icon: "square.stack.3d.up", text: "Mode \(mode)")) }
        if isStack { items.append(.init(icon: "list.bullet.indent", text: "\(childNodes.count) child nodes")) }
        if let loss = rtp_loss_pct, loss > 0 {
            items.append(.init(icon: "antenna.radiowaves.left.and.right",
                               text: String(format: "RTP %.1f%% loss", loss)))
        }
        return items
    }

    func flattenedPlayableNodes(baseURL: URL?) -> [AudioQueueItem] {
        var items: [AudioQueueItem] = []
        if let url = resolvedLiveURL(baseURL: baseURL) {
            items.append(AudioQueueItem(url: url, title: label, subtitle: site ?? stream))
        }
        for child in childNodes {
            items.append(contentsOf: child.flattenedPlayableNodes(baseURL: baseURL))
        }
        return items
    }
}
