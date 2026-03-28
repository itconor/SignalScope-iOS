import SwiftUI
import UIKit

// MARK: - Sidebar-adaptable tab style (iPad / iOS 18+)
// On iPadOS 18+ the new tab bar design can silently drop tabs from the
// "More" overflow when using the legacy .tabItem{} API with many tabs.
// .sidebarAdaptable shows ALL tabs in a collapsible sidebar on iPad and
// falls back to the standard bottom bar on iPhone / iOS 17.
private extension View {
    @ViewBuilder
    func adaptiveTabStyle() -> some View {
        if #available(iOS 18.0, *) {
            self.tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    // MARK: - Orientation management
    // Logger tab (7) locks to landscape only when LoggerDayView is pushed.
    // All other situations → portrait.  We explicitly request portrait on unlock
    // so the app snaps back immediately rather than waiting for a physical tilt.

    /// Called once on cold launch to snap back to portrait regardless of what
    /// orientation the previous session left the window in.
    private func forcePortrait() {
        AppDelegate.orientationLock = .all
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
            ) { _ in }
        }
    }

    private func applyOrientation() {
        let wantLandscape = appModel.lastSelectedTab == 7 && appModel.loggerDayViewActive
        if wantLandscape {
            guard AppDelegate.orientationLock != .landscape else { return }
            AppDelegate.orientationLock = .landscape
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(
                    UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
                ) { _ in }
            }
        } else {
            guard AppDelegate.orientationLock != .all else { return }
            AppDelegate.orientationLock = .all
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                // Explicitly request portrait to snap back — .all alone only *permits*
                // portrait but doesn't rotate; the user would otherwise have to tilt.
                scene.requestGeometryUpdate(
                    UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
                ) { _ in }
            }
        }
    }

    var body: some View {
        TabView(selection: $appModel.lastSelectedTab) {
            HubOverviewView()
                .tabItem {
                    Image(systemName: "server.rack")
                    Text("Sites")
                }
                .tag(0)

            FaultsView()
                .tabItem {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Faults")
                }
                .badge(appModel.displayedFaults.count)
                .tag(1)

            ChainsListView()
                .tabItem {
                    Image(systemName: "waveform.path.ecg")
                    Text("Chains")
                }
                .tag(2)

            ABGroupsView()
                .tabItem {
                    Label("A/B Groups", systemImage: "arrow.left.arrow.right.circle")
                }
                .tag(3)

            ReportsView()
                .tabItem {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Reports")
                }
                .tag(4)

            FMScannerView()
                .tabItem {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("FM")
                }
                .tag(5)

            DABScannerView()
                .tabItem {
                    Image(systemName: "radio")
                    Text("DAB")
                }
                .tag(6)

            LoggerView()
                .tabItem {
                    Image(systemName: "waveform.and.mic")
                    Text("Logger")
                }
                .tag(7)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(8)
        }
        .adaptiveTabStyle()
        .tint(Theme.brandBlue)
        .preferredColorScheme(.dark)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        // Force portrait on cold launch — onChange never fires at startup so a previous
        // landscape session would leave the app stuck sideways without this.
        .onAppear { forcePortrait() }
        // Tab switch → always re-evaluate orientation (ensures unlock when leaving Logger)
        .onChange(of: appModel.lastSelectedTab)    { applyOrientation() }
        // LoggerDayView pushed/popped → lock or unlock within the Logger tab
        .onChange(of: appModel.loggerDayViewActive) { applyOrientation() }
        .overlay(alignment: .top) {
            if appModel.hasActiveFaults {
                faultBanner
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let item = appModel.currentAudioItem {
                MiniPlayerBar(item: item)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
    }

    private var faultBanner: some View {
        Button {
            appModel.lastSelectedTab = 1
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .foregroundStyle(Theme.faultRed)
                Text(appModel.activeFaultBannerText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.mutedText)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel.opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.faultRed.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct MiniPlayerBar: View {
    @EnvironmentObject private var appModel: AppModel
    let item: AudioQueueItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(item.subtitle ?? appModel.audioStatusText)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if appModel.isPreparingClipPlayback {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.brandBlue)
                        Text(appModel.clipPlaybackStatusText.isEmpty ? "Preparing clip…" : appModel.clipPlaybackStatusText)
                            .font(.caption2)
                            .foregroundStyle(Theme.mutedText)
                            .lineLimit(1)
                    }
                } else if !appModel.audioStatusText.isEmpty {
                    Text(appModel.audioStatusText)
                        .font(.caption2)
                        .foregroundStyle(Theme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button {
                    appModel.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primaryText)

                Button {
                    appModel.togglePlayback()
                } label: {
                    Image(systemName: appModel.isAudioPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.brandBlue)

                Button {
                    appModel.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primaryText)

                Button {
                    appModel.stopAudio()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.mutedText)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.panelBorder.opacity(0.7), lineWidth: 1))
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
