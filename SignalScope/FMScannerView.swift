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
    @State private var statusText = "Idle"
    @State private var errorMessage: String?

    @State private var rdsPS: String = ""
    @State private var rdsRT: String = ""
    @State private var rdsStereo: Bool = false

    @State private var statusPollTask: Task<Void, Never>?
    @State private var siteLoadTask: Task<Void, Never>?

    // Custom PCM player — AVPlayer cannot handle raw PCM streams
    @StateObject private var pcmPlayer = PCMStreamPlayer()

    private var parsedFreq: Double? {
        let v = Double(freqText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return (v >= 87.5 && v <= 108.0) ? v : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if sites.isEmpty && !isLoading {
                        unavailableCard
                    } else {
                        sitePickerCard
                        tunerCard
                        rdsCard
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
            .navigationTitle("FM Scanner")
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
            .task { await loadSites() }
            .onDisappear {
                stopStatusPoll()
                pcmPlayer.stop()
            }
            .onReceive(pcmPlayer.$status) { s in
                statusText = s.label
                if s == .playing { isStreaming = true }
                if s == .stopped || s == .idle { isStreaming = false }
            }
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

    // MARK: - Tuner Card

    private var tunerCard: some View {
        PanelCard(title: "Tuner") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Frequency (MHz)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        TextField("96.5", text: $freqText)
                            .keyboardType(.decimalPad)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .foregroundStyle(parsedFreq != nil ? Theme.brandBlue : Theme.faultRed)
                            .frame(maxWidth: 120)
                    }

                    Spacer()

                    statusDot
                }

                HStack(spacing: 10) {
                    if isStreaming {
                        Button {
                            Task { await tuneAction() }
                        } label: {
                            Label("Tune", systemImage: "arrow.triangle.2.circlepath")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brandBlue)
                        .disabled(parsedFreq == nil || isLoading)

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
                        .disabled(selectedSite.isEmpty || parsedFreq == nil || isLoading)
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
            .shadow(color: (isStreaming ? Theme.okGreen : (isLoading ? Theme.pendingAmber : Color.clear)).opacity(0.6), radius: 4)
    }

    // MARK: - RDS Card

    private var rdsCard: some View {
        PanelCard(title: "RDS") {
            VStack(alignment: .leading, spacing: 10) {
                if rdsPS.isEmpty && rdsRT.isEmpty && !isStreaming {
                    Text("Start streaming to see RDS data")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedText)
                } else {
                    HStack(spacing: 8) {
                        if rdsStereo {
                            Label("Stereo", systemImage: "speaker.2.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.okGreen)
                        }
                        if !rdsPS.isEmpty {
                            Text(rdsPS)
                                .font(.system(.headline, design: .monospaced).weight(.bold))
                                .foregroundStyle(Theme.brandBlue)
                        }
                    }
                    if !rdsRT.isEmpty {
                        Text(rdsRT)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                    if rdsPS.isEmpty && rdsRT.isEmpty && isStreaming {
                        Text("Waiting for RDS data…")
                            .font(.caption)
                            .foregroundStyle(Theme.mutedText)
                    }
                }
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
                Text("FM Scanner Not Available")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("No sites with scanner dongles found. Assign a dongle the 'scanner' role in Settings → SDR Devices on a client node, then wait for the next heartbeat.")
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
            // Use the raw PCM endpoint — PCMStreamPlayer handles decoding directly
            // (AVPlayer cannot play raw PCM streams)
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
        do {
            try await appModel.api.stopScanner(site: selectedSite)
        } catch {
            // Non-fatal — local state already cleaned up
        }
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
                } catch {
                    // Ignore poll errors — keep trying
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
