// One gridcell of boardView.ts `render`: overlay-tinted texture, inset highlight, target dot or
// capture ring, coordinates and the piece glyph, in that paint order.

import ChessCore
import SwiftUI

struct SquareView: View {
    enum Target {
        /// quiet move: a centred dot, 0.3 × --sq, rgba(112,78,36,0.45)
        case dot
        /// capture: a ring inset 3px with a 3px rgba(112,78,36,0.55) border
        case ring
    }

    let square: Int
    let visualRow: Int
    let visualCol: Int
    let squareSize: CGFloat
    let isLight: Bool
    let piece: Piece
    let pieceDimmed: Bool
    let highlight: Color?
    let target: Target?
    let coordinates: Bool
    let canTouch: Bool

    private static let targetColor = Color(r: 112, g: 78, b: 36, a: 0.45)
    private static let ringColor = Color(r: 112, g: 78, b: 36, a: 0.55)

    var body: some View {
        let sq = squareSize
        ZStack {
            // sqBg: the light/dark overlay gradient over the shared texture
            LinearGradient(colors: overlay, startPoint: .top, endPoint: .bottom)
            // box-shadow: inset 0 0 0 3px
            if let highlight {
                Rectangle().strokeBorder(highlight, lineWidth: 3)
            }
            switch target {
            case .ring:
                Circle()
                    .strokeBorder(Self.ringColor, lineWidth: 3)
                    .padding(3)
            case .dot:
                Circle()
                    .fill(Self.targetColor)
                    .frame(width: 0.3 * sq, height: 0.3 * sq)
            case nil:
                EmptyView()
            }
            if coordinates {
                coordinateLabels
            }
            if !piece.isEmpty {
                PieceGlyph(type: piece.type, color: piece.color, fontSize: 0.74 * sq)
                    .opacity(pieceDimmed ? 0.25 : 1)
            }
        }
        .frame(width: sq, height: sq)
        .contentShape(Rectangle())
    }

    private var overlay: [Color] {
        isLight
            ? [Color(r: 247, g: 233, b: 206, a: 0.80), Color(r: 241, g: 224, b: 190, a: 0.80)]
            : [Color(r: 214, g: 174, b: 123, a: 0.28), Color(r: 46, g: 28, b: 10, a: 0.18)]
    }

    /// File letters along the bottom visual row (right 3, bottom 2), rank digits down the
    /// left visual column (left 3, top 2); 0.18 × --sq in the body font at 75% opacity.
    private var coordinateLabels: some View {
        let style = TextStyle(
            family: .body, weight: 400, size: 0.18 * squareSize,
            color: isLight ? Color(hex: 0x7A5A30) : Color(hex: 0xF0E2C4)
        )
        return ZStack {
            if visualRow == 7 {
                Text(String("abcdefgh"[fileOf(square)]))
                    .textStyle(style)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 3)
                    .padding(.bottom, 2)
            }
            if visualCol == 0 {
                Text(String(rankOf(square) + 1))
                    .textStyle(style)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 3)
                    .padding(.top, 2)
            }
        }
        .opacity(0.75)
        .accessibilityHidden(true)
    }
}

private extension String {
    subscript(index: Int) -> Character {
        self[self.index(startIndex, offsetBy: index)]
    }
}
