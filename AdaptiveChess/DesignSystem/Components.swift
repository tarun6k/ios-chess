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

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.button)
            .padding(.vertical, Theme.Space.s2)
            .padding(.horizontal, variant == .ghost ? Theme.Space.s1 : Theme.Space.s3 * 1.2)
            .frame(maxWidth: block ? .infinity : nil)
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
    static func block(_ variant: ButtonVariant) -> ClassicButtonStyle { ClassicButtonStyle(variant: variant, block: true) }
}

// MARK: - Inputs (`.input`)

/// `.input`: min-height 36, padding 6 × 10, 14px body, divider border (accent when focused),
/// radius 4, accent caret.
private struct InputChrome: ViewModifier {
    let focused: Bool
    var minHeight: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .textStyle(.input)
            .tint(Theme.accent)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(focused ? Theme.accent : Theme.divider, lineWidth: 1))
    }
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
        TextField(placeholder, text: $text)
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
                        .foregroundStyle(Theme.neutral500)
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: style == .card ? Theme.Space.s2 : 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, style == .card ? Theme.Space.s3 : 16)
        .padding(.horizontal, style == .card ? Theme.Space.s3 : 20)
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
    var body: some View { Text(text).textStyle(.label) }
}

// MARK: - Tags (`.tag`)

/// `.tag` + `.tag-accent` / `.tag-accent-2` / `.tag-neutral` / `.tag-outline`.
struct Tag: View {
    enum Variant: Sendable { case accent, accent2, neutral, outline }

    let text: String
    let variant: Variant

    init(_ text: String, _ variant: Variant) {
        self.text = text
        self.variant = variant
    }

    var body: some View {
        Text(text)
            .textStyle(.tag)
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.md * 0.75))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md * 0.75)
                .strokeBorder(variant == .outline ? Theme.accent : .clear, lineWidth: 1))
            .foregroundStyle(foreground)
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
        HStack(spacing: 0) {
            ForEach(options) { option in
                let active = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .textStyle(.segment)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 14)
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
