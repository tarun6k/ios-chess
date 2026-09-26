import ChessCore
import ChessServices
import SwiftUI

@main
struct AdaptiveChessApp: App {
    init() {
        AppFonts.verifyInstalled()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
