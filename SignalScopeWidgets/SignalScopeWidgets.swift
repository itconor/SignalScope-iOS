import WidgetKit
import SwiftUI

// MARK: - Shared UserDefaults keys
// The App Group "group.com.signalscope.app" must be enabled in Xcode for both
// the SignalScope and SignalScopeWidgets targets (Signing & Capabilities →
// App Groups). Without the entitlement the widget reads from standard defaults,
// which will show stale/zero data but will not crash.

private let kAppGroupSuite = "group.com.signalscope.app"
private let kFaultCount     = "faultCount"
private let kWorstChainName = "worstChainName"
private let kWorstChainStatus = "worstChainStatus"
private let kLastUpdated    = "lastUpdated"

// MARK: - Timeline Entry

struct FaultStatusEntry: TimelineEntry {
    let date: Date
    let faultCount: Int
    let worstChainName: String
    let worstChainStatus: String
    let lastUpdated: Date?
}

// MARK: - Timeline Provider

struct FaultStatusProvider: TimelineProvider {

    private func readEntry(for date: Date) -> FaultStatusEntry {
        let defaults = UserDefaults(suiteName: kAppGroupSuite) ?? UserDefaults.standard
        let faultCount     = defaults.integer(forKey: kFaultCount)
        let worstChainName = defaults.string(forKey: kWorstChainName) ?? ""
        let worstChainStatus = defaults.string(forKey: kWorstChainStatus) ?? "ok"
        let lastUpdatedTS  = defaults.double(forKey: kLastUpdated)
        let lastUpdated    = lastUpdatedTS > 0 ? Date(timeIntervalSince1970: lastUpdatedTS) : nil
        return FaultStatusEntry(
            date: date,
            faultCount: faultCount,
            worstChainName: worstChainName,
            worstChainStatus: worstChainStatus,
            lastUpdated: lastUpdated
        )
    }

    func placeholder(in context: Context) -> FaultStatusEntry {
        FaultStatusEntry(date: Date(), faultCount: 0, worstChainName: "All Clear",
                         worstChainStatus: "ok", lastUpdated: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FaultStatusEntry) -> Void) {
        completion(readEntry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FaultStatusEntry>) -> Void) {
        let entry = readEntry(for: Date())
        // Refresh every 15 minutes
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - Small Widget View

private struct FaultStatusSmallView: View {
    let entry: FaultStatusEntry

    private var hasFaults: Bool { entry.faultCount > 0 }
    private var badgeColor: Color { hasFaults ? .red : .green }
    private var statusIcon: String { hasFaults ? "exclamationmark.triangle.fill" : "checkmark.circle.fill" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("SignalScope")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Fault count badge
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    if hasFaults {
                        Text("\(entry.faultCount)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(badgeColor)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.title3)
                            .foregroundStyle(badgeColor)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasFaults ? (entry.faultCount == 1 ? "1 fault" : "\(entry.faultCount) faults") : "All Clear")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if hasFaults, !entry.worstChainName.isEmpty {
                        Text(entry.worstChainName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let updated = entry.lastUpdated {
                Text(updated, style: .relative)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(white: 0.05))
    }
}

// MARK: - Medium Widget View

private struct FaultStatusMediumView: View {
    let entry: FaultStatusEntry

    private var hasFaults: Bool { entry.faultCount > 0 }
    private var badgeColor: Color { hasFaults ? .red : .green }

    var body: some View {
        HStack(spacing: 16) {
            // Left column: count badge
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(0.2))
                        .frame(width: 56, height: 56)
                    if hasFaults {
                        Text("\(entry.faultCount)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(badgeColor)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(badgeColor)
                    }
                }
                Text(hasFaults ? (entry.faultCount == 1 ? "Fault" : "Faults") : "All Clear")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Right column: detail
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("SignalScope")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if hasFaults {
                    if !entry.worstChainName.isEmpty {
                        Label(entry.worstChainName, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(badgeColor)
                            .lineLimit(2)
                    }
                    if !entry.worstChainStatus.isEmpty, entry.worstChainStatus != "ok" {
                        Text(entry.worstChainStatus.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No active faults")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                if let updated = entry.lastUpdated {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(updated, style: .relative)
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.05))
    }
}

// MARK: - Widget Definition

struct SignalScopeWidgets: Widget {
    let kind: String = "SignalScopeWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FaultStatusProvider()) { entry in
            Group {
                if #available(iOSApplicationExtension 17.0, *) {
                    widgetView(entry: entry)
                        .containerBackground(Color(white: 0.05), for: .widget)
                } else {
                    widgetView(entry: entry)
                }
            }
        }
        .configurationDisplayName("Fault Status")
        .description("Shows active fault count and worst chain status.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    @ViewBuilder
    private func widgetView(entry: FaultStatusEntry) -> some View {
        GeometryReader { geo in
            if geo.size.width > 200 {
                FaultStatusMediumView(entry: entry)
            } else {
                FaultStatusSmallView(entry: entry)
            }
        }
    }
}
