import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget

struct ChainFaultLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChainFaultAttributes.self) { context in
            // Lock Screen / Notification Centre view
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (long-press the island)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            PulsingDot()
                            Text(context.state.isRecovered ? "RECOVERED" : "FAULT")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(context.state.isRecovered ? .green : .red)
                        }
                        Text(context.attributes.chainName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Duration")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        if context.state.isRecovered {
                            Text("Resolved")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.green)
                        } else {
                            Text(context.state.faultSince, style: .timer)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !context.state.faultAt.isEmpty {
                            Label(context.state.faultAt, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                        Text(context.state.faultReason)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                        NodeStatusStrip(statuses: context.state.nodeStatuses)
                    }
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: context.state.isRecovered
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(context.state.isRecovered ? .green : .red)
                        .font(.caption.weight(.semibold))
                }
            } compactTrailing: {
                if context.state.isRecovered {
                    Text("OK")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Text(context.state.faultSince, style: .timer)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.red)
                        .frame(maxWidth: 36)
                }
            } minimal: {
                Image(systemName: context.state.isRecovered
                      ? "checkmark.circle.fill"
                      : "exclamationmark.triangle.fill")
                    .foregroundStyle(context.state.isRecovered ? .green : .red)
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<ChainFaultAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack {
                HStack(spacing: 6) {
                    Image("signalscope_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text("SignalScope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                // Status badge
                Text(context.state.isRecovered ? "RECOVERED" : "ACTIVE FAULT")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(context.state.isRecovered ? Color.green : Color.red))
            }

            // Chain name + timer
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.chainName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if context.state.isRecovered {
                    Text("Resolved")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Duration")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Text(context.state.faultSince, style: .timer)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }

            // Fault location
            if !context.state.faultAt.isEmpty {
                Label(context.state.faultAt, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }

            // Fault reason
            Text(context.state.faultReason)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)

            // Node status strip
            NodeStatusStrip(statuses: context.state.nodeStatuses)
        }
        .padding(14)
        .background(Color(red: 0.05, green: 0.13, blue: 0.27))
    }
}

// MARK: - Shared sub-views

private struct NodeStatusStrip: View {
    let statuses: [ChainFaultAttributes.ContentState.NodeStatus]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(statuses, id: \.label) { node in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(color(for: node.status))
                            .frame(width: 7, height: 7)
                        Text(node.label)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color(for: node.status).opacity(0.15))
                    )
                }
            }
        }
    }

    private func color(for status: String) -> Color {
        switch status.lowercased() {
        case "ok":                          return .green
        case "down", "offline", "fault":    return .red
        case "maintenance":                 return .yellow
        default:                            return .gray
        }
    }
}

private struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(pulsing ? 0 : 0.35))
                .frame(width: 14, height: 14)
                .scaleEffect(pulsing ? 1.4 : 1.0)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}
