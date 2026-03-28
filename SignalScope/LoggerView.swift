import SwiftUI
import UIKit

// MARK: - LoggerView (root tab)

struct LoggerView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var isAvailable: Bool? = nil   // nil=checking, true=ok, false=unavailable
    @State private var sites: [String] = []
    @State private var selectedSite: String = ""
    @State private var streams: [LoggerStream] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isHubMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if isAvailable == nil {
                    VStack(spacing: 16) {
                        ProgressView().tint(Theme.brandBlue)
                        Text("Checking logger…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if isAvailable == false {
                    unavailableCard
                } else if isLoading && streams.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView().tint(Theme.brandBlue)
                        Text("Loading streams…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if let error = errorMessage {
                    loggerErrorView(message: error, retryAction: { Task { await loadInitial() } })
                } else if streams.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.mutedText)
                        Text("No streams configured")
                            .font(.headline)
                            .foregroundStyle(Theme.secondaryText)
                        Text("Enable recording streams in Logger Settings on the hub.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if isHubMode && sites.count > 1 {
                                sitePicker
                            }
                            streamList
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Logger")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView().controlSize(.small).tint(Theme.brandBlue)
                    } else {
                        Button { Task { await loadInitial() } } label: {
                            Image(systemName: "arrow.clockwise").foregroundStyle(Theme.brandBlue)
                        }
                    }
                }
            }
        }
        .task { await loadInitial() }
    }

    // MARK: - Unavailable card

    private var unavailableCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 52))
                .foregroundStyle(Theme.mutedText)
            VStack(spacing: 8) {
                Text("Logger Not Available")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("The Logger plugin is not installed on this hub, or the mobile API token is not configured.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                Task { await loadInitial() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brandBlue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sub-views

    private var sitePicker: some View {
        PanelCard(title: "SITE") {
            Picker("Site", selection: $selectedSite) {
                ForEach(sites, id: \.self) { site in
                    Text(site).tag(site)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.brandBlue)
        }
        .onChange(of: selectedSite) { _, _ in
            Task { await loadStreams() }
        }
    }

    private var streamList: some View {
        PanelCard(title: "STREAMS") {
            VStack(spacing: 0) {
                ForEach(Array(streams.enumerated()), id: \.element.id) { index, stream in
                    if index > 0 {
                        Divider()
                            .background(Theme.panelBorder)
                            .padding(.leading, 16)
                    }
                    NavigationLink {
                        LoggerDatesView(stream: stream, site: selectedSite)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.body)
                                .foregroundStyle(Theme.brandBlue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stream.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.primaryText)
                                Text(stream.slug)
                                    .font(.caption)
                                    .foregroundStyle(Theme.mutedText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.mutedText)
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Data loading

    private func loadInitial() async {
        guard appModel.api.baseURL != nil else { isAvailable = false; return }
        isAvailable = nil
        errorMessage = nil
        // 1. Check the plugin is installed and token is valid
        do {
            _ = try await appModel.api.fetchLoggerStatus()
        } catch {
            isAvailable = false
            return
        }
        isAvailable = true
        // 2. Load hub sites
        isLoading = true
        defer { isLoading = false }
        do {
            let fetchedSites = try await appModel.api.fetchLoggerSites()
            sites = fetchedSites
            isHubMode = !fetchedSites.isEmpty
            if let first = fetchedSites.first, selectedSite.isEmpty {
                selectedSite = first
            }
            await loadStreams()
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadStreams() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let siteParam: String? = isHubMode && !selectedSite.isEmpty ? selectedSite : nil
            streams = try await appModel.api.fetchLoggerStreams(site: siteParam)
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - LoggerDatesView

struct LoggerDatesView: View {
    @EnvironmentObject private var appModel: AppModel
    let stream: LoggerStream
    let site: String

    @State private var days: [String] = []
    @State private var isLoading = false
    @State private var isPending = false
    @State private var pollAttempt = 0
    @State private var errorMessage: String?

    private let maxPollAttempts = 15
    private let pollIntervalSeconds: UInt64 = 3

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if isLoading && days.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(Theme.brandBlue)
                    Text(isPending ? "Requesting dates from site…" : "Loading dates…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    if isPending && pollAttempt > 0 {
                        Text("Attempt \(pollAttempt)/\(maxPollAttempts)")
                            .font(.caption)
                            .foregroundStyle(Theme.mutedText)
                    }
                }
            } else if let error = errorMessage {
                loggerErrorView(message: error, retryAction: loadDays)
            } else if days.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.mutedText)
                    Text("No recordings found")
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                    Text("No recordings are available for \(stream.name).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        PanelCard(title: "RECORDINGS") {
                            VStack(spacing: 0) {
                                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                                    if index > 0 {
                                        Divider()
                                            .background(Theme.panelBorder)
                                            .padding(.leading, 16)
                                    }
                                    NavigationLink {
                                        LoggerDayView(stream: stream, site: site, date: day)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "calendar")
                                                .font(.body)
                                                .foregroundStyle(Theme.brandBlue)
                                                .frame(width: 28)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(dayLabel(for: day))
                                                    .font(.body.weight(.medium))
                                                    .foregroundStyle(Theme.primaryText)
                                                Text(day)
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.mutedText)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Theme.mutedText)
                                        }
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(stream.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(Theme.brandBlue)
                } else {
                    Button { Task { await loadDays() } } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(Theme.brandBlue)
                    }
                }
            }
        }
        .task { await loadDays() }
    }

    private func dayLabel(for dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return dateStr }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let display = DateFormatter()
        display.dateStyle = .long
        display.timeStyle = .none
        return display.string(from: date)
    }

    private func loadDays() async {
        isLoading = true
        isPending = false
        pollAttempt = 0
        errorMessage = nil
        defer { isLoading = false }

        for attempt in 1...maxPollAttempts {
            guard !Task.isCancelled else { return }
            do {
                let result = try await appModel.api.fetchLoggerDays(site: site, slug: stream.slug)
                if result.pending == true {
                    isPending = true
                    pollAttempt = attempt
                    if attempt < maxPollAttempts {
                        try? await Task.sleep(nanoseconds: pollIntervalSeconds * 1_000_000_000)
                        continue
                    } else {
                        errorMessage = "Site did not respond in time. Try again."
                        return
                    }
                }
                days = result.days
                isPending = false
                return
            } catch {
                if Task.isCancelled { return }
                errorMessage = error.localizedDescription
                return
            }
        }
    }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

// MARK: - Block status

private enum SegBlockStatus {
    case none, ok, warn, silent
    var color: Color {
        switch self {
        case .none:   return Color(red: 0.055, green: 0.125, blue: 0.250)
        case .ok:     return Color(red: 0.087, green: 0.395, blue: 0.200)
        case .warn:   return Color(red: 0.474, green: 0.217, blue: 0.059)
        case .silent: return Color(red: 0.498, green: 0.114, blue: 0.114)
        }
    }
}

// MARK: - LoggerDayView

struct LoggerDayView: View {
    @EnvironmentObject private var appModel: AppModel
    let stream: LoggerStream
    let site:   String
    let date:   String

    // Data
    @State private var segments:    [LoggerSegment]   = []
    @State private var metaEvents:  [LoggerMetaEvent] = []
    @State private var isLoading    = false
    @State private var errorMessage: String?
    @State private var segsPending  = false
    @State private var segPoll      = 0

    // Playback
    @StateObject private var player        = PCMStreamPlayer()
    @State private var playingFilename:    String?
    @State private var isStartingPlayback  = false
    @State private var playbackError:      String?
    @State private var currentSlotID:      String?

    // Timeline zoom / pan  (1× = full day visible, 16× = ~90 min visible)
    @State private var zoom:         Double = 1.0
    @State private var panFrac:      Double = 0.0   // start of visible range as day-fraction
    @State private var canvasWidth:  CGFloat = 300
    @GestureState private var liveDragX:  CGFloat = 0
    @GestureState private var liveScale:  CGFloat = 1.0


    private let maxPoll:      Int    = 15
    private let pollInterval: UInt64 = 3

    // MARK: - Derived timeline state

    private var effectiveZoom: Double { (zoom * Double(liveScale)).clamped(to: 1.0...16.0) }

    private var effectivePanFrac: Double {
        let delta = -Double(liveDragX) / Double(max(canvasWidth, 1)) / zoom
        return (panFrac + delta).clamped(to: 0...max(0, 1 - 1/effectiveZoom))
    }

    private func visibleRange() -> (start: Double, end: Double) {
        let w = 1.0 / effectiveZoom
        let s = effectivePanFrac.clamped(to: 0...max(0, 1 - w))
        return (s, s + w)
    }

    // MARK: - Derived data

    private var slotMap: [Int: LoggerSegment] {
        var m = [Int: LoggerSegment]()
        for s in segments {
            let i = Int(s.start_s / 300)
            if (0..<288).contains(i) { m[i] = s }
        }
        return m
    }

    private var slotStatuses: [SegBlockStatus] {
        let sm = slotMap
        return (0..<288).map { i -> SegBlockStatus in
            guard let s = sm[i] else { return .none }
            if s.hasSilence { return (s.silence_pct ?? 0) >= 50 ? .silent : .warn }
            return .ok
        }
    }

    private var showSpans: [(start: Double, end: Double, name: String)] {
        let evs = metaEvents.filter { $0.isShow }.sorted { $0.ts_s < $1.ts_s }
        return evs.enumerated().map { i, ev in
            (ev.ts_s / 86400,
             (i + 1 < evs.count ? evs[i+1].ts_s : min(ev.ts_s + 7200, 86400)) / 86400,
             ev.show_name ?? ev.primaryLabel)
        }
    }

    private var trackPoints: [(frac: Double, title: String)] {
        metaEvents.filter { $0.isTrack }.map { ($0.ts_s / 86400, $0.primaryLabel) }
    }

    private var micSpans: [(start: Double, end: Double)] {
        var spans = [(Double, Double)](); var on: Double?
        for ev in metaEvents.sorted(by: { $0.ts_s < $1.ts_s }) {
            if ev.isMicOn  { on = ev.ts_s / 86400 }
            else if ev.isMicOff, let s = on { spans.append((s, ev.ts_s / 86400)); on = nil }
        }
        if let s = on { spans.append((s, min(s + 600/86400, 1))) }
        return spans
    }

    private var displayDate: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return date }
        let g = DateFormatter(); g.dateStyle = .full; g.timeStyle = .none
        return g.string(from: d)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if isLoading && segments.isEmpty {
                loadingOverlay
            } else if let err = errorMessage {
                loggerErrorView(message: err, retryAction: loadAll)
            } else {
                // Landscape side-by-side: timeline left, segment grid right
                HStack(alignment: .top, spacing: 0) {
                    timelinePanel
                        .frame(maxWidth: .infinity)
                        .padding(16)

                    Divider().background(Theme.panelBorder)

                    segmentGridColumn
                        .frame(width: 280)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(stream.name).font(.headline).foregroundStyle(Theme.primaryText)
                    Text(displayDate).font(.caption).foregroundStyle(Theme.mutedText)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(Theme.brandBlue)
                } else {
                    Button { Task { await loadAll() } } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(Theme.brandBlue)
                    }
                }
            }
        }
        .task { await loadAll() }
        .onAppear  { lockToLandscape() }
        .onDisappear { stopPlayback(); unlockOrientation() }
        .safeAreaInset(edge: .bottom) {
            if playingFilename != nil || isStartingPlayback {
                playerBar.padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Theme.brandBlue)
            Text(segsPending ? "Requesting from site… (\(segPoll)/\(maxPoll))" : "Loading…")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Timeline panel (main content)

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Playback error banner
            if let pbErr = playbackError { errorBanner(pbErr) }

            // Day bar + bands
            PanelCard(title: "TIMELINE  •  PINCH TO ZOOM  •  DRAG  •  TAP TO PLAY") {
                VStack(spacing: 6) {
                    dayBarCanvas
                    timeAxisLabels
                    if !showSpans.isEmpty   { bandView(spans: showSpanRects,  height: 18, icon: "radio",      tint: Color.purple) }
                    if !micSpans.isEmpty    { bandView(spans: micSpanRects,   height: 12, icon: "mic.fill",   tint: Theme.okGreen) }
                    if !trackPoints.isEmpty { bandView(spans: trackSpanRects, height: 12, icon: "music.note", tint: Theme.pendingAmber) }
                    zoomRow
                }
            }

            legendRow
        }
    }

    // MARK: - Right-column segment grid

    private var segmentGridColumn: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("SEGMENTS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.mutedText)
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.mini).tint(Theme.brandBlue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Theme.panelBorder)

                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        if hour > 0 { Divider().background(Theme.panelBorder).opacity(0.4) }
                        hourRow(hour: hour)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 80)   // clear player bar
            }
        }
        .background(Theme.panel.opacity(0.6))
    }

    // MARK: - Day bar Canvas (zoomable / pannable)

    private var dayBarCanvas: some View {
        Canvas { ctx, size in
            let (vS, vE) = visibleRange()
            let slotsVisible = (vE - vS) * 288
            guard slotsVisible > 0 else { return }
            let bw = size.width / CGFloat(slotsVisible)
            let firstSlot = max(0, Int(vS * 288))
            let lastSlot  = min(287, Int(ceil(vE * 288)))
            let statuses  = slotStatuses
            for i in firstSlot...lastSlot {
                let bx = CGFloat(Double(i) / 288.0 - vS) * size.width / CGFloat(vE - vS)
                let r  = CGRect(x: bx, y: 0, width: max(1, bw - 0.5), height: size.height)
                ctx.fill(Path(r), with: .color(statuses[i].color))
            }
            // Playhead
            if let fname = playingFilename,
               let seg = segments.first(where: { $0.filename == fname }) {
                let f = seg.start_s / 86400
                if f >= vS && f <= vE {
                    let x = CGFloat((f - vS) / (vE - vS)) * size.width
                    ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)),
                             with: .color(Theme.okGreen))
                }
            }
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.panelBorder.opacity(0.4), lineWidth: 1))
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { canvasWidth = geo.size.width }
                          .onChange(of: geo.size.width) { _, w in canvasWidth = w }
            }
        )
        .gesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .updating($liveScale) { v, s, _ in s = v }
                    .onEnded { v in
                        let newZ = (zoom * Double(v)).clamped(to: 1.0...16.0)
                        let centre = effectivePanFrac + 0.5 / effectiveZoom
                        zoom    = newZ
                        panFrac = (centre - 0.5 / zoom).clamped(to: 0...max(0, 1 - 1/zoom))
                    },
                DragGesture(minimumDistance: 4)
                    .updating($liveDragX) { v, s, _ in s = v.translation.width }
                    .onEnded { v in
                        let delta = -Double(v.translation.width) / Double(canvasWidth) / zoom
                        panFrac = (panFrac + delta).clamped(to: 0...max(0, 1 - 1/zoom))
                    }
            )
        )
        .onTapGesture { loc in
            let (vS, vE) = visibleRange()
            let dayFrac = vS + Double(loc.x) / Double(canvasWidth) * (vE - vS)
            let idx = Int(dayFrac * 288).clamped(to: 0...287)
            if let seg = slotMap[idx] { Task { await startPlayback(segment: seg) } }
        }
    }

    // MARK: - Time axis

    private var timeAxisLabels: some View {
        GeometryReader { geo in
            let (vS, vE) = visibleRange()
            let spanHours = (vE - vS) * 24
            // choose label interval
            let interval: Double = spanHours <= 3 ? 0.5 : spanHours <= 6 ? 1 : spanHours <= 12 ? 2 : 6
            let firstH = ceil(vS * 24 / interval) * interval
            let labels: [Double] = stride(from: firstH, through: vE * 24, by: interval).map { $0 }
            return ZStack {
                ForEach(labels, id: \.self) { h in
                    let frac = h / 24
                    let x = CGFloat((frac - vS) / (vE - vS)) * geo.size.width
                    Text(String(format: "%02d:%02d", Int(h), Int(h.truncatingRemainder(dividingBy: 1) * 60)))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.mutedText)
                        .position(x: x, y: 6)
                }
            }
        }
        .frame(height: 14)
    }

    // MARK: - Band helpers

    private struct SpanRect { let x: CGFloat; let w: CGFloat; let label: String? }

    private func spansInView(_ spans: [(start: Double, end: Double)], width: CGFloat) -> [SpanRect] {
        let (vS, vE) = visibleRange()
        return spans.compactMap { span in
            let clipS = max(span.start, vS); let clipE = min(span.end, vE)
            guard clipE > clipS else { return nil }
            let x = CGFloat((clipS - vS) / (vE - vS)) * width
            let w = CGFloat((clipE - clipS) / (vE - vS)) * width
            return SpanRect(x: x, w: max(2, w), label: nil)
        }
    }

    private var showSpanRects: [SpanRect] {
        let (vS, vE) = visibleRange()
        return showSpans.compactMap { span in
            let clipS = max(span.start, vS); let clipE = min(span.end, vE)
            guard clipE > clipS else { return nil }
            let x = CGFloat((clipS - vS) / (vE - vS)) * canvasWidth
            let w = CGFloat((clipE - clipS) / (vE - vS)) * canvasWidth
            return SpanRect(x: x, w: max(2, w), label: span.name)
        }
    }
    private var micSpanRects: [SpanRect] {
        spansInView(micSpans.map { (start: $0.start, end: $0.end) }, width: canvasWidth)
    }
    private var trackSpanRects: [SpanRect] {
        let (vS, vE) = visibleRange()
        return trackPoints.compactMap { pt in
            let w5 = 300.0 / 86400
            let clipS = max(pt.frac, vS); let clipE = min(pt.frac + w5, vE)
            guard clipE > clipS else { return nil }
            let x = CGFloat((clipS - vS) / (vE - vS)) * canvasWidth
            let w = CGFloat((clipE - clipS) / (vE - vS)) * canvasWidth
            return SpanRect(x: x, w: max(2, w), label: pt.title)
        }
    }

    @ViewBuilder
    private func bandView(spans: [SpanRect], height: CGFloat, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(tint).frame(width: 24, alignment: .trailing)
            ZStack(alignment: .topLeading) {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, sr in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(tint.opacity(0.18))
                        Rectangle().fill(tint.opacity(0.85)).frame(width: 2)
                        if let lbl = sr.label, sr.w > 20 {
                            Text(lbl).font(.system(size: 9)).lineLimit(1)
                                .foregroundStyle(tint.opacity(0.9)).padding(.leading, 4)
                        }
                    }
                    .frame(width: sr.w, height: height)
                    .offset(x: sr.x)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .clipped()
        }
    }

    // MARK: - Zoom row

    private var zoomRow: some View {
        HStack(spacing: 8) {
            Button { zoomStep(-1) } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 14)).foregroundStyle(Theme.brandBlue)
            }
            .buttonStyle(.plain)

            Text(zoomLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.mutedText)
                .frame(minWidth: 28)

            Button { zoomStep(+1) } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14)).foregroundStyle(Theme.brandBlue)
            }
            .buttonStyle(.plain)

            Spacer()

            let (vS, vE) = visibleRange()
            let sh = Int(vS * 24); let sm = Int((vS * 24 - Double(sh)) * 60)
            let eh = Int(vE * 24); let em = Int((vE * 24 - Double(eh)) * 60)
            Text(String(format: "%02d:%02d – %02d:%02d", sh, sm, eh, em))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.mutedText)
        }
    }

    private var zoomLabel: String {
        let z = Int(zoom.rounded())
        return z >= 2 ? "\(z)×" : "1×"
    }

    private func zoomStep(_ dir: Int) {
        let steps: [Double] = [1, 2, 4, 8, 16]
        let cur = steps.min(by: { abs($0 - zoom) < abs($1 - zoom) }) ?? 1
        guard let idx = steps.firstIndex(of: cur) else { return }
        let newIdx = (idx + dir).clamped(to: 0...steps.count - 1)
        let newZ = steps[newIdx]
        let centre = effectivePanFrac + 0.5 / effectiveZoom
        withAnimation(.easeOut(duration: 0.2)) {
            zoom    = newZ
            panFrac = (centre - 0.5 / zoom).clamped(to: 0...max(0, 1 - 1/zoom))
        }
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 10) {
            ForEach([
                (SegBlockStatus.ok,     "OK"),
                (.warn,                 "Silence"),
                (.silent,               "Major silence"),
                (.none,                 "No recording"),
            ], id: \.1) { s, lbl in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(s.color).frame(width: 11, height: 11)
                    Text(lbl).font(.system(size: 10)).foregroundStyle(Theme.mutedText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Grid sheet

    @ViewBuilder
    private func hourRow(hour: Int) -> some View {
        let sm      = slotMap
        let statuses = slotStatuses
        HStack(spacing: 3) {
            Text(String(format: "%02d:00", hour))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.mutedText)
                .frame(width: 36, alignment: .trailing)

            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { m5 in
                    let idx    = hour * 12 + m5
                    let status = statuses[idx]
                    let seg    = sm[idx]
                    let isPlay = playingFilename != nil && seg?.filename == playingFilename

                    Button {
                        if let s = seg { Task { await startPlayback(segment: s) } }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isPlay ? Theme.okGreen : status.color)
                            if isPlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                            }
                        }
                        .frame(height: 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(seg == nil)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Player bar

    private var playerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if isStartingPlayback {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Theme.brandBlue)
                        Text("Connecting…").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                } else if let fname = playingFilename,
                          let seg = segments.first(where: { $0.filename == fname }) {
                    Text(currentMetaTitle(for: seg.start_s))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(seg.startLabel)
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.mutedText)
                        Circle().fill(playerStatusColor).frame(width: 6, height: 6)
                        Text(player.status.label).font(.caption).foregroundStyle(playerStatusColor)
                    }
                    if let sub = currentMetaSubtitle(for: seg.start_s) {
                        Text(sub).font(.caption).foregroundStyle(Theme.mutedText).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Button { playPrev() } label: {
                    Image(systemName: "backward.fill")
                        .foregroundStyle(hasPrev ? Theme.primaryText : Theme.mutedText)
                }.buttonStyle(.plain).disabled(!hasPrev)

                Button { togglePlayerPlayback() } label: {
                    Image(systemName: isActuallyPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2).foregroundStyle(Theme.brandBlue)
                }.buttonStyle(.plain)

                Button { playNext() } label: {
                    Image(systemName: "forward.fill")
                        .foregroundStyle(hasNext ? Theme.primaryText : Theme.mutedText)
                }.buttonStyle(.plain).disabled(!hasNext)

                Button { stopPlayback() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedText)
                }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.panelBorder.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: -4)
    }

    private func errorBanner(_ msg: String) -> some View {
        PanelCard {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.faultRed)
                Text(msg).font(.subheadline).foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { playbackError = nil } label: {
                    Image(systemName: "xmark").font(.caption).foregroundStyle(Theme.mutedText)
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Metadata helpers

    private func currentMetaTitle(for startSecs: Double) -> String {
        let evs = metaEvents.filter { $0.ts_s <= startSecs + 300 }.sorted { $0.ts_s < $1.ts_s }
        if let t = evs.last(where: { $0.isTrack }) { return t.primaryLabel }
        if let s = evs.last(where: { $0.isShow  }) { return s.primaryLabel }
        return stream.name
    }

    private func currentMetaSubtitle(for startSecs: Double) -> String? {
        let evs = metaEvents.filter { $0.ts_s <= startSecs + 300 }.sorted { $0.ts_s < $1.ts_s }
        if let t = evs.last(where: { $0.isTrack }), let a = t.artist,     !a.isEmpty { return a }
        if let s = evs.last(where: { $0.isShow  }), let p = s.presenter,  !p.isEmpty { return p }
        return nil
    }

    // MARK: - Player state helpers

    private var playerStatusColor: Color {
        switch player.status {
        case .playing:              return Theme.okGreen
        case .error:                return Theme.faultRed
        case .buffering, .connecting: return Theme.pendingAmber
        default:                    return Theme.mutedText
        }
    }
    private var isActuallyPlaying: Bool { player.status == .playing }
    private var currentIndex: Int? {
        guard let f = playingFilename else { return nil }
        return segments.firstIndex(where: { $0.filename == f })
    }
    private var hasPrev: Bool { (currentIndex ?? 0) > 0 }
    private var hasNext: Bool {
        guard let i = currentIndex else { return false }
        return i < segments.count - 1
    }

    // MARK: - Playback

    private func startPlayback(segment: LoggerSegment) async {
        guard !isStartingPlayback else { return }
        playbackError     = nil
        isStartingPlayback = true
        player.stop()

        do {
            if currentSlotID != nil, !site.isEmpty {
                try? await appModel.api.stopLoggerPlay(site: site)
                currentSlotID = nil
            }

            let resp = try await appModel.api.startLoggerPlay(
                site: site, slug: stream.slug, date: date,
                filename: segment.filename, seekSeconds: 0
            )
            guard let streamPath = resp.stream_url, let base = appModel.api.baseURL else {
                playbackError     = resp.error ?? "No stream URL"
                isStartingPlayback = false
                return
            }

            currentSlotID  = resp.slot_id
            playingFilename = segment.filename

            // Resolve relative URL — preserves query strings (stream_pcm?slug=…)
            let rawURL  = URL(string: streamPath, relativeTo: base)?.absoluteURL
                       ?? base.appendingPathComponent(streamPath)
            let authURL = appModel.api.authorizedPlaybackURL(for: rawURL)

            // For hub relay: give the client ~1.5 s to receive the play command
            if resp.slot_id != nil {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            isStartingPlayback = false
            player.start(url: authURL)

        } catch {
            playbackError     = error.localizedDescription
            isStartingPlayback = false
        }
    }

    // MARK: - Orientation helpers

    private func lockToLandscape() {
        AppDelegate.orientationLock = .landscape
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
            scene.requestGeometryUpdate(prefs) { _ in }
        }
    }

    private func unlockOrientation() {
        AppDelegate.orientationLock = .all
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .all)
            scene.requestGeometryUpdate(prefs) { _ in }
        }
    }

    private func stopPlayback() {
        player.stop()
        playingFilename    = nil
        isStartingPlayback  = false
        if !site.isEmpty { Task { try? await appModel.api.stopLoggerPlay(site: site) } }
        currentSlotID = nil
    }

    private func togglePlayerPlayback() {
        if isActuallyPlaying { player.stop() }
        else if let f = playingFilename, let seg = segments.first(where: { $0.filename == f }) {
            Task { await startPlayback(segment: seg) }
        }
    }

    private func playPrev() {
        guard let i = currentIndex, i > 0 else { return }
        Task { await startPlayback(segment: segments[i - 1]) }
    }

    private func playNext() {
        guard let i = currentIndex, i < segments.count - 1 else { return }
        Task { await startPlayback(segment: segments[i + 1]) }
    }

    // MARK: - Data loading

    private func loadAll() async {
        async let a: Void = loadSegments()
        async let b: Void = loadMetadata()
        _ = await (a, b)
    }

    private func loadSegments() async {
        isLoading = true; segsPending = false; segPoll = 0
        defer { isLoading = false }
        for attempt in 1...maxPoll {
            guard !Task.isCancelled else { return }
            do {
                let r = try await appModel.api.fetchLoggerSegments(site: site, slug: stream.slug, date: date)
                if r.pending == true {
                    segsPending = true; segPoll = attempt
                    if attempt < maxPoll { try? await Task.sleep(nanoseconds: pollInterval * 1_000_000_000); continue }
                    errorMessage = "Site did not respond. Try again."; return
                }
                segments = r.segments; segsPending = false; errorMessage = nil; return
            } catch {
                if Task.isCancelled { return }
                errorMessage = error.localizedDescription; return
            }
        }
    }

    private func loadMetadata() async {
        for attempt in 1...maxPoll {
            guard !Task.isCancelled else { return }
            do {
                let r = try await appModel.api.fetchLoggerMetadata(site: site, slug: stream.slug, date: date)
                if r.pending == true {
                    if attempt < maxPoll { try? await Task.sleep(nanoseconds: pollInterval * 1_000_000_000); continue }
                    return
                }
                metaEvents = r.events; return
            } catch { if Task.isCancelled { return }; return }
        }
    }
}

// MARK: - Error view helper

private func loggerErrorView(message: String, retryAction: @escaping () async -> Void) -> some View {
    VStack(spacing: 20) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 40)).foregroundStyle(Theme.faultRed)
        Text("Error").font(.headline).foregroundStyle(Theme.primaryText)
        Text(message).font(.subheadline).foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center).padding(.horizontal, 32)
        Button { Task { await retryAction() } } label: {
            Label("Retry", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brandBlue)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.brandBlue.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.brandBlue.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
