// Design tokens of the "Classical" system in public/styles.css (`:root`). Every custom property
// is here with its exact value; `color-mix(in srgb, X N%, transparent)` is X at alpha N/100.

import SwiftUI

extension Color {
    /// `#rrggbb` as written in the CSS.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// `rgba(r, g, b, a)` as written in the CSS.
    init(r: Int, g: Int, b: Int, a: Double = 1) {
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: a)
    }
}

enum Theme {
    // MARK: Roles

    /// `--color-bg`
    static let background = Color(hex: 0xF3F2F2)
    /// `--color-surface`
    static let surface = Color(hex: 0xEAE9E9)
    /// `--color-text`
    static let text = Color(hex: 0x201F1D)
    /// `--color-accent`
    static let accent = Color(hex: 0xB68235)
    /// `--color-accent-2`
    static let accent2 = Color(hex: 0xAC803E)
    /// `--color-divider: color-mix(in srgb, #201f1d 16%, transparent)`
    static let divider = Color(hex: 0x201F1D, alpha: 0.16)

    // MARK: Tonal ramps (`--color-neutral-*`, `--color-accent-*`, `--color-accent-2-*`)

    static let neutral100 = Color(hex: 0xF8F4F4)
    static let neutral200 = Color(hex: 0xEAE7E7)
    static let neutral300 = Color(hex: 0xD7D3D3)
    static let neutral400 = Color(hex: 0xBAB6B6)
    static let neutral500 = Color(hex: 0x9B9797)
    static let neutral600 = Color(hex: 0x7D7979)
    static let neutral700 = Color(hex: 0x605D5D)
    static let neutral800 = Color(hex: 0x444141)
    static let neutral900 = Color(hex: 0x2D2B2B)

    static let accent100 = Color(hex: 0xFFF3E4)
    static let accent200 = Color(hex: 0xFFE3BF)
    static let accent300 = Color(hex: 0xFACB8D)
    static let accent400 = Color(hex: 0xE1AD66)
    static let accent500 = Color(hex: 0xC28D41)
    static let accent600 = Color(hex: 0xA06F24)
    static let accent700 = Color(hex: 0x7D5411)
    static let accent800 = Color(hex: 0x5A3B0A)
    static let accent900 = Color(hex: 0x3A270D)

    static let accent2_100 = Color(hex: 0xFFF3E4)
    static let accent2_200 = Color(hex: 0xFFE3BE)
    static let accent2_300 = Color(hex: 0xF5CD96)
    static let accent2_400 = Color(hex: 0xDBAF70)
    static let accent2_500 = Color(hex: 0xBC8F4E)
    static let accent2_600 = Color(hex: 0x9B7232)
    static let accent2_700 = Color(hex: 0x79561F)
    static let accent2_800 = Color(hex: 0x573D14)
    static let accent2_900 = Color(hex: 0x382810)

    // MARK: Spacing (`--space-*`, px == pt)

    enum Space {
        static let s1: CGFloat = 4.6
        static let s2: CGFloat = 9.2
        static let s3: CGFloat = 13.8
        static let s4: CGFloat = 18.4
        static let s6: CGFloat = 27.6
        static let s8: CGFloat = 36.8
    }

    // MARK: Radii (`--radius-*`)

    enum Radius {
        static let sm: CGFloat = 2
        static let md: CGFloat = 4
        static let lg: CGFloat = 7
    }

    // MARK: Shadows (`--shadow-*`)

    /// A CSS `box-shadow: 0 <y> <blur> <color>`. SwiftUI's `shadow(radius:)` takes a Gaussian
    /// sigma, and CSS blur radius is 2 sigma, so `radius` is `blur / 2`.
    struct Shadow: Sendable {
        let color: Color
        let y: CGFloat
        let blur: CGFloat
        var radius: CGFloat { blur / 2 }

        /// `0 1px 2px #2d2b2b 14%`
        static let sm = Shadow(color: Color(hex: 0x2D2B2B, alpha: 0.14), y: 1, blur: 2)
        /// `0 3px 10px #2d2b2b 16%`
        static let md = Shadow(color: Color(hex: 0x2D2B2B, alpha: 0.16), y: 3, blur: 10)
        /// `0 12px 32px #2d2b2b 22%`
        static let lg = Shadow(color: Color(hex: 0x2D2B2B, alpha: 0.22), y: 12, blur: 32)
    }
}

extension View {
    /// Applies one of the `--shadow-*` tokens.
    func themeShadow(_ shadow: Theme.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }
}
