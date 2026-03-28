import ActivityKit
import Foundation

/// Attributes and dynamic content state for the SignalScope chain-fault Live Activity.
/// This file must be added to BOTH the main app target AND the widget extension target.
struct ChainFaultAttributes: ActivityAttributes {

    // MARK: - Dynamic content (changes while activity is live)
    public struct ContentState: Codable, Hashable {
        /// One-line reason for the fault (or "Recovered" when isRecovered is true)
        var faultReason: String
        /// Label of the node where the fault is (e.g. "Studio Feed")
        var faultAt: String
        /// Per-node statuses for the mini strip — label + status string
        var nodeStatuses: [NodeStatus]
        /// When the fault started — drives the SwiftUI timer display
        var faultSince: Date
        /// True for the brief window before the activity is ended after recovery
        var isRecovered: Bool

        struct NodeStatus: Codable, Hashable {
            var label: String
            var status: String   // "ok" | "down" | "offline" | "unknown" | "maintenance"
        }
    }

    // MARK: - Fixed metadata (set at start, cannot change)
    let chainID: String
    let chainName: String
}
