import ChessCore
import ChessServices
import SwiftUI

@main
struct AdaptiveChessApp: App {
    @State private var boot: AppBoot
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFonts.verifyInstalled()
        _boot = State(initialValue: AppBoot())
    }

    var body: some Scene {
        WindowGroup {
            RootView(boot: boot)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: boot.didEnterBackground()
                    case .active: boot.didBecomeActive()
                    case .inactive: break
                    @unknown default: break
                    }
                }
        }
    }
}
