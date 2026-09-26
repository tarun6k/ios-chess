// The page scaffolding shared by home, play, puzzles, insights and settings: the centred column
// container with its clamp() paddings, the title / divider / status header, and a flex-wrap
// layout for tag rows, button rows and the board + side panel row.

import SwiftUI

/// CSS `clamp(lo, preferred, hi)`.
func cssClamp(_ lo: CGFloat, _ preferred: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(lo, preferred), hi)
}

/// JavaScript `Number.prototype.toFixed(digits)`: ties round away from zero (unlike printf's
/// round-half-even), and there is no exponent form for the magnitudes the screens format.
func jsToFixed(_ value: Double, _ digits: Int) -> String {
    let scale = pow(10.0, Double(digits))
    let scaled = (abs(value) * scale).rounded(.toNearestOrAwayFromZero)
    let text = String(format: "%.\(digits)f", scaled / scale)
    return value < 0 && scaled != 0 ? "-" + text : text
}

/// JavaScript `Math.round`: halves round toward +∞.
func jsRound(_ value: Double) -> Int {
    Int((value + 0.5).rounded(.down))
}

/// `padding: clamp(20px, 4vw, 36px) 12px 96px; display: flex; flex-direction: column;
/// align-items: center` — the 96px bottom padding lets the last card scroll clear of the nav,
/// which floats over the content exactly like the TS `position: fixed` bar.
struct ScreenPage<Content: View>: View {
    @ViewBuilder let content: (_ viewportWidth: CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content(proxy.size.width)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, cssClamp(20, 0.04 * proxy.size.width, 36))
                .padding(.horizontal, 12)
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

/// `<header style="text-align:center">`: the title, a 64 × 1 divider with 10px margins, and
/// the uppercase status line (omitted on Settings).
struct PageHeader: View {
    let title: String
    var titleStyle: TextStyle = .pageTitle
    var status: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text(title).textStyle(titleStyle)
            Rectangle().fill(Theme.divider)
                .frame(width: 64, height: 1)
                .padding(.vertical, 10)
            if let status {
                Text(status).textStyle(.gameStatus)
            }
        }
        .multilineTextAlignment(.center)
    }
}

/// The card column under the header: `width: min(420px, calc(100vw - 24px)); display: flex;
/// flex-direction: column; gap: 20px; margin-top: clamp(16px, 3vw, 28px)`.
struct PageColumn<Content: View>: View {
    let viewportWidth: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
        }
        .frame(width: min(420, viewportWidth - 24), alignment: .leading)
        .padding(.top, cssClamp(16, 0.03 * viewportWidth, 28))
    }
}

/// `display: flex; justify-content: space-between; align-items: center|baseline` — the two-ended
/// row that every card uses for a label and its control. A `FlexRow`, so when the label and the
/// control do not both fit they shrink like flex items instead of one of them being squeezed to
/// nothing (`wrap` is the home screen's `flex-wrap: wrap`).
struct SpaceBetween<Leading: View, Trailing: View>: View {
    var alignment: FlexRow.Align = .center
    var spacing: CGFloat = 0
    var wrap = false
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        FlexRow(justify: .spaceBetween, align: alignment, gap: spacing, wrap: wrap) {
            leading
            trailing
        }
    }
}

/// CSS `display: flex; flex-direction: row` as the screens use it: items start at their content
/// width (`flex-basis: auto; flex-grow: 0`) and, when the row is too narrow, shrink in
/// proportion to that width but never below their min-content width (`flex-shrink: 1;
/// min-width: auto`) — so "AI level" wraps to two lines and "Push me" to "Push / me" exactly
/// where the browser does. Supports `justify-content`, `align-items`, `gap` and `flex-wrap`.
/// Text items declare their min-content width with `.minContent(_:_:)`; items that must adopt
/// the resolved width (the segment cells) carry `.frame(maxWidth: .infinity)`.
struct FlexRow: Layout {
    enum Justify { case start, center, spaceBetween }
    enum Align { case start, center, baseline, stretch }

    var justify: Justify = .start
    var align: Align = .center
    var gap: CGFloat = 0
    var wrap = false
    /// A block-level row takes the full proposed width; an inline one (`segWrap` as a flex item)
    /// shrink-wraps its items.
    var fill = true

    private struct Item {
        var basis: CGFloat
        var minimum: CGFloat
        var width: CGFloat = 0
        var height: CGFloat = 0
        var baseline: CGFloat = 0
    }

    private struct Line {
        var range: Range<Int>
        var height: CGFloat
        var maxBaseline: CGFloat
        var width: CGFloat
    }

    private func resolve(_ subviews: Subviews, width: CGFloat?) -> (items: [Item], lines: [Line], width: CGFloat) {
        var items = subviews.map { sub -> Item in
            let ideal = sub.sizeThatFits(.unspecified).width
            let minimum = sub.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
            return Item(basis: ideal, minimum: min(minimum, ideal))
        }
        let contentWidth = items.reduce(0) { $0 + $1.basis } + gap * CGFloat(max(0, items.count - 1))
        let available = width ?? contentWidth

        // flex-wrap: an item that no longer fits at its hypothetical size starts a new line
        var ranges: [Range<Int>] = []
        if items.isEmpty {
            ranges = []
        } else if wrap, width != nil {
            var start = 0
            var used: CGFloat = 0
            for i in items.indices {
                let hypothetical = max(items[i].basis, items[i].minimum)
                if i > start, used + gap + hypothetical > available + 0.5 {
                    ranges.append(start..<i)
                    start = i
                    used = hypothetical
                } else {
                    used += (i > start ? gap : 0) + hypothetical
                }
            }
            ranges.append(start..<items.count)
        } else {
            ranges = [0..<items.count]
        }

        // flex-shrink: distribute the deficit in proportion to the bases, freezing items that
        // would drop below their min-content width (the spec's "resolve flexible lengths" loop)
        for range in ranges {
            let space = available - gap * CGFloat(max(0, range.count - 1))
            var frozen = Set<Int>()
            for i in range { items[i].width = items[i].basis }
            while true {
                let unfrozen = range.filter { !frozen.contains($0) }
                let frozenTotal = frozen.reduce(0) { $0 + items[$1].width }
                let basisTotal = unfrozen.reduce(0) { $0 + items[$1].basis }
                let deficit = basisTotal - (space - frozenTotal)
                guard deficit > 0, !unfrozen.isEmpty, basisTotal > 0 else { break }
                var violated = false
                for i in unfrozen {
                    let shrunk = items[i].basis - deficit * items[i].basis / basisTotal
                    if shrunk < items[i].minimum {
                        items[i].width = items[i].minimum
                        frozen.insert(i)
                        violated = true
                    } else {
                        items[i].width = shrunk
                    }
                }
                if !violated { break }
            }
        }

        // cross axis: heights at the resolved widths, baselines for align-items: baseline
        var lines: [Line] = []
        for range in ranges {
            var height: CGFloat = 0
            var maxBaseline: CGFloat = 0
            var maxBelow: CGFloat = 0
            var lineWidth = gap * CGFloat(max(0, range.count - 1))
            for i in range {
                let dims = subviews[i].dimensions(in: ProposedViewSize(width: items[i].width, height: nil))
                items[i].height = dims.height
                items[i].baseline = dims[VerticalAlignment.firstTextBaseline]
                height = max(height, dims.height)
                maxBaseline = max(maxBaseline, items[i].baseline)
                maxBelow = max(maxBelow, dims.height - items[i].baseline)
                lineWidth += items[i].width
            }
            if align == .baseline { height = max(height, maxBaseline + maxBelow) }
            lines.append(Line(range: range, height: height, maxBaseline: maxBaseline, width: lineWidth))
        }

        let usedWidth: CGFloat
        if fill, let width {
            usedWidth = width
        } else {
            usedWidth = lines.map(\.width).max() ?? 0
        }
        return (items, lines, usedWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (_, lines, width) = resolve(subviews, width: proposal.width)
        let height = lines.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (items, lines, _) = resolve(subviews, width: bounds.width)
        var y = bounds.minY
        for line in lines {
            let count = line.range.count
            let spare = max(0, bounds.width - line.width)
            var x = bounds.minX
            var step = gap
            switch justify {
            case .start: break
            case .center: x += spare / 2
            case .spaceBetween: if count > 1 { step = gap + spare / CGFloat(count - 1) }
            }
            for i in line.range {
                let item = items[i]
                let itemY: CGFloat
                var height: CGFloat? = nil
                switch align {
                case .start: itemY = y
                case .center: itemY = y + (line.height - item.height) / 2
                case .baseline: itemY = y + line.maxBaseline - item.baseline
                case .stretch:
                    itemY = y
                    height = line.height
                }
                subviews[i].place(at: CGPoint(x: x, y: itemY), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: item.width, height: height))
                x += item.width + step
            }
            y += line.height + gap
        }
    }
}

/// CSS `max-height` on a scroll container: proposes at most `maxHeight` to its child and never
/// grows past it, but unlike `.frame(maxHeight:)` it shrinks to the child's natural height. Pair
/// it with `ViewThatFits(in: .vertical) { content; ScrollView { content } }` for `overflow-y: auto`.
struct CapHeight: Layout {
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let capped = ProposedViewSize(width: proposal.width, height: min(proposal.height ?? maxHeight, maxHeight))
        let size = child.sizeThatFits(capped)
        return CGSize(width: size.width, height: min(size.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

/// A 1px divider line (`height:1px; background:var(--color-divider)`).
struct DividerLine: View {
    var color: Color = Theme.divider
    var body: some View {
        Rectangle().fill(color).frame(height: 1).frame(maxWidth: .infinity)
    }
}

/// `display: flex; flex-wrap: wrap; gap: …` with `justify-content: flex-start | center` and
/// `align-items: flex-start`: children keep their ideal size and wrap onto new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat? = nil
    var justify: HorizontalAlignment = .leading
    /// `flex: 1` children stretch to share the line's spare width (used by the review arrows).
    var stretch = false

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(for subviews: Subviews, in width: CGFloat) -> (lines: [Line], sizes: [CGSize]) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var lines: [Line] = []
        var current = Line()
        for (i, size) in sizes.enumerated() {
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && needed > width + 0.5 {
                lines.append(current)
                current = Line()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(i)
        }
        if !current.indices.isEmpty { lines.append(current) }
        return (lines, sizes)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
            + spacing * CGFloat(max(0, subviews.count - 1))
        let (lines, _) = lines(for: subviews, in: width)
        let gap = lineSpacing ?? spacing
        let height = lines.map(\.height).reduce(0, +) + gap * CGFloat(max(0, lines.count - 1))
        let maxLine = lines.map(\.width).max() ?? 0
        return CGSize(width: stretch || proposal.width != nil ? width : maxLine, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (lines, sizes) = lines(for: subviews, in: bounds.width)
        let gap = lineSpacing ?? spacing
        var y = bounds.minY
        for line in lines {
            let spare = max(0, bounds.width - line.width)
            let extra = stretch ? spare / CGFloat(line.indices.count) : 0
            var x = bounds.minX
            if !stretch {
                switch justify {
                case .center: x += spare / 2
                case .trailing: x += spare
                default: break
                }
            }
            for i in line.indices {
                let size = sizes[i]
                let w = size.width + extra
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: w, height: size.height))
                x += w + spacing
            }
            y += line.height + gap
        }
    }
}
