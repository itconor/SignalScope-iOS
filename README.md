# SignalScope iOS

The iOS companion app for [SignalScope](https://github.com/itconor/SignalScope) — a broadcast signal intelligence platform. Monitor broadcast chain health, receive fault alerts, and playback audio clips from anywhere.

---

## Features

- **Real-time fault monitoring** — live view of active faults across all monitored broadcast chains
- **Chain status** — hierarchical node tree showing signal levels, RTP loss, and health per node
- **Push notifications** — APNs alerts for new faults with deep linking directly to the affected chain
- **Live Activities** — lock screen and Dynamic Island widgets showing active fault details and duration
- **Audio clip playback** — stream or download fault-triggered audio clips in-app
- **Signal history charts** — 6, 12, or 24-hour time-series for level, RTP loss, FM signal, DAB SNR, and more
- **Hub overview** — per-site stream cards with RDS PS/RT, DAB service names, DLS text, and AI status
- **Engineer notes** — attach timestamped notes to fault log entries
- **Reports** — paginated historical fault event log with per-site summaries
- **Widgets** — home screen widget (future) and Live Activity for active faults

---

## Requirements

- iOS 16.2+ (Live Activities require iOS 16.2; core features work on iOS 16.0+)
- A running [SignalScope](https://github.com/itconor/SignalScope) hub with the mobile API enabled
- Xcode 15+

---

## Getting Started

1. Clone the repo and open `SignalScope.xcodeproj` in Xcode
2. Set your development team in **Signing & Capabilities**
3. Build and run on a device or simulator
4. Open the app and go to **Settings**
5. Enter your hub URL (e.g. `https://hub.example.com`) and API token
6. Tap **Save & Connect** — the app will start polling immediately

---

## Configuration

All configuration is done in-app under the **Settings** tab:

| Setting | Description |
|---|---|
| Hub URL | Full URL of your SignalScope hub |
| API Token | Authentication token (stored securely in device keychain) |
| Refresh interval | How often to poll for updates (5–120 seconds) |

---

## Architecture

| File | Description |
|---|---|
| `AppModel.swift` | Central state — chains, faults, audio playback, polling, push notifications |
| `APIClient.swift` | All HTTP requests to the hub; Bearer token and X-API-Key auth |
| `Models.swift` | Codable data models (chains, nodes, streams, metrics, reports) |
| `ContentView.swift` | Tab bar root with fault banner and mini audio player overlay |
| `HubOverviewView.swift` | Sites tab — hub summary and per-site stream cards |
| `FaultsView.swift` | Faults tab — active faults with local acknowledgment |
| `ChainsListView.swift` | Chains tab — searchable, filterable chain list |
| `ChainDetailView.swift` | Chain detail — node tree, fault log, audio clips, engineer notes |
| `SignalHistoryView.swift` | Signal history charts using Apple Charts |
| `LiveActivityManager.swift` | iOS Live Activity lifecycle for active fault widgets |
| `NotificationManager.swift` | APNs registration, local notifications, deep link routing |
| `Theme.swift` | Colour palette, gradients, and shared UI components |

---

## Hub API Endpoints Used

The app communicates with the SignalScope hub over HTTPS:

```
GET  /api/mobile/hub/overview
GET  /api/mobile/chains
GET  /api/mobile/chains/{id}
GET  /api/mobile/active_faults
GET  /api/mobile/reports/events
GET  /api/mobile/metrics/history
POST /api/mobile/device_token
POST /api/mobile/chain_notes/{fault_log_id}
```

---

## Related

- [SignalScope Hub](https://github.com/itconor/SignalScope) — the Python/Flask backend this app connects to
