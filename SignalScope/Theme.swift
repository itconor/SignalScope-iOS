import SwiftUI

enum Theme {
    // Palette
    static let backgroundTop = Color(hex: "04112A")
    static let backgroundBottom = Color(hex: "030A18")
    static let panel = Color(hex: "0D2754")
    static let panelSecondary = Color(hex: "113163")
    static let panelBorder = Color(hex: "1F4C8E").opacity(0.6)
    static let brandBlue = Color(hex: "27A5FF")
    static let brandBlueDark = Color(hex: "1350A5")
    static let okGreen = Color(hex: "18E471")
    static let pendingAmber = Color(hex: "FFAE00")
    static let faultRed = Color(hex: "FF4F4F")
    static let primaryText = Color(hex: "FFFFFF")
    static let secondaryText = Color(hex: "ACC2E4")
    static let mutedText = Color(hex: "7A96C3")

    static let backgroundGradient = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Equalizer Bars Visualizer

struct EqualizerBarsView: View {
    /// RMS audio level 0–1. Drive from real PCM data or a simulated timer value.
    var level: Float
    /// Whether playback is active. Bars collapse when false.
    var isActive: Bool

    private let barCount = 20

    // Per-bar random multipliers seeded once — give each bar its own personality
    @State private var multipliers: [Double] = []
    @State private var heights: [Double] = Array(repeating: 2, count: 20)

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2.5
            let barW = (geo.size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(eqGradient)
                        .frame(width: max(1, barW),
                               height: max(2, heights.indices.contains(i) ? heights[i] : 2))
                        .animation(.spring(response: 0.13, dampingFraction: 0.52), value: heights[i])
                }
            }
        }
        .frame(height: 48)
        .onAppear {
            guard multipliers.isEmpty else { return }
            // Bell-curve shape — mids higher than bass/treble, then randomised
            multipliers = (0..<barCount).map { i in
                let pos = Double(i) / Double(barCount - 1)   // 0…1
                let curve = 1.0 - pow(abs(pos - 0.45) * 1.8, 2.0)
                return max(0.15, curve) * Double.random(in: 0.55...1.45)
            }
        }
        .onChange(of: level) { _, lvl in
            guard isActive, !multipliers.isEmpty else { return }
            // RMS of typical speech/music is ~0.03–0.25; scale to fill the bars
            let scaled = min(1.0, Double(lvl) * 5.5)
            heights = multipliers.map { m in
                let h = scaled * m * 46.0 + Double.random(in: -2...2)
                return max(2, min(48, h))
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                withAnimation(.easeOut(duration: 0.7)) {
                    heights = Array(repeating: 2, count: barCount)
                }
            }
        }
    }

    private var eqGradient: LinearGradient {
        LinearGradient(
            colors: [
                Theme.brandBlue.opacity(0.75),
                Theme.brandBlue,
                Color(red: 0.12, green: 0.92, blue: 0.72)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: - Panel Card

struct PanelCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
            }
            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.panelBorder, lineWidth: 1)
        )
    }
}

enum ChainDisplayStatus: String, Codable, CaseIterable {
    case ok, pending, fault, adbreak, unknown

    var color: Color {
        switch self {
        case .ok: return Theme.okGreen
        case .pending, .adbreak: return Theme.pendingAmber
        case .fault: return Theme.faultRed
        case .unknown: return Theme.mutedText
        }
    }

    var label: String { rawValue.uppercased() }
}

struct StatusPill: View {
    let status: ChainDisplayStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(status.color)
            )
            .accessibilityLabel("Status: \(status.label)")
    }
}

struct MetricChip: View {
    let icon: String?
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(Theme.brandBlue)
            }
            Text(text)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panelSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.panelBorder.opacity(0.6), lineWidth: 1)
        )
    }
}

struct PanelCard_Previews: PreviewProvider {
    static var previews: some View {
        PanelCard(title: "Panel Title") {
            Text("This is the content of the panel.")
                .foregroundColor(Theme.primaryText)
        }
        .padding()
        .background(Theme.backgroundGradient)
        .previewLayout(.sizeThatFits)
    }
}

struct StatusPill_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            ForEach(ChainDisplayStatus.allCases, id: \.self) { status in
                StatusPill(status: status)
            }
        }
        .padding()
        .background(Theme.backgroundGradient)
        .previewLayout(.sizeThatFits)
    }
}

struct MetricChip_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            MetricChip(icon: "bolt.fill", text: "Fast")
            MetricChip(icon: nil, text: "No Icon")
        }
        .padding()
        .background(Theme.backgroundGradient)
        .previewLayout(.sizeThatFits)
    }
}
