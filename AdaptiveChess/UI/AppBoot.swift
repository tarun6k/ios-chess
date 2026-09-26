// src/main.ts and the app-wide state of src/ui/router.ts: the boot sequence (load the store,
// run the Capacitor Preferences migration, pick login or home, resume the autosaved game or
// start one vs the AI as White), the current route and the single GameController every screen
// shares. Lifecycle handling (pause + autosave on background, resume on foreground) has no TS
// counterpart — the web app simply kept its timers running.

import ChessCore
import ChessServices
import OSLog
import SwiftUI

/// router.ts `ScreenName`.
enum Route: String, CaseIterable, Sendable {
    case login, home, play, puzzles, stats, settings
}

/// router.ts `NAV_ITEMS`.
struct NavItem: Identifiable {
    let route: Route
    let label: String
    let icon: String
    var id: Route { route }

    static let all: [NavItem] = [
        NavItem(route: .home, label: "Home", icon: "⌂"),
        NavItem(route: .play, label: "Play", icon: "♞"),
        NavItem(route: .puzzles, label: "Puzzles", icon: "✦"),
        NavItem(route: .stats, label: "Insights", icon: "◔"),
        NavItem(route: .settings, label: "Settings", icon: "⚙"),
    ]
}

@Observable @MainActor
final class AppBoot {
    let state: AppState
    let feedback: AppFeedback
    let controller: GameController
    /// main.ts keeps one `GameScreen` instance and only mounts/unmounts it, so the play tab's
    /// selection, review position and dialogs survive a trip through the other tabs.
    let playScreen = GameScreenModel()
    /// Likewise the home screen's new-game picks.
    let homeScreen: HomeScreenModel
    private(set) var route: Route

    /// The clock was running when the scene left the foreground.
    private var clockWasRunning = false

    private static let log = Logger(subsystem: "com.adaptivechess.app", category: "boot")

    init() {
        let storage: Storage
        do {
            storage = try Storage.live()
        } catch {
            Self.log.fault("Application Support is unavailable: \(String(describing: error), privacy: .public) — persisting through UserDefaults only")
            storage = Storage(primary: UserDefaultsStore(), secondary: UserDefaultsStore())
        }
        #if DEBUG
        DebugScenario.resetStoredStateIfRequested(storage)
        #endif
        let state = AppState(storage: storage)
        let migrated = state.migrateFromCapacitor()
        if !migrated.isEmpty {
            Self.log.notice("Migrated Capacitor Preferences: \(migrated.joined(separator: ", "), privacy: .public)")
        }
        state.loadAll()
        self.state = state
        homeScreen = HomeScreenModel(difficulty: state.difficulty)
        let feedback = AppFeedback(state: state)
        self.feedback = feedback
        controller = GameController(state: state, ai: AIEngine(), feedback: feedback,
                                    timeSource: ContinuousClockTimeSource())

        // First launch: ask for a name (or guest). After that, straight to home.
        route = (state.playerName ?? "").isEmpty && !state.guest ? .login : .home

        // Resume the autosaved game if any moves were played; otherwise start a fresh game vs the AI as White.
        if let saved = state.saved, !saved.uciMoves.isEmpty {
            controller.resume(saved)
        } else {
            startGame(NewGameOptions(mode: .ai, playerColor: .white))
        }
    }

    /// router.ts `navigate()`.
    func navigate(_ route: Route) {
        self.route = route
    }

    /// `controller.newGame(opts)`. The only error is an invalid start FEN, which the built-in
    /// puzzles, drills and constraints never produce; it is logged rather than surfaced.
    func startGame(_ opts: NewGameOptions) {
        do {
            try controller.newGame(opts)
        } catch {
            Self.log.error("newGame rejected the start position: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: lifecycle

    /// Scene → background: stop the running clock and autosave with the current remaining times.
    func didEnterBackground() {
        clockWasRunning = controller.clock?.active != nil
        controller.clock?.pause()
        controller.save()
    }

    /// Scene → active: restart the clock for the side to move if it was running when we left.
    func didBecomeActive() {
        guard clockWasRunning else { return }
        clockWasRunning = false
        if controller.game.status == .active {
            controller.clock?.start(controller.game.turn)
        }
    }
}
