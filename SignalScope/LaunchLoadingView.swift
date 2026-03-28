import SwiftUI

struct LaunchLoadingView: View {
    @State private var ring1Scale: CGFloat = 0.4
    @State private var ring2Scale: CGFloat = 0.4
    @State private var ring3Scale: CGFloat = 0.4
    @State private var ring1Opacity: Double = 0
    @State private var ring2Opacity: Double = 0
    @State private var ring3Opacity: Double = 0
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var statusOpacity: Double = 0

    var body: some View {
        ZStack {
            // Background — deep navy radial, matching signalscope.site
            RadialGradient(
                colors: [
                    Color(hex: "12376F"),
                    Color(hex: "04112A"),
                    Color(hex: "03080F"),
                ],
                center: .top,
                startRadius: 0,
                endRadius: 600
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Signal pulse rings + icon ──────────────────────────────
                ZStack {
                    // Ring 3 (outermost)
                    Circle()
                        .stroke(Theme.brandBlue.opacity(0.12), lineWidth: 1)
                        .frame(width: 200, height: 200)
                        .scaleEffect(ring3Scale)
                        .opacity(ring3Opacity)

                    // Ring 2
                    Circle()
                        .stroke(Theme.brandBlue.opacity(0.22), lineWidth: 1)
                        .frame(width: 200, height: 200)
                        .scaleEffect(ring2Scale)
                        .opacity(ring2Opacity)

                    // Ring 1 (innermost)
                    Circle()
                        .stroke(Theme.brandBlue.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 200, height: 200)
                        .scaleEffect(ring1Scale)
                        .opacity(ring1Opacity)

                    // Icon circle
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "1A4A8A"), Color(hex: "0D2346")],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .frame(width: 88, height: 88)
                        .overlay(
                            Circle()
                                .stroke(Theme.brandBlue.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Theme.brandBlue.opacity(0.3), radius: 20, x: 0, y: 0)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(Theme.brandBlue)
                        .shadow(color: Theme.brandBlue.opacity(0.6), radius: 8, x: 0, y: 0)
                }
                .opacity(iconOpacity)
                .padding(.bottom, 36)

                // ── App name ───────────────────────────────────────────────
                VStack(spacing: 6) {
                    Text("SIGNALSCOPE")
                        .font(.system(size: 30, weight: .bold, design: .default))
                        .tracking(4)
                        .foregroundStyle(Theme.primaryText)

                    Text("Broadcast Signal Intelligence")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.mutedText)
                        .tracking(0.5)
                }
                .opacity(textOpacity)

                Spacer()

                // ── Bottom status ──────────────────────────────────────────
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.brandBlue.opacity(0.7))

                    Text("Connecting to hub…")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedText)
                }
                .opacity(statusOpacity)
                .padding(.bottom, 52)
            }
        }
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        // Icon + rings fade in
        withAnimation(.easeOut(duration: 0.5)) {
            iconOpacity = 1
        }

        // Ring 1 pulse
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(0.1)) {
            ring1Scale   = 1.05
            ring1Opacity = 1
        }
        withAnimation(.easeIn(duration: 1.4).repeatForever(autoreverses: false).delay(0.1)) {
            ring1Opacity = 0
        }

        // Ring 2 pulse (staggered)
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(0.45)) {
            ring2Scale   = 1.05
            ring2Opacity = 1
        }
        withAnimation(.easeIn(duration: 1.4).repeatForever(autoreverses: false).delay(0.45)) {
            ring2Opacity = 0
        }

        // Ring 3 pulse (staggered more)
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(0.8)) {
            ring3Scale   = 1.05
            ring3Opacity = 1
        }
        withAnimation(.easeIn(duration: 1.4).repeatForever(autoreverses: false).delay(0.8)) {
            ring3Opacity = 0
        }

        // Text fades in slightly after icon
        withAnimation(.easeOut(duration: 0.6).delay(0.25)) {
            textOpacity = 1
        }

        // Status fades in last
        withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
            statusOpacity = 1
        }
    }
}

#Preview {
    LaunchLoadingView()
}
