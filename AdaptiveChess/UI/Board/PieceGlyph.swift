// boardView.ts GLYPHS / WHITE_PIECE_STYLE / BLACK_PIECE_STYLE: pieces are the Unicode chess
// glyphs (with U+FE0E so they never become emoji) in the body font, whose fallback supplies the
// symbols — the same cascade the browser used, since Lora has no chess glyphs — with an engraved
// look from four 1px outline copies and a soft drop shadow beneath.

import ChessCore
import SwiftUI

enum PieceGlyphs {
    /// `VS` — U+FE0E VARIATION SELECTOR-15, the text presentation selector.
    static let variationSelector = "\u{FE0E}"

    /// `GLYPHS`: the same six (black) glyphs for both colours; colour comes from the style.
    static func glyph(_ type: PieceType) -> String {
        switch type {
        case .king: return "♚"
        case .queen: return "♛"
        case .rook: return "♜"
        case .bishop: return "♝"
        case .knight: return "♞"
        default: return "♟"
        }
    }

    /// `GLYPHS[type] + VS`
    static func text(_ type: PieceType) -> String { glyph(type) + variationSelector }

    /// boardView.ts `PIECE_NAMES` — used by the accessibility labels.
    static func name(_ type: PieceType) -> String {
        switch type {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        default: return ""
        }
    }
}

/// `color` + the five `text-shadow` layers: four 1px outline offsets in `outline` and a
/// `0 2px 3px` drop shadow in `shadow`.
struct PieceStyle: Sendable {
    let fill: Color
    let outline: Color
    let shadow: Color

    /// `WHITE_PIECE_STYLE`
    static let white = PieceStyle(
        fill: Color(hex: 0xF6E8CD),
        outline: Color(hex: 0x8A6435),
        shadow: Color(r: 60, g: 38, b: 10, a: 0.35)
    )

    /// `BLACK_PIECE_STYLE`
    static let black = PieceStyle(
        fill: Color(hex: 0x4A3018),
        outline: Color(r: 244, g: 230, b: 205, a: 0.85),
        shadow: Color(r: 0, g: 0, b: 0, a: 0.3)
    )

    static func of(_ color: PieceColor) -> PieceStyle { color == .white ? .white : .black }
}

/// One piece glyph at a CSS `font-size` with `line-height: 1`, laid out as a `fontSize`-square
/// box (the glyph is centred horizontally like the span in its flex-centred square).
///
/// The glyph sits on the body font's baseline exactly where the browser puts it: a line box
/// `fontSize` tall with Lora's ascent/descent centred inside it. Blink rounds the ascent and
/// descent to whole pixels and floors the half-leading, so the baseline is
/// `round(ascent) + floor((size − round(ascent) − round(descent)) / 2)` from the top; measured
/// against the reference screenshots this is where the pieces land.
struct PieceGlyph: View {
    let type: PieceType
    let color: PieceColor
    let fontSize: CGFloat

    /// Room for the outline and blurred shadow outside the line box.
    private static let bleed: CGFloat = 8

    var body: some View {
        let style = PieceStyle.of(color)
        let font = AppFonts.body(fontSize)
        let baseline = Self.baseline(fontSize: fontSize)
        let bleed = Self.bleed
        Canvas { context, size in
            var text = context.resolve(Text(PieceGlyphs.text(type)).font(font))
            let measured = text.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            let textBaseline = text.firstBaseline(in: measured)
            let origin = CGPoint(
                x: (size.width - measured.width) / 2,
                y: bleed + baseline - textBaseline
            )
            func draw(_ color: Color, dx: CGFloat, dy: CGFloat, in g: inout GraphicsContext) {
                text.shading = .color(color)
                g.draw(text, at: CGPoint(x: origin.x + dx, y: origin.y + dy), anchor: .topLeading)
            }
            // text-shadow paints back to front: the blurred drop shadow, then the outlines.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 1.5))
                draw(style.shadow, dx: 0, dy: 2, in: &layer)
            }
            draw(style.outline, dx: 0, dy: 1, in: &context)
            draw(style.outline, dx: 0, dy: -1, in: &context)
            draw(style.outline, dx: 1, dy: 0, in: &context)
            draw(style.outline, dx: -1, dy: 0, in: &context)
            draw(style.fill, dx: 0, dy: 0, in: &context)
        }
        .frame(width: fontSize + 2 * bleed, height: fontSize + 2 * bleed)
        .frame(width: fontSize, height: fontSize)
        .accessibilityHidden(true)
    }

    /// Baseline offset from the top of a `line-height: 1` box in the body font, with Blink's
    /// integer font metrics.
    static func baseline(fontSize: CGFloat) -> CGFloat {
        guard let ui = AppFonts.uiFont(.body, size: fontSize, weight: 400) else { return fontSize * 0.8 }
        let ascent = ui.ascender.rounded()
        let descent = (-ui.descender).rounded()
        let halfLeading = ((fontSize - ascent - descent) / 2).rounded(.down)
        return ascent + halfLeading
    }
}
