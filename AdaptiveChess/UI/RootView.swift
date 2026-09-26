import SwiftUI

/// Placeholder root for the Phase 0 scaffold. Phase 8 replaces it with the tab shell.
struct RootView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text("Chess")
                .font(.system(size: 44, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.text)
        }
    }
}

#Preview {
    RootView()
}
