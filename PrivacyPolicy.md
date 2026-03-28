# Privacy Policy — SignalScope

**Last updated: 28 March 2026**

## Overview

SignalScope is a professional broadcast monitoring application for iOS. This policy explains what data the app accesses, how it is used, and your rights as a user.

SignalScope is designed for broadcast engineers. It connects exclusively to a SignalScope hub server that **you configure and control**. We do not operate any centralised servers that receive your data, and we do not collect, store, or share any personal information.

---

## 1. Data We Do Not Collect

We do **not** collect, store, or transmit any of the following:

- Personal information (name, email address, phone number)
- Location data
- Usage analytics or crash reports sent to us
- Advertising identifiers
- Browsing history or cross-app tracking data

SignalScope does **not** track you across apps or websites.

---

## 2. Data Stored Locally on Your Device

The following information is stored **only on your device** using iOS standard storage (UserDefaults / App Storage):

| Data | Purpose |
|------|---------|
| Hub URL | The address of your SignalScope monitoring hub |
| API token | Authentication credential for your hub |
| Refresh interval | Your preferred polling frequency |
| Acknowledged faults | Which faults you have already reviewed |
| Recent fault history | A short local cache for offline display |
| Push notification token | Registered with your hub only (see below) |

This data never leaves your device except to communicate with **the hub URL you have configured**.

---

## 3. Communication With Your Hub

SignalScope connects to the hub server address you provide in Settings. All network requests go directly to that server. The app:

- Polls your hub for signal status, fault events, and audio streams
- Registers your device push notification token with your hub so alerts can be delivered
- Downloads audio clips stored on your hub for playback

Your hub is operated by you or your organisation, not by us. Its privacy practices are governed by your own policies.

---

## 4. Push Notifications

If you enable push notifications, your device token is registered with your SignalScope hub. The hub may forward alerts via Apple Push Notification service (APNs).

- Device tokens are stored on your hub only
- We do not have access to your device token
- You can revoke push permissions at any time in **iOS Settings → Notifications → SignalScope**

---

## 5. Audio Playback

SignalScope can stream and play audio from your hub (live streams and recorded clips). Audio data is streamed in real time and is not retained on your device beyond the duration of playback. Temporary files used during playback are deleted automatically when playback ends.

---

## 6. Local Network Access

SignalScope requests access to the local network so it can connect to a SignalScope hub running on your local Wi-Fi network. No data from your local network is collected or transmitted to us.

---

## 7. Widgets and Live Activities

The SignalScope widget and Live Activity features display fault and signal status information sourced from your hub. This information is stored in a shared App Group container accessible only to SignalScope and its extensions on your device.

---

## 8. Third-Party Services

SignalScope does not integrate with any third-party analytics, advertising, or tracking SDKs.

The app uses Apple's standard frameworks (AVFoundation, UserNotifications, ActivityKit, Charts) solely to provide its core functionality. These frameworks are subject to [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

---

## 9. Children's Privacy

SignalScope is a professional tool intended for use by broadcast engineers. It is not directed at children under 13, and we do not knowingly collect information from children.

---

## 10. Changes to This Policy

If we make material changes to this policy we will update the "Last updated" date at the top of this document and update the version available at the link provided in the App Store listing.

---

## 11. Contact

If you have questions about this privacy policy, please contact:

**Conor Ewings**
Email: conor@signalscope.site
Website: https://signalscope.site

---

*SignalScope is developed independently. This privacy policy applies to the iOS application "SignalScope" available on the Apple App Store.*
