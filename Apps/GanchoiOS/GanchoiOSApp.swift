import GanchoDesign
import GanchoKit
import SwiftUI

/// iOS companion shell (pre-alpha). The real app (E7.1) is the synced history
/// viewer with honest intent-based capture; this shell exists so the target
/// builds and the package graph is proven on iOS from day one.
@main
struct GanchoiOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: GanchoTokens.Spacing.md) {
                Image(systemName: "paperclip")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Gancho")
                    .font(.title2.bold())
                Text("Your clipboard, everywhere. Pre-alpha shell — capture lands with E2.1/E2.2.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, GanchoTokens.Spacing.xl)
            }
            .navigationTitle("Gancho")
        }
    }
}
