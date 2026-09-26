// Fonts and the type scale of public/styles.css + the inline text styles the TS screens use.
//
// The web app ships two variable fonts and pins `wght` through `@font-face` (400 and 600).
// The bundle carries the same faces as four static instances (see PORTING_PLAN Notes), so the
// CSS weight → face lookup is the browser's: 400/500 → Regular, 600 → SemiBold.

import SwiftUI
import UIKit
import os

enum AppFonts {
    enum Family: Sendable {
        /// `--font-heading: "Cormorant Garamond"`
        case heading
        /// `--font-body: "Lora"`
        case body
    }

    static let headingRegular = "CormorantGaramond-Regular"
    static let headingSemiBold = "CormorantGaramond-SemiBold"
    static let bodyRegular = "Lora-Regular"
    static let bodySemiBold = "Lora-SemiBold"

    /// PostScript names of the four faces registered through `UIAppFonts`.
    static let all = [headingRegular, headingSemiBold, bodyRegular, bodySemiBold]

    /// CSS font matching for a family that ships weights 400 and 600 only: a requested weight
    /// up to 500 resolves to 400, anything heavier to 600.
    static func postScriptName(_ family: Family, weight: Int) -> String {
        switch family {
        case .heading: return weight > 500 ? headingSemiBold : headingRegular
        case .body: return weight > 500 ? bodySemiBold : bodyRegular
        }
    }

    static func font(_ family: Family, size: CGFloat, weight: Int) -> Font {
        .custom(postScriptName(family, weight: weight), fixedSize: size)
    }

    /// `font-family: var(--font-heading); font-weight: var(--font-heading-weight)` (600 unless
    /// the inline style says otherwise).
    static func heading(_ size: CGFloat, weight: Int = 600) -> Font {
        font(.heading, size: size, weight: weight)
    }

    /// `font-family: var(--font-body)` at the body weight (400 unless inline).
    static func body(_ size: CGFloat, weight: Int = 400) -> Font {
        font(.body, size: size, weight: weight)
    }

    static func uiFont(_ family: Family, size: CGFloat, weight: Int) -> UIFont? {
        UIFont(name: postScriptName(family, weight: weight), size: size)
    }

    /// The PostScript names that fail to load at runtime (empty when the bundle is intact).
    static func missingFaces() -> [String] {
        all.filter { UIFont(name: $0, size: 12) == nil }
    }

    /// Runs once at launch: a missing face means the TTF is not in the bundle or `UIAppFonts`
    /// is wrong, which the build cannot catch.
    static func verifyInstalled() {
        let missing = missingFaces()
        guard !missing.isEmpty else { return }
        Logger(subsystem: "com.adaptivechess.app", category: "fonts")
            .fault("Bundled fonts failed to load: \(missing.joined(separator: ", "), privacy: .public)")
        assertionFailure("Bundled fonts failed to load: \(missing)")
    }
}

/// One CSS text style: font, size, `line-height`, `letter-spacing` (em), `text-transform`,
/// colour and opacity.
struct TextStyle: Sendable {
    var family: AppFonts.Family
    var weight: Int
    var size: CGFloat
    /// `line-height` as a multiple of the font size. Defaults to the `body` value (1.55), which
    /// every inline style inherits unless it sets its own; `nil` keeps the font's own line height.
    var lineHeight: CGFloat? = 1.55
    /// `letter-spacing` in em.
    var letterSpacing: CGFloat = 0
    var uppercase = false
    var color: Color?
    var opacity: Double = 1
    /// `font-feature-settings: 'tnum'`
    var tabularNumbers = false

    var font: Font {
        let f = AppFonts.font(family, size: size, weight: weight)
        return tabularNumbers ? f.monospacedDigit() : f
    }

    /// `letter-spacing` in points.
    var tracking: CGFloat { letterSpacing * size }

    /// How much taller the CSS line box is than the font's natural line height (negative when
    /// the CSS line-height is tighter than the font).
    var extraLeading: CGFloat {
        guard let lineHeight, let ui = AppFonts.uiFont(family, size: size, weight: weight) else { return 0 }
        return lineHeight * size - ui.lineHeight
    }

    // MARK: styles.css — base type scale

    /// `body { font-size: 15px; line-height: 1.55; font-weight: 400 }`
    static let body = TextStyle(family: .body, weight: 400, size: 15, lineHeight: 1.55)
    /// `h1 … h6 { font-family: heading; font-weight: 600; line-height: 1.12; letter-spacing: -0.015em }`
    static let h1 = heading(42)
    static let h2 = heading(32)
    static let h3 = heading(25)
    static let h4 = heading(20)
    static let h5 = heading(16)
    /// `h6 { font-size: 13px; text-transform: uppercase; letter-spacing: 0.08em }`
    static let h6 = TextStyle(family: .heading, weight: 600, size: 13, lineHeight: 1.12, letterSpacing: 0.08, uppercase: true)
    /// `figcaption { font-size: 11px }`
    static let figcaption = TextStyle(family: .body, weight: 400, size: 11)

    private static func heading(_ size: CGFloat) -> TextStyle {
        TextStyle(family: .heading, weight: 600, size: size, lineHeight: 1.12, letterSpacing: -0.015)
    }

    // MARK: styles.css — components

    /// `.btn`: heading 600 14px, line-height 1.2
    static let button = TextStyle(family: .heading, weight: 600, size: 14, lineHeight: 1.2)
    /// `.input`: 14px body
    static let input = TextStyle(family: .body, weight: 400, size: 14)
    /// `.card-kicker`: 10px, 0.1em, uppercase, accent
    static let cardKicker = TextStyle(family: .body, weight: 400, size: 10, letterSpacing: 0.1, uppercase: true, color: Theme.accent)
    /// `.card-title`: heading 600 17px, line-height 1.2
    static let cardTitle = TextStyle(family: .heading, weight: 600, size: 17, lineHeight: 1.2)
    /// `.tag`: 11px, 0.02em
    static let tag = TextStyle(family: .body, weight: 400, size: 11, letterSpacing: 0.02)
    /// `.table`: 14px
    static let tableCell = TextStyle(family: .body, weight: 400, size: 14)
    /// `.table th`: 11px, 0.08em, uppercase, text 60%
    static let tableHeader = TextStyle(family: .body, weight: 400, size: 11, letterSpacing: 0.08, uppercase: true, color: Theme.text.opacity(0.6))
    /// `.dialog-title`: heading 600 20px
    static let dialogTitle = TextStyle(family: .heading, weight: 600, size: 20)
    /// `.dialog-body`: 14px, opacity 0.85
    static let dialogBody = TextStyle(family: .body, weight: 400, size: 14, opacity: 0.85)

    // MARK: dom.ts / router.ts / gameScreen.ts inline styles

    /// dom.ts `LABEL_STYLE`: 12px, 0.12em, uppercase, neutral-600
    static let label = TextStyle(family: .body, weight: 400, size: 12, letterSpacing: 0.12, uppercase: true, color: Theme.neutral600)
    /// dom.ts `segStyle`: 13px body
    static let segment = TextStyle(family: .body, weight: 400, size: 13)
    /// router.ts nav label: 10px, 0.1em, uppercase, body
    static let navLabel = TextStyle(family: .body, weight: 400, size: 10, letterSpacing: 0.1, uppercase: true)
    /// router.ts nav icon: 19px, line-height 1
    static let navIcon = TextStyle(family: .body, weight: 400, size: 19, lineHeight: 1)
    /// gameScreen.ts header: heading 400 44px, 0.02em, line-height 1.1
    static let gameTitle = TextStyle(family: .heading, weight: 400, size: 44, lineHeight: 1.1, letterSpacing: 0.02)
    /// gameScreen.ts status line: 13px, 0.14em, uppercase, neutral-600, tnum
    static let gameStatus = TextStyle(family: .body, weight: 400, size: 13, letterSpacing: 0.14, uppercase: true, color: Theme.neutral600, tabularNumbers: true)
    /// gameScreen.ts promotion heading: heading family at 24px; the inline style sets no weight,
    /// so it inherits the body's 400
    static let promotionTitle = TextStyle(family: .heading, weight: 400, size: 24)
}

private struct TextStyleModifier: ViewModifier {
    let style: TextStyle

    func body(content: Content) -> some View {
        let extra = style.extraLeading
        content
            .font(style.font)
            .tracking(style.tracking)
            .textCase(style.uppercase ? .uppercase : nil)
            .lineSpacing(max(0, extra))
            .padding(.vertical, extra / 2)
            .modifier(OptionalForeground(color: style.color))
            .opacity(style.opacity)
    }
}

/// Colour is inherited like CSS: a style without one keeps the surrounding `foregroundStyle`.
private struct OptionalForeground: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.foregroundStyle(color)
        } else {
            content
        }
    }
}

extension View {
    /// Applies a `TextStyle`: font, tracking, uppercase, colour, opacity, and the CSS line box
    /// (extra leading is split above and below so single lines measure `line-height × size`).
    func textStyle(_ style: TextStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}
