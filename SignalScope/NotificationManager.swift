import Foundation
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
                UNUserNotificationCenter.current().delegate = self
            }
        }
    }

    // Called when app is foregrounded and a notification arrives — show it as a banner
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // Called when user taps a notification — deep-link into the app
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let chainID = userInfo["chain_id"] as? String, !chainID.isEmpty {
            NotificationCenter.default.post(name: .navigateToChain, object: chainID)
        }
    }

    func scheduleSilenceNotification(nodeName: String, chainName: String, site: String, level: Double?) {
        let content = UNMutableNotificationContent()
        content.title = "Silence detected: \(nodeName)"
        let levelStr = level.map { String(format: "%.0f dBFS", $0) } ?? "below threshold"
        let siteStr = site.isEmpty ? "" : " · \(site)"
        content.body = "\(chainName)\(siteStr) — \(levelStr)"
        content.sound = .default
        content.userInfo = ["type": "silence", "node": nodeName]
        let request = UNNotificationRequest(
            identifier: "silence_\(nodeName)_\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // Used when the app is in the background and needs to schedule a local fallback
    func scheduleFaultNotification(chain: ChainSummary) {
        let content = UNMutableNotificationContent()
        content.title = "Fault: \(chain.name)"
        content.body = chain.fault_reason ?? "Chain entered FAULT state"
        content.sound = .default
        if let faultAt = chain.fault_at, !faultAt.isEmpty {
            content.subtitle = "At \(faultAt)"
        }
        content.userInfo = ["chain_id": chain.id]

        let request = UNNotificationRequest(
            identifier: "fault_\(chain.id)_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// Notification names for cross-module communication
extension Notification.Name {
    static let deviceTokenReceived = Notification.Name("SignalScope.deviceTokenReceived")
    static let navigateToChain     = Notification.Name("SignalScope.navigateToChain")
}
