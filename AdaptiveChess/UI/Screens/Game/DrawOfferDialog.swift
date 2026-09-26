// gameScreen.ts `pvpDrawDialog()`: in pass-and-play the other side is asked to accept or
// decline a draw offer.

import ChessCore
import ChessServices
import SwiftUI

struct DrawOfferDialog: View {
    @Environment(AppBoot.self) private var boot
    /// `g.drawOffer` — the side that offered
    let offerer: PieceColor

    var body: some View {
        let offererName = offerer == .white ? "White" : "Black"
        let otherName = offerer == .white ? "Black" : "White"
        DialogBackdrop {
            Dialog {
                DialogTitle("Draw offer")
                DialogBody("\(offererName) offers a draw. Does \(otherName) accept?")
                DialogActions {
                    Button("Decline") { boot.controller.declineDraw() }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("play-draw-decline")
                    Button("Accept") { boot.controller.acceptDraw() }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("play-draw-accept")
                }
            }
        }
        .accessibilityIdentifier("play-draw-offer")
    }
}
