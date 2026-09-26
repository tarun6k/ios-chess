import SwiftUI

/// Placeholder root for the Phase 0 scaffold. Phase 8 replaces it with the tab shell.
struct RootView: View {
    var body: some View {
        #if DEBUG
        if let page = BoardGallery.launchPage {
            BoardGallery(initialPage: page)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text("Chess")
                .font(AppFonts.heading(44, weight: 400))
                .foregroundStyle(Theme.text)
        }
    }
}

#Preview {
    RootView()
}
