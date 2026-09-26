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

    @Test("italic is a 14° synthetic oblique of the upright face, as the browser renders it")
    func syntheticOblique() throws {
        let oblique = AppFonts.obliqueUIFont(.body, size: 13, weight: 400)
        let upright = try #require(AppFonts.uiFont(.body, size: 13, weight: 400))
        #expect(oblique.fontName == AppFonts.bodyRegular)
        // SwiftUI renders the CTFont, whose matrix carries the skew (`UIFont.fontDescriptor`
        // does not report it back). A pure horizontal shear: x' = x + tan 14° · y.
        let matrix = CTFontGetMatrix(oblique as CTFont)
        #expect(abs(matrix.c / matrix.a - tan(14 * CGFloat.pi / 180)) < 1e-6, "\(matrix)")
        #expect(matrix.b == 0 && abs(matrix.a - matrix.d) < 1e-6, "\(matrix)")
        // The shear reaches the outlines: the oblique glyph's path is the upright path under that
        // matrix (compared on the bounds — "l" has a foot serif, so it widens by less than its
        // height × tan 14°).
        var glyph = CGGlyph(0)
        var scalar = UniChar(("l" as Character).utf16.first!)
        #expect(CTFontGetGlyphsForCharacters(upright as CTFont, &scalar, &glyph, 1))
        let uprightPath = try #require(CTFontCreatePathForGlyph(upright as CTFont, glyph, nil))
        let obliqueBox = try #require(CTFontCreatePathForGlyph(oblique as CTFont, glyph, nil)).boundingBoxOfPath
        var shear = CGAffineTransform(a: 1, b: 0, c: AppFonts.obliqueSkew, d: 1, tx: 0, ty: 0)
        let shearedBox = try #require(uprightPath.copy(using: &shear)).boundingBoxOfPath
        #expect(abs(shearedBox.minX - obliqueBox.minX) < 0.01 && abs(shearedBox.maxX - obliqueBox.maxX) < 0.01
            && abs(shearedBox.minY - obliqueBox.minY) < 0.01 && abs(shearedBox.maxY - obliqueBox.maxY) < 0.01,
            "\(uprightPath.boundingBoxOfPath) sheared is \(shearedBox), the oblique face gives \(obliqueBox)")
        #expect(obliqueBox.width > uprightPath.boundingBoxOfPath.width + 1, "the slant must be visible at 13 pt")
        #expect(oblique.lineHeight == upright.lineHeight, "the skew must not change the line box")
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
