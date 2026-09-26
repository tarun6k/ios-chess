// gameScreen.ts `gameOverDialog()`: result title and message, the AI's "How I adapted" notes,
// the "Up for more?" offers and the Export PGN / Review / New game / Close actions.

import ChessCore
import ChessServices
import SwiftUI

struct GameOverDialog: View {
    @Environment(AppBoot.self) private var boot
    let result: GameResult

    var body: some View {
        GeometryReader { proxy in
            // `max-height: 85vh` — 100vh is the full screen, safe areas included
            let vh = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            DialogBackdrop {
                Dialog {
                    CapHeight(maxHeight: 0.85 * vh - 2 * Theme.Space.s4) {
                        ViewThatFits(in: .vertical) {
                            content
                            ScrollView { content }
                        }
                    }
                }
            }
        }
        // A real container: without it SwiftUI hands the identifier to every element inside,
        // overriding the title's and the buttons' own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("play-game-over")
    }

    private var content: some View {
        let controller = boot.controller
        let model = boot.playScreen
        let g = controller.game
        let r = result
        let playerWon = r.winner == controller.playerColor
        let title = controller.mode == .pvp
            ? (r.winner == nil ? "Draw" : r.winner == .white ? "White wins" : "Black wins")
            : r.winner == nil ? "Draw" : playerWon ? "You win" : "AI wins"
        let notes = controller.postGame?.notes ?? []
        let offers = controller.mode == .ai && !controller.isChallengeGame
            ? offerChallenges(boot.state.model, boot.state.progress, lastGameWon: r.winner == nil ? nil : playerWon)
            : []

        return VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Text(title)
                .textStyle(.dialogTitle(26))
                .accessibilityIdentifier("play-game-over-title")
            DialogBody(r.message)

            if !notes.isEmpty {
                SectionLabel("How I adapted").padding(.top, 6)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                        AdaptationNote(n, size: 13)
                    }
                }
                .accessibilityIdentifier("play-adaptation")
            }

            if !offers.isEmpty {
                SectionLabel("Up for more?").padding(.top, 6)
                ForEach(offers) { o in
                    Button {
                        model.acceptOffer(o, boot: boot)
                    } label: {
                        Card(style: .card, vertical: 10, horizontal: 12) {
                            Text(o.title).textStyle(.cardTitle(15))
                            Text(o.detail).textStyle(.inline(12.5, opacity: 0.8))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("play-offer-\(o.id)")
                }
            }

            WrapLayout(spacing: Theme.Space.s2, justify: .trailing) {
                Button("Export PGN") { model.exportPgn(boot: boot) }
                    .buttonStyle(.ghost)
                    .accessibilityIdentifier("play-export-pgn")
                if controller.mode != .pvp && g.history.count >= 4 {
                    Button("Review") {
                        model.showGameOver = false
                        model.reviewPly = g.history.count
                    }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("play-review")
                }
                Button("New game") { model.newGameSameSettings(boot: boot) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("play-game-over-new")
                Button("Close") { model.showGameOver = false }
                    .buttonStyle(.ghost)
                    .accessibilityIdentifier("play-game-over-close")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Space.s2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
