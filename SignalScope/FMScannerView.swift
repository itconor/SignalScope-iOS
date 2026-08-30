import SwiftUI

struct FMScannerView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var sites: [ScannerSite] = []
    @State private var selectedSite: String = ""
    @State private var selectedSerial: String = ""
    @State private var freqText: String = "96.5"
    @State private var freqMHz: Double = 96.5

    @State private var isLoading = false
    @State private var isStreaming = false
    @State private var statusText = "Ready"
    @State private var errorMessage: String?

    @State private var rdsPS: String = ""
    @State private var rdsRT: String = ""
    @State private var rdsStereo: Bool = false

    @State private var statusPollTask: Task<Void, Never>?
    @State private var siteLoadTask: Task<Void, Never>?

    @StateObject private var pcmPlayer = PCMStreamPlayer()

    private var parsedFreq: Double? {
        let v = Double(freqText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return (v >= 87.5 && v <= 108.0) ? v : nil
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
                            playerCard
                            if !sites.isEmpty {
                                siteCard
                            }
                        }
                        if let error = errorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("FM Scanner")
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
            .onDisappear {
                stopStatusPoll()
                pcmPlayer.stop()
            }
            .onReceive(pcmPlayer.$status) { s in
                statusText = s.label
                if s == .playing  { isStreaming = true }
                if s == .stopped || s == .idle { isStreaming = false }
            }
        }
    }

    // MARK: - Player Card

    private var playerCard: some View {
        PanelCard {
            VStack(spacing: 0) {

                // ── Station / frequency header ───────────────────────────────
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        if isStreaming && !rdsPS.isEmpty {
                            Text(rdsPS)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Theme.primaryText)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        HStack(spacing: 8) {
                            Text(String(format: "%.1f MHz", parsedFreq ?? freqMHz))
                                .font(.system(size: isStreaming && !rdsPS.isEmpty ? 18 : 28,
                                              weight: .bold, design: .monospaced))
                                .foregroundStyle(isStreaming ? Theme.brandBlue : Theme.primaryText)
                                .contentTransition(.numericText())

                            if isStreaming && rdsStereo {
                                HStack(spacing: 3) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.caption2.weight(.semibold))
                                    Text("STEREO")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(Theme.okGreen)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.okGreen.opacity(0.15)))
                                .overlay(Capsule().stroke(Theme.okGreen.opacity(0.4), lineWidth: 1))
                            }
                        }
                    }

                    Spacer()

                    // Live badge
                    VStack(alignment: .trailing, spacing: 6) {
                        if isStreaming {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.faultRed)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: Theme.faultRed.opacity(0.9), radius: 4)
                                Text("LIVE")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(Theme.faultRed)
                            }
                            .transition(.opacity)
                        }
                        statusIndicator
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isStreaming)
                .padding(.bottom, 14)

                // ── EQ Visualizer ────────────────────────────────────────────
                EqualizerBarsView(level: pcmPlayer.audioLevel, isActive: isStreaming)
                    .padding(.bottom, 14)

                // ── RadioText (RT) ────────────────────────────────────────────
                if isStreaming && !rdsRT.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(Theme.brandBlue)
                        Text(rdsRT)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.3), value: rdsRT)
                }

                Divider()
                    .background(Theme.panelBorder)
                    .padding(.bottom, 14)

                // ── Frequency input with nudge buttons ───────────────────────
                HStack(spacing: 10) {
                    Button { nudgeFreq(-0.1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.brandBlue.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    TextField("96.5", text: $freqText)
                        .keyboardType(.decimalPad)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(parsedFreq != nil ? Theme.primaryText : Theme.faultRed)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.panelSecondary.opacity(0.55))
                        )
                        .frame(maxWidth: .infinity)

                    Button { nudgeFreq(0.1) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.brandBlue.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 14)

                // ── Transport buttons ────────────────────────────────────────
                HStack(spacing: 10) {
                    if isStreaming {
                        Button { Task { await tuneAction() } } label: {
                            Label("Retune", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandBlue)
                        .disabled(parsedFreq == nil || isLoading)

                        Button { Task { await stopAction() } } label: {
                            Label("Stop", systemImage: "stop.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.faultRed)
                        .disabled(isLoading)
                    } else {
                        Button { Task { await startAction() } } label: {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                Text("Play")
                                    .font(.title3.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.okGreen)
                        .disabled(selectedSite.isEmpty || parsedFreq == nil || isLoading)
                    }

                    if isLoading {
                        ProgressView().tint(Theme.brandBlue)
                    }
                }

                // ── Status line ──────────────────────────────────────────────
                if statusText != "Ready" && !statusText.isEmpty {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(Theme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var statusIndicator: some View {
        Circle()
            .fill(isStreaming ? Theme.okGreen : (isLoading ? Theme.pendingAmber : Theme.mutedText.opacity(0.4)))
            .frame(width: 10, height: 10)
            .shadow(color: isStreaming ? Theme.okGreen.opacity(0.8) : .clear, radius: 6)
    }

    // MARK: - Site Card

    private var siteCard: some View {
        PanelCard(title: "SDR Source") {
            VStack(alignment: .leading, spacing: 10) {
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

    // MARK: - Unavailable

    private var unavailableCard: some View {
        PanelCard {
            VStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.mutedText)
                Text("FM Scanner Not Available")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("No sites with scanner dongles found. Assign a dongle the 'scanner' role in Settings → SDR Devices on a client node, then wait for the next heartbeat.")
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

    // MARK: - Frequency nudge

    private func nudgeFreq(_ delta: Double) {
        let current = Double(freqText.replacingOccurrences(of: ",", with: ".")) ?? freqMHz
        let stepped = (current * 10 + delta * 10).rounded() / 10
        let clamped = max(87.5, min(108.0, stepped))
        freqText = String(format: "%.1f", clamped)
    }

    // MARK: - Actions (unchanged)

    private func loadSites() async {
        guard appModel.api.baseURL != nil else {
            errorMessage = "Configure your Hub URL in Settings."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            sites = try await appModel.api.fetchScannerSites()
            if selectedSite.isEmpty, let first = sites.first {
                selectedSite = first.site
                selectedSerial = first.serials.first ?? ""
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAction() async {
        guard let freq = parsedFreq, !selectedSite.isEmpty else { return }
        freqMHz = freq
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appModel.api.startScanner(site: selectedSite, freqMHz: freq, sdrSerial: selectedSerial)
            guard result.ok, let slotID = result.slot_id else {
                errorMessage = result.error ?? "Failed to start scanner"
                return
            }
            errorMessage = nil
            let pcmURL = appModel.api.authorizedPlaybackURL(
                for: resolveStreamURL("/api/mobile/hub/scanner/stream/\(slotID)")
            )
            pcmPlayer.start(url: pcmURL)
            startStatusPoll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func tuneAction() async {
        guard let freq = parsedFreq else { return }
        freqMHz = freq
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appModel.api.tuneScanner(site: selectedSite, freqMHz: freq)
            guard result.ok, let slotID = result.slot_id else {
                errorMessage = result.error ?? "Tune failed"
                return
            }
            rdsPS = ""; rdsRT = ""; rdsStereo = false
            let pcmURL = appModel.api.authorizedPlaybackURL(
                for: resolveStreamURL("/api/mobile/hub/scanner/stream/\(slotID)")
            )
            pcmPlayer.start(url: pcmURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAction() async {
        stopStatusPoll()
        pcmPlayer.stop()
        isStreaming = false
        rdsPS = ""; rdsRT = ""; rdsStereo = false
        statusText = "Ready"
        do {
            try await appModel.api.stopScanner(site: selectedSite)
        } catch { }
    }

    // MARK: - Status polling

    private func startStatusPoll() {
        stopStatusPoll()
        statusPollTask = Task {
            while !Task.isCancelled {
                do {
                    let status = try await appModel.api.fetchScannerStatus(site: selectedSite)
                    if status.active {
                        rdsPS     = status.ps ?? ""
                        rdsRT     = status.rt ?? ""
                        rdsStereo = status.stereo ?? false
                        if status.streaming == true {
                            statusText = String(format: "Streaming %.1f MHz", status.freq_mhz ?? freqMHz)
                        } else {
                            statusText = "Buffering…"
                        }
                    } else {
                        isStreaming = false
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
