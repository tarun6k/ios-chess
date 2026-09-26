// src/ui/gameScreen.ts `render()`, `isFlipped()`, `header()` / `statusLine()` and the dialog
// slots: the board plus side panel under the "Chess" header, and the three overlays (promotion,
// game over, pass-and-play draw offer) that main.ts stacks over everything, nav included.

import ChessCore
import ChessServices
import SwiftUI

/// `JUDGMENT_MARK` / `JUDGMENT_COLOR` — the marks after annotated moves.
enum JudgmentStyle {
    static func mark(_ j: Judgment) -> String {
        switch j {
        case .best: return "★"
        case .good: return ""
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .blunder: return "??"
        }
    }

    /// `JUDGMENT_COLOR[j]`; nil for `good` (the TS empty string falls back to the caller's colour).
    static func color(_ j: Judgment) -> Color? {
        switch j {
        case .best: return Theme.accent700
        case .good: return nil
        case .inaccuracy: return Theme.accent600
        case .mistake: return Color(hex: 0xA3541F)
        case .blunder: return Color(hex: 0x8A2C1C)
        }
    }
}

struct GameScreen: View {
    @Environment(AppBoot.self) private var boot

    var body: some View {
        let controller = boot.controller
        let model = boot.playScreen
        let g = controller.game
        let reviewing = model.reviewing
        let pos = reviewing ? g.positionAt(model.reviewPly ?? 0) : g.position
        ScreenPage { vw in
            PageHeader(title: "Chess", titleStyle: .gameTitle, status: statusLine(pos: pos, reviewing: reviewing))
                .accessibilityIdentifier("play-status")
            WrapLayout(spacing: cssClamp(20, 0.04 * vw, 40), justify: .center) {
                BoardView(
                    state: boardState(pos: pos, reviewing: reviewing),
                    viewportWidth: vw,
                    onSquareTap: { sq in model.tapSquare(sq, controller: controller, settings: boot.state.settings) },
                    onDrop: { from, to in model.tryMove(from: from, to: to, controller: controller, settings: boot.state.settings) }
                )
                SidePanel(reviewing: reviewing)
                    .frame(width: min(300, vw - 24))
            }
            .padding(.top, cssClamp(16, 0.03 * vw, 28))
        }
        .onChange(of: controller.revision, initial: true) { _, _ in
            model.sync(with: controller)
        }
    }

    /// The `this.board.render({...})` arguments.
    private func boardState(pos: Position, reviewing: Bool) -> BoardState {
        let controller = boot.controller
        let model = boot.playScreen
        let g = controller.game
        let lastEntry: HistoryEntry?
        if reviewing {
            let ply = model.reviewPly ?? 0
            lastEntry = ply > 0 ? g.history[ply - 1] : nil
        } else {
            lastEntry = g.history.last
        }
        return BoardState(
            position: pos,
            selected: reviewing ? nil : model.selected,
            targets: reviewing ? [] : model.targets,
            lastMove: lastEntry.map { ($0.move.from, $0.move.to) },
            checkSquare: pos.isInCheck() ? pos.kingSquare(pos.turn) : nil,
            flipped: isFlipped,
            coordinates: boot.state.settings.coordinates,
            hintMove: reviewing ? nil : controller.hintMove,
            interactive: !reviewing && controller.humanTurn && model.pendingPromo == nil && !model.showGameOver
        )
    }

    private var isFlipped: Bool {
        let controller = boot.controller
        switch boot.state.settings.boardFlip {
        case .white: return false
        case .black: return true
        case .auto:
            if controller.mode == .pvp { return controller.game.turn == .black }
            return controller.playerColor == .black
        }
    }

    private func statusLine(pos: Position, reviewing: Bool) -> String {
        let controller = boot.controller
        let g = controller.game
        if reviewing {
            let ply = boot.playScreen.reviewPly ?? 0
            return "Review · move \(Int((Double(ply) / 2).rounded(.up))) of \(Int((Double(g.history.count) / 2).rounded(.up)))"
        }
        if controller.puzzleState == .solved { return "Solved! Well done." }
        if controller.puzzleState == .wrong { return "Not quite — try again" }
        if let r = g.result { return r.message }
        let check = g.isInCheck() ? "Check · " : ""
        if controller.thinking { return check + "Computer is thinking…" }
        return check + (g.turn == .white ? "White" : "Black") + " to move"
    }
}

/// The dialogs of `render()`'s `parts` after the page: promotion (z 50), the pass-and-play draw
/// offer (z 55) and the game-over sheet (z 60). RootView mounts this above the nav so the
/// backdrops cover the whole viewport like the TS `position: fixed; inset: 0`.
struct GameScreenOverlays: View {
    @Environment(AppBoot.self) private var boot

    var body: some View {
        let controller = boot.controller
        let model = boot.playScreen
        let g = controller.game
        ZStack {
            if let promo = model.pendingPromo {
                PromotionDialog(color: g.turn, moves: promo.moves) { m in
                    model.finishMove(m, controller: controller)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("play-promotion")
            }
            if controller.mode == .pvp, let offerer = g.drawOffer, g.status == .active {
                DrawOfferDialog(offerer: offerer)
            }
            if model.showGameOver, let result = g.result {
                GameOverDialog(result: result)
            }
        }
    }
}
