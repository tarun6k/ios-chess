// src/ui/router.ts: the screen switch and the fixed bottom navigation (hidden on login). The
// game screen's dialogs (`position: fixed; inset: 0`) are layered above the nav here, at the
// root, so they cover the whole viewport like the TS backdrops.

import SwiftUI

struct RootView: View {
    let boot: AppBoot

    var body: some View {
        #if DEBUG
        if let page = BoardGallery.launchPage {
            BoardGallery(initialPage: page)
        } else {
            shell
        }
        #else
        shell
        #endif
    }

    private var shell: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if boot.route != .login {
                nav
            }
            if boot.route == .play {
                GameScreenOverlays()
            }
        }
        .font(AppFonts.body(15))
        .foregroundStyle(Theme.text)
        .environment(boot)
        #if DEBUG
        .task {
            if let scenario = DebugScenario.launchScenario {
                await DebugScenario.run(scenario, boot: boot)
            }
        }
        #endif
    }

    @ViewBuilder private var screen: some View {
        switch boot.route {
        case .login: LoginScreen()
        case .home: HomeScreen()
        case .play: GameScreen()
        case .puzzles: PuzzlesScreen()
        case .stats: InsightsScreen()
        case .settings: SettingsScreen()
        }
    }

    private var nav: some View {
        BottomNavBar {
            ForEach(NavItem.all) { item in
                BottomNavItem(icon: item.icon, label: item.label, active: boot.route == item.route) {
                    boot.navigate(item.route)
                }
                .accessibilityIdentifier("nav-\(item.route.rawValue)")
            }
        }
    }
}
