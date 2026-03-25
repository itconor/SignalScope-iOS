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
    @State private var statusText = "Idle"
    @State private var errorMessage: String?
    @State private var dlsText: String = ""
    @State private var currentService: String = ""
    @State private var currentChannel: String = ""

    @State private var statusPollTask: Task<Void, Never>?
    @State private var siteLoadTask: Task<Void, Never>?

    // Region / location presets for faster scanning
    @State private var regions: [DABRegion] = []          // flat list loaded from hub
    @State private var selectedRegionID: String = "all"   // "all" = scan every channel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if sites.isEmpty && !isLoading {
                        unavailableCard
                    } else {
                        sitePickerCard
                        servicesCard
                        playerCard
                        if !dlsText.isEmpty || isStreaming {
                            dlsCard
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.faultRed)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("DAB Scanner")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoading {
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
            .task {
                await loadSites()
                await loadRegions()
            }
            .onDisappear { stopStatusPoll() }
        }
    }

    // MARK: - Site Picker Card

    private var sitePickerCard: some View {
        PanelCard(title: "Site") {
            VStack(alignment: .leading, spacing: 10) {
                if sites.isEmpty {
                    HStack { Spacer(); ProgressView().tint(Theme.brandBlue); Spacer() }
                } else {
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

                    if let site = sites.first(where: { $0.site == selectedSite }), site.serials.count > 1 {
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
        }
    }

    // MARK: - Services Card

    private var selectedRegion: DABRegion? {
        regions.first { $0.id == selectedRegionID }
    }

    private var servicesCard: some View {
        PanelCard(title: "Services") {
            VStack(alignment: .leading, spacing: 12) {

                // Region picker — only shown once regions are loaded from hub
                if !regions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scan Region")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Picker("Region", selection: $selectedRegionID) {
                            Text("🌍 Full Scan (\(regions.first?.channels.count ?? 0) ch)").tag("all")
                            ForEach(regions.dropFirst()) { region in  // skip root "All Europe" entry
                                let chCount = region.channels.count
                                Text("\(region.icon.isEmpty ? "📡" : region.icon) \(region.label) (\(chCount) ch)")
                                    .tag(region.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.brandBlue)
                    }
                }

                HStack {
                    if !scannedAt.isEmpty {
                        Text("Scanned \(scannedAt)")
                            .font(.caption2)
                            .foregroundStyle(Theme.mutedText)
                    }
                    Spacer()
                    Button {
                        Task { await scanAction() }
                    } label: {
                        Label(isScanning ? "Scanning…" : "Scan", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brandBlue)
                    .disabled(selectedSite.isEmpty || isScanning)
                }

                if services.isEmpty {
                    Text("No services found. Tap Scan to discover DAB services.")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedText)
                } else {
                    ForEach(services) { service in
                        Button {
                            selectedService = service
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.primaryText)
                                    Text("Ch \(service.channel)")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.mutedText)
                                }
                                Spacer()
                                if selectedService?.id == service.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.brandBlue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        if service.id != services.last?.id {
                            Divider().background(Theme.panelBorder.opacity(0.5))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Player Card

    private var playerCard: some View {
        PanelCard(title: "Playback") {
            VStack(alignment: .leading, spacing: 12) {
                if let service = selectedService {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.label)
                                .font(.headline)
                                .foregroundStyle(Theme.primaryText)
                            Text("Channel \(service.channel)")
                                .font(.caption)
                                .foregroundStyle(Theme.mutedText)
                        }
                        Spacer()
                        statusDot
                    }
                } else {
                    Text("Select a service above to play")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedText)
                }

                HStack(spacing: 10) {
                    if isStreaming {
                        Button {
                            Task { await stopAction() }
                        } label: {
                            Label("Stop", systemImage: "stop.circle.fill")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.faultRed)
                        .disabled(isLoading)
                    } else {
                        Button {
                            Task { await startAction() }
                        } label: {
                            Label("Play", systemImage: "play.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.okGreen)
                        .disabled(selectedSite.isEmpty || selectedService == nil || isLoading)
                    }

                    if isLoading {
                        ProgressView().tint(Theme.brandBlue)
                    }
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(isStreaming ? Theme.okGreen : (isLoading ? Theme.pendingAmber : Theme.mutedText))
            .frame(width: 12, height: 12)
            .shadow(color: (isStreaming ? Theme.okGreen : Color.clear).opacity(0.6), radius: 4)
    }

    // MARK: - DLS Card

    private var dlsCard: some View {
        PanelCard(title: "Now Playing (DLS)") {
            if dlsText.isEmpty {
                Text("No DLS data yet…")
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)
            } else {
                Text(dlsText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Unavailable Card

    private var unavailableCard: some View {
        PanelCard {
            VStack(spacing: 14) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 40))
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
            .padding(.vertical, 20)
        }
    }

    // MARK: - Actions

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
        } catch {
            // Non-fatal
        }
    }

    private func loadRegions() async {
        guard appModel.api.baseURL != nil else { return }
        if let rootRegion = try? await appModel.api.fetchDABRegions() {
            // Flatten to a list: root first, then all descendants
            regions = rootRegion.allDescendants
        }
    }

    private func scanAction() async {
        guard !selectedSite.isEmpty else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            // Pass selected region's channels (nil = all channels = full scan)
            let channels: [String]? = selectedRegionID == "all" ? nil : selectedRegion?.channels
            let chDesc = channels.map { "\($0.count) ch" } ?? "full scan"
            try await appModel.api.scanDAB(site: selectedSite, sdrSerial: selectedSerial, channels: channels)
            statusText = "Scan started (\(chDesc)) — polling for progress…"

            // Poll scan_status until done
            let deadline = Date().addingTimeInterval(20 * 60)  // 20 minute timeout
            var pollCount = 0
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 5_000_000_000)  // poll every 5 s
                if let status = try? await appModel.api.fetchDABScanStatus(site: selectedSite) {
                    pollCount += 1
                    let pct = status.total.flatMap { t in
                        status.progress.map { p in t > 0 ? Int(100 * p / t) : 0 }
                    } ?? 0
                    let ch = status.channel.flatMap { $0.isEmpty ? nil : $0 }.map { " (\($0))" } ?? ""
                    statusText = status.status == "done"
                        ? "Scan complete — \(status.found ?? 0) service(s) found"
                        : "Scanning\(ch)… \(pct)%"
                    if status.status == "done" || (status.status == "idle" && pollCount > 2) {
                        break
                    }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAction() async {
        stopStatusPoll()
        appModel.stopAudio()
        isStreaming = false
        statusText = "Stopped"
        dlsText = ""
        do {
            try await appModel.api.stopDAB(site: selectedSite)
        } catch {
            // Non-fatal
        }
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
                        if status.streaming == true {
                            statusText = "Streaming \(currentService) — Ch \(currentChannel)"
                        } else {
                            statusText = "Buffering…"
                        }
                    } else {
                        isStreaming = false
                        statusText = "Session ended"
                    }
                } catch {
                    // Ignore poll errors
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func stopStatusPoll() {
        statusPollTask?.cancel()
        statusPollTask = nil
    }

    // MARK: - Helpers

    private func resolveStreamURL(_ path: String) -> URL {
        if let base = appModel.api.baseURL {
            return URL(string: path, relativeTo: base)?.absoluteURL
                ?? base.appendingPathComponent(path)
        }
        return URL(string: path) ?? URL(string: "about:blank")!
    }
}
