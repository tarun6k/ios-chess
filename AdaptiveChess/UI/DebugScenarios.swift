#if DEBUG
// `--scenario <name>` reproduces the app states of .porting/tools/capture.mjs (the reference
// screenshots of the TS app) so the simulator can be screenshotted in the same states.
// Debug builds only; the app ignores the argument otherwise.

import ChessCore
import ChessServices
import Foundation

enum DebugScenario {
    static let launchArgument = "--scenario"

    static var launchScenario: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: launchArgument) else { return nil }
        let next = args.index(after: i)
        return next < args.endIndex ? args[next] : nil
    }

    /// `--reset-state`: forget everything the app has stored before booting, so a UI test can start
    /// from the very first launch (the login screen) on a simulator that has been used before.
    static let resetArgument = "--reset-state"

    static func resetStoredStateIfRequested(_ storage: Storage) {
        guard ProcessInfo.processInfo.arguments.contains(resetArgument) else { return }
        for key in StoreKey.allCases {
            storage.remove(forKey: key.rawValue)
        }
    }

    /// Runs the named scenario against the live app; unknown names do nothing.
    @MainActor
    static func run(_ name: String, boot: AppBoot) async {
        let controller = boot.controller
        let model = boot.playScreen

        func guest() {
            if (boot.state.playerName ?? "").isEmpty && !boot.state.guest {
                boot.state.guest = true
                boot.state.persist(.guest)
            }
        }
        func tap(_ square: String) async {
            let files = Array("abcdefgh")
            let chars = Array(square)
            guard chars.count == 2, let f = files.firstIndex(of: chars[0]), let r = Int(String(chars[1])) else { return }
            model.tapSquare((r - 1) * 8 + f, controller: controller, settings: boot.state.settings)
            try? await Task.sleep(for: .milliseconds(250))
        }
        /// capture.mjs `go()` waits 250 ms after switching routes so the screen has rendered
        /// (the play screen syncs its local state with the controller on its first render).
        func go(_ route: Route) async {
            boot.navigate(route)
            try? await Task.sleep(for: .milliseconds(250))
        }
        func newGame(_ opts: NewGameOptions) async {
            boot.startGame(opts)
            await go(.home)
            await go(.play)
        }

        guest()
        switch name {
        case "home":
            await go(.home)
        case "play-start":
            await go(.play)
        case "play-selected":
            await go(.play)
            await tap("e2")
        case "play-promotion":
            await newGame(NewGameOptions(mode: .pvp, startFen: "4k3/6P1/8/8/8/8/8/4K3 w - - 0 1"))
            await tap("g7")
            await tap("g8")
        case "gameover-pvp", "finished-pvp":
            await newGame(NewGameOptions(mode: .pvp, startFen: "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1"))
            await tap("a1")
            await tap("a8")
            if name == "finished-pvp" {
                try? await Task.sleep(for: .milliseconds(600))
                model.showGameOver = false
            }
        case "gameover-ai":
            await newGame(NewGameOptions(mode: .ai, playerColor: .white))
            await tap("e2")
            await tap("e4")
            try? await Task.sleep(for: .milliseconds(2500)) // let the AI reply
            controller.resign()
        case "puzzles":
            await go(.puzzles)
        case "insights":
            await go(.stats)
        case "settings":
            await go(.settings)
        case "home-continue":
            await newGame(NewGameOptions(mode: .ai, playerColor: .white))
            await tap("d2")
            await tap("d4")
            try? await Task.sleep(for: .milliseconds(2500))
            await go(.home)
        default:
            break
        }
    }
}
#endif
