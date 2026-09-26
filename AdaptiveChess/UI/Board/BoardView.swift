// src/ui/boardView.ts: the chessboard rendered exactly per the design — wood plate, textured
// squares, glyph pieces with engraved outlines, dot/ring move targets — plus drag & drop, check
// highlight, coordinates, board flipping and VoiceOver announcements.

import ChessCore
import SwiftUI
import UIKit

/// `BoardState`
struct BoardState {
    var position: Position
    var selected: Int?
    var targets: [Move] = []
    var lastMove: (from: Int, to: Int)?
    var checkSquare: Int?
    var flipped = false
    var coordinates = true
    var hintMove: Move?
    var interactive = true
}

/// Visual ↔ board square mapping and the pointer → square hit test of boardView.ts.
enum BoardGeometry {
    /// gameScreen.ts `--sq: min(62px, calc((100vw - 60px) / 8))`
    static func squareSize(viewportWidth: CGFloat) -> CGFloat {
        min(62, (viewportWidth - 60) / 8)
    }

    /// boardView.ts plate `padding: min(16px, 2.5vw)`
    static func platePadding(viewportWidth: CGFloat) -> CGFloat {
        min(16, viewportWidth * 0.025)
    }

    /// `vToSq`: visual index (0..63, top-left first) → board square
    static func square(atVisual v: Int, flipped: Bool) -> Int {
        let r = v / 8, c = v % 8
        return flipped ? r * 8 + (7 - c) : (7 - r) * 8 + c
    }

    /// `sqToV`: board square → visual index
    static func visual(ofSquare sq: Int, flipped: Bool) -> Int {
        let rank = rankOf(sq), file = fileOf(sq)
        return flipped ? rank * 8 + (7 - file) : (7 - rank) * 8 + file
    }

    /// `squareAt`: a point in the grid's bounding box (border included) → square, or −1 outside.
    static func square(at point: CGPoint, in size: CGSize, flipped: Bool) -> Int {
        let c = Int((point.x / size.width * 8).rounded(.down))
        let r = Int((point.y / size.height * 8).rounded(.down))
        if c < 0 || c > 7 || r < 0 || r > 7 { return -1 }
        return square(atVisual: r * 8 + c, flipped: flipped)
    }

    /// `sqNameHuman`: "e4", or "e2, white pawn".
    static func humanName(_ sq: Int, piece: Piece) -> String {
        let name = squareName(sq)
        if piece.isEmpty { return name }
        return "\(name), \(piece.color == .white ? "white" : "black") \(PieceGlyphs.name(piece.type))"
    }
}

/// `BoardView`: the plate, the 8×8 grid, and the tap / drag-and-drop input, sized from the
/// viewport width like the CSS custom property.
struct BoardView: View {
    let state: BoardState
    let viewportWidth: CGFloat
    let onSquareTap: (Int) -> Void
    let onDrop: (_ from: Int, _ to: Int) -> Void

    @State private var drag = BoardDragState()

    /// `announce`: the polite live region → a VoiceOver announcement.
    static func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private var squareSize: CGFloat { BoardGeometry.squareSize(viewportWidth: viewportWidth) }

    var body: some View {
        let sq = squareSize
        let gridSide = 8 * sq
        grid(squareSize: sq)
            .frame(width: gridSide, height: gridSide)
            .padding(1)
            .background(Color(r: 60, g: 40, b: 16, a: 0.5)) // border: 1px solid rgba(60,40,16,0.5)
            // The gesture must stop at the border: the texture below overflows the grid by
            // another eight squares and SwiftUI's `.clipped()` clips only the drawing, not hit
            // testing, so without this a drag on a blank spot up to 8 squares under the board
            // (the cards have no fill) would lift a piece instead of scrolling the page.
            .contentShape(Rectangle())
            .boardGestures(
                state: state,
                size: CGSize(width: gridSide + 2, height: gridSide + 2),
                drag: $drag,
                onSquareTap: onSquareTap,
                onDrop: onDrop
            )
            .overlay(alignment: .topLeading) { ghost(squareSize: sq) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Chessboard")
            .padding(BoardGeometry.platePadding(viewportWidth: viewportWidth))
            .background { plate }
            .compositingGroup() // shadow the plate as one box, not every square and glyph
            .themeShadow(.md)
            .onChange(of: state.interactive) { _, interactive in
                if !interactive { drag = BoardDragState() }
            }
    }

    /// `linear-gradient(rgba(30,18,6,0.30), rgba(30,18,6,0.38)), url(wood.jpg) center / 700px auto`
    /// with `border-radius: 6px`.
    private var plate: some View {
        Rectangle()
            .fill(.clear)
            .overlay {
                Image(decorative: "wood")
                    .resizable()
                    .frame(width: 700, height: 1400)
            }
            .overlay {
                LinearGradient(
                    colors: [Color(r: 30, g: 18, b: 6, a: 0.30), Color(r: 30, g: 18, b: 6, a: 0.38)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .allowsHitTesting(false) // decoration only; its overflow must not catch touches
    }

    /// The wood texture once across the whole grid (`8 × --sq` wide, positioned at
    /// `−c·sq, −r·sq` per square, so every square shows its own patch) under the 64 squares.
    private func grid(squareSize sq: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: "wood")
                .resizable()
                .frame(width: 8 * sq, height: 16 * sq)
                .frame(width: 8 * sq, height: 8 * sq, alignment: .topLeading)
                .clipped()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { c in
                            square(visualRow: r, visualCol: c, squareSize: sq)
                        }
                    }
                }
            }
        }
    }

    private func square(visualRow r: Int, visualCol c: Int, squareSize sq: CGFloat) -> some View {
        let square = BoardGeometry.square(atVisual: r * 8 + c, flipped: state.flipped)
        let piece = state.position.board[square]
        let target = state.targets.first { $0.to == square }
        let isLight = (rankOf(square) + fileOf(square)) % 2 == 1
        let isSelected = state.selected == square
        let isLast = state.lastMove.map { $0.from == square || $0.to == square } ?? false
        let isCheck = state.checkSquare == square
        let isHint = state.hintMove.map { $0.from == square || $0.to == square } ?? false
        let highlight: Color? = isSelected ? Theme.accent
            : isHint ? Theme.accent300
            : isCheck ? Color(r: 146, g: 44, b: 28, a: 0.75)
            : isLast ? Color(r: 182, g: 130, b: 53, a: 0.45)
            : nil
        let canTouch = state.interactive && (target != nil || (!piece.isEmpty && piece.color == state.position.turn))
        return SquareView(
            square: square,
            visualRow: r,
            visualCol: c,
            squareSize: sq,
            isLight: isLight,
            piece: piece,
            pieceDimmed: drag.from == square && drag.hasGhost,
            highlight: highlight,
            target: target.map { _ in piece.isEmpty ? .dot : .ring },
            coordinates: state.coordinates,
            canTouch: canTouch
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoardGeometry.humanName(square, piece: piece))
        .accessibilityAddTraits(canTouch ? [.isButton] : [])
        .modifier(SquareActivation(enabled: state.interactive) { onSquareTap(square) })
    }

    /// The lifted piece: `font-size: 0.9 × --sq`, `translate(-50%, -60%)` of its line box.
    @ViewBuilder
    private func ghost(squareSize sq: CGFloat) -> some View {
        if drag.hasGhost, let location = drag.location, drag.from >= 0 {
            let piece = state.position.board[drag.from]
            if !piece.isEmpty {
                let size = 0.9 * sq
                PieceGlyph(type: piece.type, color: piece.color, fontSize: size)
                    .position(x: location.x, y: location.y - 0.1 * size)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// VoiceOver activation of a square: the pointerdown that a double-tap on the gridcell
/// produces in the TS app, only while the board is interactive.
private struct SquareActivation: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(.default, action)
        } else {
            content
        }
    }
}
