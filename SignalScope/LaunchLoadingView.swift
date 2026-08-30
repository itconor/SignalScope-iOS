
import SwiftUI

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Image("SignalScopeLaunch")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 28)

                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.brandBlue)

                Text("Connecting to hub…")
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    LaunchLoadingView()
}
