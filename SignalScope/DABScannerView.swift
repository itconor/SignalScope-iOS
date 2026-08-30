import SwiftUI

struct DABScannerView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var sites: [DABSite] = []
    @State private var selectedSite: String = ""
    @State private var selectedSerial: String = ""
    @State private var services: [DABService] = []
    @State private var scannedAt: String = ""
    @State private var selectedService: DABService?

    @State private var isLoading = false
    @State private var isStreaming = false
    @State private var isScanning = false
    @State private var statusText = "Ready"
    @State private var errorMessage: String?
    @State private var dlsText: String = ""
    @State private var currentService: String = ""
    @State private var currentChannel: String = ""

    @State private var statusPollTask: Task<Void, Never>?
    @State private var siteLoadTask: Task<Void, Never>?

    // Simulated EQ level for DAB (AVPlayer doesn't expose PCM level easily)
    @State private var eqLevel: Float = 0
    @State private var eqTimer: Timer?
    @State private var eqPhase: Double = 0

    // Region / location presets
    private static let scanPresets: [(id: String, label: String, icon: String, channels: [String])] = [
        ("all",          "Full Scan (38 ch)",           "🌍", []),
        ("uk_ni",        "Northern Ireland (6 ch)",     "🏴", ["11D","11A","12B","12D","9A","9C"]),
        ("uk_scotland",  "Scotland (5 ch)",              "🏴", ["11D","11B","11C","12B","12C"]),
        ("uk_wales",     "Wales (4 ch)",                 "🏴", ["11D","11A","12B","12C"]),
        ("uk_national",  "England — National (3 ch)",   "🇬🇧", ["11D","12B","10B"]),
        ("uk_london",    "London (6 ch)",                "🇬🇧", ["11D","12B","10B","10C","11C","12D"]),
        ("uk_northwest", "North West England (5 ch)",   "🇬🇧", ["11D","12B","10B","11A","11C"]),
        ("uk_northeast", "North East England (4 ch)",   "🇬🇧", ["11D","12B","10B","11B"]),
        ("uk_yorkshire", "Yorkshire (5 ch)",             "🇬🇧", ["11D","12B","10B","11B","12A"]),
        ("uk_midlands",  "Midlands (4 ch)",              "🇬🇧", ["11D","12B","10B","11A"]),
        ("uk_south",     "South England (5 ch)",         "🇬🇧", ["11D","12B","10B","11C","12C"]),
        ("uk",           "All UK (10 ch)",               "🇬🇧", ["10B","10C","11A","11B","11C","11D","12A","12B","12C","12D"]),
        ("ireland",      "Republic of Ireland (3 ch)",   "🇮🇪", ["9D","11B","11D"]),
        ("germany",      "Germany (11 ch)",               "🇩🇪", ["5A","5C","7A","7B","7C","7D","8A","8D","9A","9D","10D"]),
        ("netherlands",  "Netherlands (6 ch)",            "🇳🇱", ["7C","8A","8B","9B","10A","11A"]),
        ("france",       "France (6 ch)",                 "🇫🇷", ["10A","10B","10C","10D","11A","11B"]),
        ("norway",       "Norway (6 ch)",                 "🇳🇴", ["7B","9D","10A","10B","11D","12A"]),
        ("denmark",      "Denmark (6 ch)",                "🇩🇰", ["10B","10C","10D","11A","11B","11C"]),
        ("belgium",      "Belgium (4 ch)",                "🇧🇪", ["7B","8A","10B","11D"]),
        ("switzerland",  "Switzerland (5 ch)",            "🇨🇭", ["7A","7B","7C","8A","12D"]),
    ]
    @State private var selectedRegionID: String = "all"

    private var selectedPreset: (id: String, label: String, icon: String, channels: [String])? {
        Self.scanPresets.first { $0.id == selectedRegionID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        if sites.isEmpty && !isLoading {
                            unavailableCard
                        } else {
                            // Now-playing hero — visible only when streaming
                            if isStreaming {
                                nowPlayingCard
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Source + scan controls
                            controlsCard

                            // Station list
                            if !services.isEmpty {
                                stationListCard
                            } else if !isScanning {
                                noServicesCard
                            }
                        }

                        if let error = errorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding()
                    .animation(.easeInOut(duration: 0.3), value: isStreaming)
                }
            }
            .navigationTitle("DAB Scanner")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoading && sites.isEmpty {
                        ProgressView().tint(Theme.brandBlue)
                    } else {
                        Button {
                            siteLoadTask?.cancel()
                            siteLoadTask = Task { await loadSites() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Theme.brandBlue)
                        }
                    }
                }
            }
            .task { await loadSites() }
            .onDisappear { stopStatusPoll(); stopEQTimer() }
        }
    }

    // MARK: - Now Playing Hero Card

    private var nowPlayingCard: some View {
        PanelCard {
            VStack(spacing: 0) {
                // Live badge + header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Theme.faultRed)
                                .frame(width: 7, height: 7)
                                .shadow(color: Theme.faultRed.opacity(0.9), radius: 4)
                            Text("LIVE")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(Theme.faultRed)
                        }

                        Text(currentService.isEmpty ? (selectedService?.label ?? "DAB Radio") : currentService)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.caption2)
                                .foregroundStyle(Theme.brandBlue)
                            Text("DAB")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.brandBlue)
                            if !currentChannel.isEmpty {
                                Text("· Ch \(currentChannel)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.mutedText)
                            }
                        }
                    }

                    Spacer()

                    // Stop button in header
                    Button { Task { await stopAction() } } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title)
                            .foregroundStyle(Theme.faultRed)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
                .padding(.bottom, 14)

                // EQ Visualizer (simulated for DAB)
                EqualizerBarsView(level: eqLevel, isActive: isStreaming)
                    .padding(.bottom, 14)

                // DLS "now playing" text
                if !dlsText.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(Theme.brandBlue)
                        Text(dlsText)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                } else if isStreaming {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.brandBlue)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(Theme.mutedText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.brandBlue.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Controls Card (site, region, scan)

    private var controlsCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                // Site + serial pickers
                if sites.isEmpty {
                    HStack { Spacer(); ProgressView().tint(Theme.brandBlue); Spacer() }
                } else {
                    HStack(spacing: 10) {
                        Label("Site", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Picker("Site", selection: $selectedSite) {
                            ForEach(sites) { site in
                                Text(site.site).tag(site.site)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.brandBlue)
                        .onChange(of: selectedSite) { _, newSite in
                            let site = sites.first { $0.site == newSite }
                            selectedSerial = site?.serials.first ?? ""
                            services = []
                            Task { await loadServices() }
                        }
                    }

                    if let site = sites.first(where: { $0.site == selectedSite }), site.serials.count > 1 {
                        HStack(spacing: 10) {
                            Label("SDR", systemImage: "memorychip")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Picker("SDR Device", selection: $selectedSerial) {
                                ForEach(site.serials, id: \.self) { serial in
                                    Text(serial.isEmpty ? "Auto" : serial).tag(serial)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.brandBlue)
                        }
                    }
                }

                Divider().background(Theme.panelBorder)

                // Region picker + scan button
                HStack(spacing: 10) {
                    Picker("Region", selection: $selectedRegionID) {
                        ForEach(Self.scanPresets, id: \.id) { preset in
                            Text("\(preset.icon) \(preset.label)").tag(preset.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.brandBlue)
                    .frame(maxWidth: .infinity)

                    Button { Task { await scanAction() } } label: {
                        HStack(spacing: 6) {
                            if isScanning {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(isScanning ? "Scanning…" : "Scan")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brandBlue)
                    .disabled(selectedSite.isEmpty || isScanning)
                }

                // Scan progress / last scanned
                if isScanning || !statusText.isEmpty && statusText != "Ready" {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(Theme.mutedText)
                        .transition(.opacity)
                }

                if !scannedAt.isEmpty && !isScanning {
                    Text("Last scan: \(scannedAt)")
                        .font(.caption2)
                        .foregroundStyle(Theme.mutedText.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Station List Card

    private var stationListCard: some View {
        PanelCard(title: "\(services.count) Services Found") {
            VStack(spacing: 0) {
                ForEach(services) { service in
                    stationRow(service)
                    if service.id != services.last?.id {
                        Divider()
                            .background(Theme.panelBorder.opacity(0.5))
                    }
                }
            }
        }
    }

    private func stationRow(_ service: DABService) -> some View {
        let isSelected = selectedService?.id == service.id
        let isPlaying  = isStreaming && isSelected

        return Button {
            let wasStreaming = isStreaming
            selectedService = service
            if wasStreaming {
                Task {
                    await stopAction()
                    await startAction()
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Play/active indicator
                ZStack {
                    Circle()
                        .fill(isPlaying ? Theme.okGreen.opacity(0.18) : (isSelected ? Theme.brandBlue.opacity(0.13) : Color.clear))
                        .frame(width: 34, height: 34)
                    Image(systemName: isPlaying ? "waveform" : (isSelected ? "checkmark.circle.fill" : "play.circle"))
                        .font(isPlaying ? .caption.weight(.bold) : .body)
                        .foregroundStyle(isPlaying ? Theme.okGreen : (isSelected ? Theme.brandBlue : Theme.mutedText))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(service.label)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.primaryText : Theme.secondaryText)
                    Text("Ch \(service.channel)")
                        .font(.caption2)
                        .foregroundStyle(Theme.mutedText)
                }

                Spacer()

                if !isStreaming && isSelected {
                    Button { Task { await startAction() } } label: {
                        Label("Play", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.okGreen)
                    .disabled(isLoading)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - No services / unavailable

    private var noServicesCard: some View {
        PanelCard {
            VStack(spacing: 12) {
                Image(systemName: "radio")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.mutedText)
                Text("No services found")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Tap Scan to discover DAB services in your area.")
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private var unavailableCard: some View {
        PanelCard {
            VStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.mutedText)
                Text("DAB Scanner Not Available")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("No sites with DAB/scanner dongles found. Assign a dongle the 'scanner' role in Settings, or install the DAB plugin on the hub.")
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.faultRed)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.faultRed)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - EQ simulation (DAB uses AVPlayer — no raw PCM level available)

    private func startEQTimer() {
        stopEQTimer()
        eqPhase = 0
        eqTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            guard isStreaming else { return }
            eqPhase += 0.12
            // Combine two slow sine waves + small random jitter → natural-looking movement
            let base = Float(0.30 + 0.22 * sin(eqPhase * 2.1) + 0.14 * sin(eqPhase * 4.9))
            eqLevel = max(0.05, base + Float.random(in: -0.04...0.04))
        }
    }

    private func stopEQTimer() {
        eqTimer?.invalidate()
        eqTimer = nil
        eqLevel = 0
    }

    // MARK: - Actions (logic unchanged)

    private func loadSites() async {
        guard appModel.api.baseURL != nil else {
            errorMessage = "Configure your Hub URL in Settings."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            sites = try await appModel.api.fetchDABSites()
            if selectedSite.isEmpty, let first = sites.first {
                selectedSite = first.site
                selectedSerial = first.serials.first ?? ""
                await loadServices()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadServices() async {
        guard !selectedSite.isEmpty else { return }
        do {
            let response = try await appModel.api.fetchDABServices(site: selectedSite)
            services = response.services
            scannedAt = response.scanned_at ?? ""
            if let first = services.first, selectedService == nil {
                selectedService = first
            }
        } catch { }
    }

    private func scanAction() async {
        guard !selectedSite.isEmpty else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            let channels: [String]? = selectedRegionID == "all" ? nil : selectedPreset?.channels
            let chDesc = channels.map { "\($0.count) ch" } ?? "full scan"
            try await appModel.api.scanDAB(site: selectedSite, sdrSerial: selectedSerial, channels: channels)
            statusText = "Scan started (\(chDesc)) — polling for progress…"

            let deadline = Date().addingTimeInterval(20 * 60)
            var pollCount = 0
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let status = try? await appModel.api.fetchDABScanStatus(site: selectedSite) {
                    pollCount += 1
                    let pct = status.total.flatMap { t in
                        status.progress.map { p in t > 0 ? Int(100 * p / t) : 0 }
                    } ?? 0
                    let ch = status.channel.flatMap { $0.isEmpty ? nil : $0 }.map { " (\($0))" } ?? ""
                    statusText = status.status == "done"
                        ? "Scan complete — \(status.found ?? 0) service(s) found"
                        : "Scanning\(ch)… \(pct)%"
                    if status.status == "done" || (status.status == "idle" && pollCount > 2) { break }
                }
            }
            await loadServices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAction() async {
        guard let service = selectedService, !selectedSite.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appModel.api.startDAB(
                site: selectedSite, service: service.label,
                channel: service.channel, sdrSerial: selectedSerial
            )
            guard result.ok, let streamPath = result.mobile_stream_url ?? result.stream_url else {
                errorMessage = result.error ?? "Failed to start DAB"
                return
            }
            let resolvedURL = resolveStreamURL(streamPath)
            errorMessage = nil
            isStreaming = true
            statusText = "Connecting…"
            dlsText = ""
            appModel.playAudio(
                url: resolvedURL,
                title: service.label,
                subtitle: "\(selectedSite) · Ch \(service.channel)",
                playlist: [],
                index: 0
            )
            startStatusPoll()
            startEQTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAction() async {
        stopStatusPoll()
        stopEQTimer()
        appModel.stopAudio()
        isStreaming = false
        statusText = "Ready"
        dlsText = ""
        do {
            try await appModel.api.stopDAB(site: selectedSite)
        } catch { }
    }

    // MARK: - Status polling

    private func startStatusPoll() {
        stopStatusPoll()
        statusPollTask = Task {
            while !Task.isCancelled {
                do {
                    let status = try await appModel.api.fetchDABStatus(site: selectedSite)
                    if status.active {
                        dlsText = status.dls ?? ""
                        currentService = status.service ?? ""
                        currentChannel = status.channel ?? ""
                        statusText = status.streaming == true
                            ? "Streaming \(currentService)"
                            : "Buffering…"
                    } else {
                        isStreaming = false
                        stopEQTimer()
                        statusText = "Session ended"
                    }
                } catch { }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func stopStatusPoll() {
        statusPollTask?.cancel()
        statusPollTask = nil
    }

    private func resolveStreamURL(_ path: String) -> URL {
        if let base = appModel.api.baseURL {
            return URL(string: path, relativeTo: base)?.absoluteURL ?? base.appendingPathComponent(path)
        }
        return URL(string: path) ?? URL(string: "about:blank")!
    }
}
