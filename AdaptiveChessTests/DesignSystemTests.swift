import Testing
import UIKit
@testable import AdaptiveChess
import ChessCore

@Suite("Fonts and board geometry")
@MainActor
struct DesignSystemTests {
    @Test("all four PostScript faces are registered from Info.plist")
    func fontsLoad() {
        #expect(AppFonts.missingFaces().isEmpty)
        for name in AppFonts.all {
            #expect(UIFont(name: name, size: 15) != nil, "\(name) did not load")
        }
    }

    @Test("CSS weights above 500 pick the semi-bold face")
    func weightMapping() {
        #expect(AppFonts.postScriptName(.body, weight: 400) == AppFonts.bodyRegular)
        #expect(AppFonts.postScriptName(.body, weight: 600) == AppFonts.bodySemiBold)
        #expect(AppFonts.postScriptName(.heading, weight: 500) == AppFonts.headingRegular)
        #expect(AppFonts.postScriptName(.heading, weight: 700) == AppFonts.headingSemiBold)
    }

    @Test("square size is min(62, (vw − 60) / 8) and the plate padding min(16, 2.5vw)")
    func geometry() {
        #expect(BoardGeometry.squareSize(viewportWidth: 402) == 42.75)
        #expect(BoardGeometry.squareSize(viewportWidth: 1024) == 62)
        #expect(BoardGeometry.platePadding(viewportWidth: 402) == 10.05)
        #expect(BoardGeometry.platePadding(viewportWidth: 1024) == 16)
    }

    @Test("visual rows follow the flip and map back to the same square")
    func flipRoundTrip() {
        for flipped in [false, true] {
            for square in 0..<64 {
                let v = BoardGeometry.visual(ofSquare: square, flipped: flipped)
                #expect(BoardGeometry.square(atVisual: v, flipped: flipped) == square)
            }
        }
        #expect(BoardGeometry.visual(ofSquare: parseSquare("a8")!, flipped: false) == 0)
        #expect(BoardGeometry.visual(ofSquare: parseSquare("a8")!, flipped: true) == 63)
        #expect(BoardGeometry.visual(ofSquare: parseSquare("h1")!, flipped: false) == 63)
        #expect(BoardGeometry.square(at: CGPoint(x: 10, y: 10), in: CGSize(width: 344, height: 344), flipped: false) == parseSquare("a8")!)
        #expect(BoardGeometry.square(at: CGPoint(x: 350, y: 10), in: CGSize(width: 344, height: 344), flipped: false) == -1)
    }

    @Test("VoiceOver names read like boardView.ts")
    func humanNames() {
        #expect(BoardGeometry.humanName(parseSquare("e4")!, piece: .empty) == "e4")
        #expect(BoardGeometry.humanName(parseSquare("e2")!, piece: Piece(type: .pawn, color: .white)) == "e2, white pawn")
        #expect(BoardGeometry.humanName(parseSquare("g8")!, piece: Piece(type: .knight, color: .black)) == "g8, black knight")
    }

    @Test("piece glyphs carry the text variation selector, never the emoji one")
    func glyphs() {
        #expect(PieceGlyphs.text(.king) == "♚\u{FE0E}")
        #expect(PieceGlyphs.text(.pawn).unicodeScalars.contains("\u{FE0E}"))
        #expect(!PieceGlyphs.text(.queen).unicodeScalars.contains("\u{FE0F}"))
    }
}
