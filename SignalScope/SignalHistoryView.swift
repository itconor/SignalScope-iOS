import SwiftUI
import Charts

struct SignalHistoryView: View {
    let streamName: String
    let siteName: String

    @EnvironmentObject private var appModel: AppModel
    @State private var selectedMetric: MetricOption = .level
    @State private var selectedHours: Int = 6
    @State private var historyPoints: [MetricPoint] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum MetricOption: String, CaseIterable, Identifiable {
        case level      = "level_dbfs"
        case lufs_m     = "lufs_m"
        case lufs_i     = "lufs_i"
        case rtp_loss   = "rtp_loss_pct"
        case rtp_jitter = "rtp_jitter_ms"
        case fm_signal  = "fm_signal_dbm"
        case fm_snr     = "fm_snr_db"
        case dab_snr    = "dab_snr"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .level:      return "Level (dBFS)"
            case .lufs_m:     return "LUFS Momentary"
            case .lufs_i:     return "LUFS Integrated"
            case .rtp_loss:   return "RTP Loss %"
            case .rtp_jitter: return "RTP Jitter (ms)"
            case .fm_signal:  return "FM Signal (dBm)"
            case .fm_snr:     return "FM SNR (dB)"
            case .dab_snr:    return "DAB SNR"
            }
        }

        var unit: String {
            switch self {
            case .rtp_loss:   return "%"
            case .rtp_jitter: return "ms"
            default:          return "dB"
            }
        }

        var lineColor: Color {
            switch self {
            case .rtp_loss, .rtp_jitter: return Theme.pendingAmber
            default:                     return Theme.brandBlue
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    controlsCard
                    chartCard
                }
                .padding()
            }
        }
        .navigationTitle(streamName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .onChange(of: selectedMetric) { _, _ in Task { await loadData() } }
        .onChange(of: selectedHours)  { _, _ in Task { await loadData() } }
    }

    // MARK: - Controls

    private var controlsCard: some View {
        PanelCard(title: "Signal History") {
            VStack(alignment: .leading, spacing: 12) {
                if !siteName.isEmpty {
                    Text(siteName)
                        .font(.caption)
                        .foregroundStyle(Theme.mutedText)
                }

                Picker("Time Range", selection: $selectedHours) {
                    Text("1h").tag(1)
                    Text("6h").tag(6)
                    Text("24h").tag(24)
                }
                .pickerStyle(.segmented)

                Picker("Metric", selection: $selectedMetric) {
                    ForEach(MetricOption.allCases) { opt in
                        Text(opt.displayName).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .foregroundStyle(Theme.brandBlue)
            }
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().tint(Theme.brandBlue).scaleEffect(1.2)
                        Spacer()
                    }
                    .frame(height: 200)
                } else if let error = errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.mutedText)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.mutedText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                } else if historyPoints.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.mutedText)
                        Text("No data for this period")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                } else {
                    Chart(historyPoints) { point in
                        LineMark(
                            x: .value("Time",  Date(timeIntervalSince1970: point.ts)),
                            y: .value(selectedMetric.displayName, point.value)
                        )
                        .foregroundStyle(selectedMetric.lineColor)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            if let date = value.as(Date.self) {
                                AxisValueLabel {
                                    Text(date, format: selectedHours <= 1
                                         ? .dateTime.hour().minute()
                                         : .dateTime.hour())
                                        .font(.caption2)
                                        .foregroundStyle(Theme.mutedText)
                                }
                            }
                            AxisGridLine().foregroundStyle(Theme.panelBorder.opacity(0.5))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            if let v = value.as(Double.self) {
                                AxisValueLabel {
                                    Text(String(format: "%.1f", v))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.mutedText)
                                }
                            }
                            AxisGridLine().foregroundStyle(Theme.panelBorder.opacity(0.5))
                        }
                    }
                    .frame(height: 220)
                    .padding(.bottom, 4)

                    statsRow
                }
            }
        }
    }

    private var statsRow: some View {
        let values = historyPoints.map(\.value)
        guard let minVal = values.min(), let maxVal = values.max() else {
            return AnyView(EmptyView())
        }
        let avg = values.reduce(0, +) / Double(values.count)
        let unit = selectedMetric.unit

        return AnyView(
            HStack(spacing: 16) {
                statLabel("Min",    String(format: "%.1f %@", minVal, unit))
                statLabel("Avg",    String(format: "%.1f %@", avg,    unit))
                statLabel("Max",    String(format: "%.1f %@", maxVal, unit))
                Spacer()
                Text("\(historyPoints.count) pts")
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedText)
            }
        )
    }

    private func statLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.mutedText)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
        }
    }

    // MARK: - Data

    private func loadData() async {
        guard appModel.api.baseURL != nil else {
            errorMessage = "No hub URL configured"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await appModel.api.fetchMetricHistory(
                stream: streamName,
                site: siteName.isEmpty ? nil : siteName,
                metric: selectedMetric.rawValue,
                hours: selectedHours
            )
            historyPoints = result.points
        } catch {
            if error is CancellationError { return }
            errorMessage = error.localizedDescription
        }
    }
}
