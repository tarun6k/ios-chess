// gameScreen.ts `promoDialog`: a backdrop over the whole screen with a "Promote to" card and the
// four 64×64 piece buttons (queen, rook, bishop, knight) in the mover's piece style.

import ChessCore
import SwiftUI

struct PromotionDialog: View {
    /// the side promoting (`g.turn`)
    let color: PieceColor
    /// `pendingPromo.moves` — the four promotion moves to the same square
    let moves: [Move]
    let onChoose: (Move) -> Void

    private static let choices: [PieceType] = [.queen, .rook, .bishop, .knight]

    var body: some View {
        DialogBackdrop(background: Color(r: 32, g: 31, b: 29, a: 0.4)) {
            Dialog(gap: 16, vertical: 28, horizontal: 32, radius: Theme.Radius.md, background: Theme.background, alignment: .center) {
                Text("Promote to").textStyle(.promotionTitle)
                HStack(spacing: 10) {
                    ForEach(Self.choices, id: \.rawValue) { type in
                        if let move = moves.first(where: { $0.promotion == type }) {
                            Button {
                                onChoose(move)
                            } label: {
                                PieceGlyph(type: type, color: color, fontSize: 40)
                                    .frame(width: 64, height: 64)
                                    .background(Color(hex: 0xEEDDBE), in: RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent, lineWidth: 1))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(PieceGlyphs.name(type))
                        }
                    }
                }
            }
        }
    }
}
