// The per-screen state and input handling of src/ui/gameScreen.ts (the fields of the
// `GameScreen` class plus tapSquare / tryMove / commitCandidates / finishMove). main.ts keeps
// one GameScreen for the app's lifetime, so this object lives on AppBoot.

import ChessCore
import ChessServices
import SwiftUI

/// `pendingPromo: { from, to, moves }` — the four promotion moves awaiting a piece choice.
struct PendingPromotion: Hashable {
    let from: Int
    let to: Int
    let moves: [Move]
}

@Observable @MainActor
final class GameScreenModel {
    var selected: Int? = nil
    var targets: [Move] = []
    var pendingPromo: PendingPromotion? = nil
    /// nil = live; a ply = review mode
    var reviewPly: Int? = nil
    var showGameOver = false
    var gameOverShownFor: String? = nil
    var drawNote = ""
    private var seenGameId = -1

    var reviewing: Bool { reviewPly != nil }

    /// The `controller.subscribe` callback + the start of `render()`: surface the game-over sheet
    /// once per game, then drop stale local state when a different game was loaded (e.g. from Home).
    func sync(with controller: GameController) {
        if controller.game.status == .finished && controller.gameOverHandled {
            let key = controller.game.uciLine().joined(separator: " ")
            if gameOverShownFor != key && reviewPly == nil {
                gameOverShownFor = key
                showGameOver = true
            }
        }
        if controller.gameId != seenGameId {
            seenGameId = controller.gameId
            resetLocal()
        }
    }

    func resetLocal() {
        selected = nil
        targets = []
        pendingPromo = nil
        reviewPly = nil
        showGameOver = false
        gameOverShownFor = nil
        drawNote = ""
    }

    // MARK: input

    func tapSquare(_ sq: Int, controller: GameController, settings: Settings) {
        if reviewPly != nil { return }
        if !controller.humanTurn || pendingPromo != nil { return }
        let g = controller.game
        if let m = targets.first(where: { $0.to == sq }) {
            commitMove(m, controller: controller, settings: settings)
            return
        }
        let p = g.position.board[sq]
        if !p.isEmpty && p.color == g.turn && sq != selected {
            selected = sq
            targets = controller.legalTargetsFrom(sq).filter { controller.moveAllowedByConstraint($0) }
            if !controller.legalTargetsFrom(sq).isEmpty && targets.isEmpty {
                drawNote = "Challenge rule: your queen must not move."
            }
        } else {
            selected = nil
            targets = []
        }
    }

    func tryMove(from: Int, to: Int, controller: GameController, settings: Settings) {
        if reviewPly != nil || !controller.humanTurn || pendingPromo != nil { return }
        let moves = controller.legalTargetsFrom(from).filter { controller.moveAllowedByConstraint($0) }
        let candidates = moves.filter { $0.to == to }
        if candidates.isEmpty {
            selected = nil
            targets = []
            return
        }
        commitCandidates(candidates, controller: controller, settings: settings)
    }

    private func commitMove(_ m: Move, controller: GameController, settings: Settings) {
        let all = targets.filter { $0.from == m.from && $0.to == m.to }
        commitCandidates(all.isEmpty ? [m] : all, controller: controller, settings: settings)
    }

    private func commitCandidates(_ candidates: [Move], controller: GameController, settings: Settings) {
        if candidates.count > 1 && candidates[0].promotion != .empty {
            if settings.autoQueen {
                let q = candidates.first { $0.promotion == .queen } ?? candidates[0]
                finishMove(q, controller: controller)
            } else {
                pendingPromo = PendingPromotion(from: candidates[0].from, to: candidates[0].to, moves: candidates)
            }
            return
        }
        finishMove(candidates[0], controller: controller)
    }

    func finishMove(_ m: Move, controller: GameController) {
        selected = nil
        targets = []
        pendingPromo = nil
        drawNote = ""
        let g = controller.game
        let san = g.status == .active ? previewSan(m, controller: controller) : ""
        if controller.playMove(m) {
            BoardView.announce(san)
        }
    }

    /// Spoken form for accessibility, e.g. "Knight f3".
    private func previewSan(_ m: Move, controller: GameController) -> String {
        let pos = controller.game.position
        let t = pos.board[m.from].type
        let names = ["", "Pawn", "Knight", "Bishop", "Rook", "Queen", "King"]
        return "\(names[t.rawValue]) \(squareName(m.to))"
    }
}

// MARK: - actions shared by the side panel and the game-over sheet

extension GameScreenModel {
    /// Mode segment: a new game in the other mode, keeping the timer if it was on.
    func switchMode(_ mode: GameMode, boot: AppBoot) {
        let controller = boot.controller
        if controller.mode == mode { return }
        resetLocal()
        boot.startGame(NewGameOptions(
            mode: mode, playerColor: .white,
            timeControl: controller.timerOn ? (controller.timeControl ?? timePresets[2]) : nil
        ))
    }

    /// AI level segment: persists the pick and restarts against the AI at that level.
    func setDifficulty(_ d: DifficultyMode, boot: AppBoot) {
        let controller = boot.controller
        boot.state.difficulty = d
        boot.state.persist(.difficulty)
        resetLocal()
        boot.startGame(NewGameOptions(
            mode: .ai, playerColor: controller.playerColor, difficulty: d,
            timeControl: controller.timerOn ? controller.timeControl : nil
        ))
    }

    func setTimer(_ on: Bool, boot: AppBoot) {
        let controller = boot.controller
        if controller.game.history.count > 0 && controller.game.status == .active {
            // per the design, the toggle restarts with the new setting
            resetLocal()
            boot.startGame(NewGameOptions(
                mode: controller.mode, playerColor: controller.playerColor,
                timeControl: on ? (controller.timeControl ?? timePresets[2]) : nil
            ))
            return
        }
        if on && controller.timeControl == nil {
            resetLocal()
            boot.startGame(NewGameOptions(mode: controller.mode, playerColor: controller.playerColor, timeControl: timePresets[2]))
        } else if !on {
            controller.setTimerOn(false)
        }
    }

    func pickPreset(_ tc: TimeControl, boot: AppBoot) {
        let controller = boot.controller
        resetLocal()
        boot.startGame(NewGameOptions(mode: controller.mode, playerColor: controller.playerColor, timeControl: tc))
    }

    func newGameSameSettings(boot: AppBoot) {
        let controller = boot.controller
        resetLocal()
        if controller.isChallengeGame {
            controller.retryPuzzle()
            return
        }
        boot.startGame(NewGameOptions(
            mode: controller.mode == .pvp ? .pvp : .ai,
            playerColor: controller.playerColor,
            timeControl: controller.timerOn ? controller.timeControl : nil
        ))
    }

    /// One of the post-game "Up for more?" cards.
    func acceptOffer(_ offer: OfferedChallenge, boot: AppBoot) {
        let controller = boot.controller
        resetLocal()
        switch offer.kind {
        case .rematchBlitz:
            boot.startGame(NewGameOptions(mode: .ai, playerColor: controller.playerColor, timeControl: timePresets[1]))
        case .drill:
            if let id = offer.drillId, let d = drills.first(where: { $0.id == id }) {
                boot.startGame(NewGameOptions(mode: .drill, challenge: ChallengeContext(drill: d)))
            }
        case .constraint:
            if let id = offer.constraintId, let c = constraints.first(where: { $0.id == id }) {
                boot.startGame(NewGameOptions(mode: .constraint, challenge: ChallengeContext(constraint: c)))
            }
        case .puzzleSet:
            if let first = offer.puzzleIds?.first, let p = puzzles.first(where: { $0.id == first }) {
                boot.startGame(NewGameOptions(mode: .puzzle, challenge: ChallengeContext(puzzle: p)))
            }
        }
    }

    /// "Export PGN": the archived game's PGN (or the live game's) goes to the clipboard.
    func exportPgn(boot: AppBoot) {
        let pgn = boot.state.archive.first?.pgn ?? toPGN(boot.controller.game)
        UIPasteboard.general.string = pgn
        drawNote = "PGN copied to clipboard."
    }
}
