import ActivityKit
import Foundation

/// Manages starting, updating, and ending Live Activities for chain faults.
/// Requires iOS 16.2+. All methods are safe to call on older OS — they are no-ops.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    // chainID → live activity (stored as Any to avoid @available everywhere)
    private var activities: [String: Any] = [:]

    // MARK: - Public API

    /// Start a new Live Activity for a faulted chain, or update it if one is already running.
    func startOrUpdate(for chain: ChainSummary) {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard chain.displayStatus == .fault else { return }

        let state = makeContentState(for: chain)

        if let existing = activities[chain.id] as? Activity<ChainFaultAttributes> {
            Task {
                await existing.update(
                    ActivityContent(state: state, staleDate: Date().addingTimeInterval(30))
                )
            }
        } else {
            let attributes = ChainFaultAttributes(chainID: chain.id, chainName: chain.name)
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(30)),
                    pushType: nil
                )
                activities[chain.id] = activity
                print("[LiveActivity] Started for '\(chain.name)'")
            } catch {
                print("[LiveActivity] Failed to start for '\(chain.name)': \(error)")
            }
        }
    }

    /// End the Live Activity for a chain.
    /// If `recovered` is true, briefly shows a "Recovered" state before dismissing.
    func end(chainID: String, recovered: Bool = false) {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = activities[chainID] as? Activity<ChainFaultAttributes> else { return }
        activities.removeValue(forKey: chainID)

        Task {
            if recovered {
                var finalState = activity.content.state
                finalState.isRecovered = true
                finalState.faultReason = "Recovered — all positions OK"
                await activity.update(
                    ActivityContent(state: finalState, staleDate: Date().addingTimeInterval(10))
                )
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            await activity.end(nil, dismissalPolicy: .immediate)
            print("[LiveActivity] Ended for chainID=\(chainID) recovered=\(recovered)")
        }
    }

    /// End all running Live Activities (e.g. on logout or server URL change).
    func endAll() {
        guard #available(iOS 16.2, *) else { return }
        for (_, activity) in activities {
            if let a = activity as? Activity<ChainFaultAttributes> {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
        }
        activities.removeAll()
    }

    // MARK: - Private helpers

    @available(iOS 16.2, *)
    private func makeContentState(for chain: ChainSummary) -> ChainFaultAttributes.ContentState {
        let nodeStatuses: [ChainFaultAttributes.ContentState.NodeStatus] = chain.nodes.flatMap { node in
            if node.isStack {
                return node.childNodes.map {
                    ChainFaultAttributes.ContentState.NodeStatus(label: $0.label, status: $0.status)
                }
            }
            return [ChainFaultAttributes.ContentState.NodeStatus(label: node.label, status: node.status)]
        }

        let faultSince: Date = {
            if let ts = chain.fault_since_ts { return Date(timeIntervalSince1970: ts) }
            return Date()
        }()

        return ChainFaultAttributes.ContentState(
            faultReason: chain.fault_reason ?? "Chain fault detected",
            faultAt: chain.fault_at ?? "",
            nodeStatuses: nodeStatuses,
            faultSince: faultSince,
            isRecovered: false
        )
    }
}
