// The reusable pieces of public/styles.css, src/ui/dom.ts and src/ui/router.ts that the TS
// screens actually use: `.btn` (primary / secondary / ghost / block), `.input`, `.card` +
// dom.ts CARD_STYLE, `.card-kicker` / `.card-title` / LABEL_STYLE, `.tag-*`, the dom.ts
// segmented control, `.table th/td`, `.dialog-backdrop` / `.dialog` / `-title` / `-body` /
// `-actions`, and the bottom navigation bar. Hover states have no touch equivalent and are
// not ported; `:active` maps to the pressed state.

import SwiftUI

// MARK: - Buttons (`.btn`)

/// `.btn` (no modifier class), `.btn-primary`, `.btn-secondary`, `.btn-ghost`.
enum ButtonVariant: Sendable {
    case plain, primary, secondary, ghost
}

/// `.btn`: heading 600 14px / 1.2, padding 9.2 × 16.56 (ghost: 4.6 inline), 1px border,
/// radius 4, disabled opacity 0.45. `block` is `.btn-block` (width 100%, margin-top 9.2).
struct ClassicButtonStyle: ButtonStyle {
    var variant: ButtonVariant
    var block = false
    /// Inline `min-height` (the screens use 44 for the main actions); measured on the border box.
    var minHeight: CGFloat? = nil
    /// Inline `flex: 1` (the review arrows share a row equally).
    var fill = false
    /// Inline `padding` / `font-size` overrides (the Insights "PGN" button uses `0 6px` at 12px).
    var vertical: CGFloat? = nil
    var horizontal: CGFloat? = nil
    var fontSize: CGFloat? = nil

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        var style = TextStyle.button
        if let fontSize { style.size = fontSize }
        return configuration.label
            .textStyle(style)
            .padding(.vertical, vertical ?? Theme.Space.s2)
            .padding(.horizontal, horizontal ?? (variant == .ghost ? Theme.Space.s1 : Theme.Space.s3 * 1.2))
            .frame(maxWidth: block || fill ? .infinity : nil, minHeight: minHeight.map { $0 - 2 })
            .padding(1)
            .background(pressedBackground(configuration.isPressed), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(borderColor, lineWidth: 1))
            .foregroundStyle(foreground)
            .opacity(isEnabled ? 1 : 0.45)
            .padding(.top, block ? Theme.Space.s2 : 0)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch variant {
        case .plain, .secondary: return Theme.text
        case .primary, .ghost: return Theme.accent
        }
    }

    private var borderColor: Color {
        switch variant {
        case .plain, .ghost: return .clear
        case .primary: return Theme.accent
        case .secondary: return Theme.divider
        }
    }

    private func pressedBackground(_ pressed: Bool) -> Color {
        guard pressed else { return .clear }
        switch variant {
        case .plain: return .clear
        case .primary: return Theme.accent.opacity(0.22)
        case .secondary: return Theme.text.opacity(0.14)
        case .ghost: return Theme.accent.opacity(0.18)
        }
    }
}

extension ButtonStyle where Self == ClassicButtonStyle {
    /// `class="btn"`
    static var classic: ClassicButtonStyle { ClassicButtonStyle(variant: .plain) }
    /// `class="btn btn-primary"`
    static var primary: ClassicButtonStyle { ClassicButtonStyle(variant: .primary) }
    /// `class="btn btn-secondary"`
    static var secondary: ClassicButtonStyle { ClassicButtonStyle(variant: .secondary) }
    /// `class="btn btn-ghost"`
    static var ghost: ClassicButtonStyle { ClassicButtonStyle(variant: .ghost) }
    /// `class="btn btn-<variant> btn-block"`
    static func block(_ variant: ButtonVariant, minHeight: CGFloat? = nil) -> ClassicButtonStyle {
        ClassicButtonStyle(variant: variant, block: true, minHeight: minHeight)
    }
    /// `class="btn btn-<variant>" style="min-height: …"`, optionally `flex: 1`.
    static func classic(_ variant: ButtonVariant, minHeight: CGFloat? = nil, fill: Bool = false) -> ClassicButtonStyle {
        ClassicButtonStyle(variant: variant, minHeight: minHeight, fill: fill)
    }
}

// MARK: - Inputs (`.input`)

/// `.input`: min-height 36, padding 6 × 10, 14px body, divider border (accent when focused),
/// radius 4, accent caret. The login screen overrides padding, size and background inline.
struct InputChrome: ViewModifier {
    let focused: Bool
    var minHeight: CGFloat = 36
    var style: TextStyle = .input
    var vertical: CGFloat = 6
    var horizontal: CGFloat = 10
    var background: Color = .clear

    func body(content: Content) -> some View {
        content
            .textStyle(style)
            .tint(Theme.accent)
            .padding(.vertical, vertical)
            .padding(.horizontal, horizontal)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(focused ? Theme.accent : Theme.divider, lineWidth: 1))
            // `:focus-visible { outline: 2px solid accent }` with `.input:focus-visible { outline-offset: 0 }`:
            // a 2px ring hugging the border box while the field has the keyboard.
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: Theme.Radius.md + 2)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                        .padding(-2)
                }
            }
    }

    /// Chrome's default `::placeholder` colour.
    static let placeholderColor = Color(hex: 0x757575)
}

/// `<input class="input">`
struct ClassicTextField: View {
    let placeholder: String
    @Binding var text: String

    @FocusState private var focused: Bool

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        TextField(text: $text, prompt: Text(placeholder).foregroundStyle(InputChrome.placeholderColor)) {
            Text(placeholder)
        }
        .focused($focused)
        .modifier(InputChrome(focused: focused))
    }
}

/// `<textarea class="input">`; the TS PGN box overrides the min-height inline.
struct ClassicTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 90

    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(InputChrome.placeholderColor)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .modifier(InputChrome(focused: focused, minHeight: minHeight))
    }
}

// MARK: - Cards

/// `.card` (gap 9.2, padding 13.8) and dom.ts `CARD_STYLE` (gap 10, padding 16 × 20): a column
/// with a divider border and radius 4.
struct Card<Content: View>: View {
    enum Style: Sendable {
        /// `class="card"`
        case card
        /// dom.ts `CARD_STYLE`
        case inline
    }

    var style: Style = .card
    /// Inline `gap` override (the moves card uses `CARD_STYLE.replace('gap:10px', 'gap:8px')`).
    var gap: CGFloat? = nil
    /// Inline `padding` overrides (the game-over offer cards use `10px 12px`).
    var vertical: CGFloat? = nil
    var horizontal: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: gap ?? (style == .card ? Theme.Space.s2 : 10)) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, vertical ?? (style == .card ? Theme.Space.s3 : 16))
        .padding(.horizontal, horizontal ?? (style == .card ? Theme.Space.s3 : 20))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.divider, lineWidth: 1))
    }
}

/// `.card-kicker`
struct CardKicker: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).textStyle(.cardKicker) }
}

/// `.card-title`
struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).textStyle(.cardTitle) }
}

/// dom.ts `LABEL_STYLE` — the uppercase small label on every card.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).textStyle(.label).minContent(text, .label) }
}

// MARK: - Tags (`.tag`)

/// `.tag` + `.tag-accent` / `.tag-accent-2` / `.tag-neutral` / `.tag-outline`.
struct Tag: View {
    enum Variant: Sendable { case accent, accent2, neutral, outline }

    let text: String
    let variant: Variant
    /// Inline `min-height` — the time-control tag buttons use 28.
    var minHeight: CGFloat? = nil
    /// Inline `opacity` — unearned badges sit at 0.55.
    var opacity: Double = 1

    init(_ text: String, _ variant: Variant, minHeight: CGFloat? = nil, opacity: Double = 1) {
        self.text = text
        self.variant = variant
        self.minHeight = minHeight
        self.opacity = opacity
    }

    var body: some View {
        Text(text)
            .textStyle(.tag)
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
            .frame(minHeight: minHeight)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.md * 0.75))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md * 0.75)
                .strokeBorder(variant == .outline ? Theme.accent : .clear, lineWidth: 1))
            .foregroundStyle(foreground)
            .opacity(opacity)
    }

    private var background: Color {
        switch variant {
        case .accent: return Theme.accent100
        case .accent2: return Theme.accent2_100
        case .neutral: return Theme.neutral100
        case .outline: return .clear
        }
    }

    private var foreground: Color {
        switch variant {
        case .accent: return Theme.accent800
        case .accent2: return Theme.accent2_800
        case .neutral: return Theme.neutral800
        case .outline: return Theme.accent
        }
    }
}

// MARK: - Segmented control (dom.ts `segStyle` / `segWrap`)

/// A row of `segStyle` buttons inside `segWrap`: 13px body, padding 4 × 14, the active option
/// on accent-100 with accent-800 text and a 2px accent bottom border, inactive options in
/// neutral-600; the wrap has a divider border, radius 4 and clips its children.
struct SegmentedControl<Value: Hashable & Sendable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }

        init(_ value: Value, _ label: String) {
            self.value = value
            self.label = label
        }
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        // `segWrap`: `display: flex` — the buttons shrink like flex items (never below their
        // widest word, so "Push me" wraps to "Push / me") and stretch to the row's height.
        FlexRow(align: .stretch, fill: false) {
            ForEach(options) { option in
                let active = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .textStyle(.segment)
                        .multilineTextAlignment(.center)
                        .minContent(option.label, .segment, alignment: .center)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(active ? Theme.accent800 : Theme.neutral600)
                        .background(active ? Theme.accent100 : .clear)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(active ? Theme.accent : .clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .padding(1)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.divider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Table (`.table`)

/// `.table th` / `.table td`: padding 9.2 and a divider bottom border; headers are 11px
/// uppercase at 60% text, cells 14px. Lay rows out as `HStack(spacing: 0)` of cells.
struct TableCell: View {
    let text: String
    var header = false
    var alignment: Alignment = .leading

    init(_ text: String, header: Bool = false, alignment: Alignment = .leading) {
        self.text = text
        self.header = header
        self.alignment = alignment
    }

    var body: some View {
        Text(text)
            .textStyle(header ? .tableHeader : .tableCell)
            .padding(Theme.Space.s2)
            .frame(maxWidth: .infinity, alignment: alignment)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

// MARK: - Dialogs (`.dialog-backdrop`, `.dialog`)

/// `.dialog-backdrop`: covers the screen (`position: fixed; inset: 0`) in neutral-900 at 50%
/// (the promotion dialog passes its own `rgba(32,31,29,0.4)`), padding 18.4, content centred.
struct DialogBackdrop<Content: View>: View {
    var background: Color = Theme.neutral900.opacity(0.5)
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            background
            content.padding(Theme.Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea() // `position: fixed; inset: 0` covers the whole viewport, nav bar included
    }
}

/// `.dialog`: width min(440, 100%), column gap 13.8, padding 18.4, radius 7, surface
/// background, shadow-lg, divider border. The promotion dialog overrides most of these inline.
struct Dialog<Content: View>: View {
    var gap: CGFloat = Theme.Space.s3
    var vertical: CGFloat = Theme.Space.s4
    var horizontal: CGFloat = Theme.Space.s4
    var radius: CGFloat = Theme.Radius.lg
    var background: Color = Theme.surface
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: alignment, spacing: gap) {
            content
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .padding(.vertical, vertical)
        .padding(.horizontal, horizontal)
        .background(background, in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.divider, lineWidth: 1))
        .compositingGroup() // one box-shadow for the dialog, not one per child
        .themeShadow(.lg)
        .frame(maxWidth: 440)
    }
}

/// `.dialog-title`
struct DialogTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).textStyle(.dialogTitle) }
}

/// `.dialog-body`
struct DialogBody: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).textStyle(.dialogBody) }
}

/// `.dialog-actions`: trailing row, gap 9.2, margin-top 9.2.
struct DialogActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Theme.Space.s2) { content }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, Theme.Space.s2)
    }
}

// MARK: - Bottom navigation (router.ts)

/// One nav button: flex 1, min-height 52, icon 19px over a 10px uppercase label, gap 1,
/// padding 6 × 0, accent-700 + 2px accent top border when current, neutral-600 otherwise.
/// The icon gets U+FE0E appended: the browser draws ⚙ and friends as text, iOS would pick the
/// colour emoji without the selector.
struct BottomNavItem: View {
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(icon + PieceGlyphs.variationSelector).textStyle(.navIcon).accessibilityHidden(true)
                Text(label).textStyle(.navLabel)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(alignment: .top) {
                Rectangle().fill(active ? Theme.accent : .clear).frame(height: 2)
            }
            .foregroundStyle(active ? Theme.accent700 : Theme.neutral600)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/// The fixed bottom `<nav>`: bg at 92% over an 8px blur, divider top border, safe-area bottom
/// padding. Place it with `.safeAreaInset(edge: .bottom)` so screens scroll underneath.
struct BottomNavBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .background {
                Rectangle()
                    .fill(Theme.background.opacity(0.92))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Main navigation")
    }
}
