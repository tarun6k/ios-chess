// src/ui/statsScreen.ts: rating and its graph, level progress, the style profile with the last
// adaptation notes, recurring weaknesses, openings, badges and the recent-games archive.

import ChessCore
import ChessServices
import SwiftUI
import UIKit

struct InsightsScreen: View {
    @Environment(AppBoot.self) private var boot

    private static let weaknessLabel: [WeaknessKey: String] = [
        .hangingPieces: "Leaving pieces undefended",
        .missedTactics: "Missing tactical shots",
        .backRank: "Back-rank vulnerability",
        .endgame: "Endgame technique",
        .opening: "Opening mistakes",
        .kingSafety: "King safety",
    ]

    var body: some View {
        let state = boot.state
        let m = state.model
        let p = state.progress
        let lv = levelForXp(p.xp)
        let style = classifyStyle(m.features)
        ScreenPage { vw in
            PageHeader(title: "Insights", status: "\(state.playerName ?? "Guest") · Rating \(m.rating) · Level \(lv.level)")
            PageColumn(viewportWidth: vw) {
                ratingCard(m)
                levelCard(lv)
                styleCard(m, style)
                weaknessesCard(m)
                openingsCard(m)
                badgesCard(p)
                if !state.archive.isEmpty {
                    recentGamesCard(state.archive)
                }
            }
        }
    }

    // MARK: Rating graph

    private func ratingCard(_ m: PlayerModel) -> some View {
        Card(style: .inline) {
            SpaceBetween(alignment: .baseline) {
                SectionLabel("Rating")
            } trailing: {
                Text(String(m.rating)).textStyle(.inline(22, tabularNumbers: true))
            }
            ratingGraph(m.ratingHistory)
            HStack(spacing: 0) {
                Text("\(m.wins) wins")
                Spacer(minLength: 0)
                Text("\(m.losses) losses")
                Spacer(minLength: 0)
                Text("\(m.draws) draws")
                Spacer(minLength: 0)
                Text(m.streak > 0 ? "↑ \(m.streak) streak" : m.streak < 0 ? "↓ \(-m.streak) streak" : "—")
            }
            .textStyle(.inline(13, color: Theme.neutral600))
        }
    }

    @ViewBuilder private func ratingGraph(_ hist: [RatingPoint]) -> some View {
        if hist.count < 2 {
            Text("Your rating graph appears after a few games vs the AI.")
                .textStyle(.inline(13, color: Theme.neutral500, italic: true))
        } else {
            RatingGraph(values: hist.map(\.rating))
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .accessibilityLabel("Rating graph")
        }
    }

    // MARK: XP / level

    private func levelCard(_ lv: LevelInfo) -> some View {
        Card(style: .inline) {
            SpaceBetween(alignment: .baseline) {
                SectionLabel("Level \(lv.level)")
            } trailing: {
                Text("\(lv.into) / \(lv.needed) XP").textStyle(.inline(12, color: Theme.neutral500))
            }
            GeometryReader { proxy in
                Rectangle()
                    .fill(Theme.accent400)
                    .frame(width: proxy.size.width * CGFloat(jsRound(100 * Double(lv.into) / Double(lv.needed))) / 100)
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.divider, lineWidth: 1))
            .accessibilityLabel("Level progress")
        }
    }

    // MARK: Style profile

    private func featureRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(Theme.neutral600)
            Spacer(minLength: 0)
            Text(value)
        }
        .textStyle(.inline(13.5))
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) { DividerLine(color: Theme.neutral200) }
    }

    private func styleCard(_ m: PlayerModel, _ style: StyleClassification) -> some View {
        let f = m.features
        return Card(style: .inline) {
            SectionLabel("How the AI reads you")
            // `text-transform: capitalize`
            CardTitle((f.games >= 2 ? "\(style.label.rawValue) player" : "Still learning you…").capitalized)
            featureRow("Games analyzed", String(f.games))
            featureRow("Capture rate", jsToFixed(f.avgCaptureRate * 100, 0) + "% of moves")
            featureRow("Queen out by", f.avgEarlyQueenPly >= 23 ? "late" : "move \(jsRound(f.avgEarlyQueenPly / 2 + 1))")
            featureRow("Castles by", f.avgCastlePly >= 29 ? "rarely castles" : "move \(jsRound(f.avgCastlePly / 2 + 1))")
            featureRow("Accuracy", f.avgCpLoss != 0 ? "\(jsToFixed(f.avgCpLoss, 0)) cp lost/move" : "—")
            if let notes = m.lastAdaptation, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel("Last game adaptation")
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        AdaptationNote(note, size: 12.5)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: Weaknesses

    private func weaknessesCard(_ m: PlayerModel) -> some View {
        let weak = topWeaknesses(m, n: 6)
        return Card(style: .inline) {
            SectionLabel("Working on")
            if weak.isEmpty {
                Text("No recurring weaknesses spotted yet.")
                    .textStyle(.inline(13, color: Theme.neutral500, italic: true))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(weak, id: \.key) { w in
                        HStack(spacing: 8) {
                            Text(Self.weaknessLabel[w.key] ?? w.key.rawValue).textStyle(.inline(13.5))
                            Spacer(minLength: 0)
                            Tag("× \(w.count)", .accent2)
                        }
                    }
                }
            }
        }
    }

    // MARK: Openings

    private func openingsCard(_ m: PlayerModel) -> some View {
        Card(style: .inline) {
            SectionLabel("Your openings")
            if m.openings.isEmpty {
                Text("Play book openings and they will show up here.")
                    .textStyle(.inline(13, color: Theme.neutral500, italic: true))
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        TableCell("Opening", header: true)
                        TableCell("Games", header: true)
                        TableCell("Wins", header: true)
                    }
                    ForEach(Array(m.openings.prefix(6).enumerated()), id: \.offset) { _, o in
                        HStack(spacing: 0) {
                            TableCell(o.name)
                            TableCell(String(o.count))
                            TableCell(String(o.wins))
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Your openings")
            }
        }
    }

    // MARK: Badges

    private func badgesCard(_ p: PlayerProgress) -> some View {
        Card(style: .inline) {
            SectionLabel("Badges · \(p.badges.count)/\(badges.count)")
            WrapLayout(spacing: 6) {
                ForEach(badges) { b in
                    let earned = p.badges.contains(b.id)
                    Tag(b.title, earned ? .accent : .neutral, opacity: earned ? 1 : 0.55)
                        .accessibilityHint(b.description)
                }
            }
        }
    }

    // MARK: Recent games

    private func recentGamesCard(_ archive: [ArchivedGame]) -> some View {
        Card(style: .inline) {
            SectionLabel("Recent games")
            ForEach(Array(archive.prefix(8).enumerated()), id: \.offset) { _, a in
                HStack(spacing: 8) {
                    Text(a.result).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Date(timeIntervalSince1970: Double(a.date) / 1000).formatted(date: .numeric, time: .omitted))
                        .foregroundStyle(Theme.neutral500)
                        .fixedSize()
                    Button("PGN") {
                        UIPasteboard.general.string = a.pgn
                    }
                    .buttonStyle(ClassicButtonStyle(variant: .ghost, vertical: 0, horizontal: 6, fontSize: 12))
                }
                .textStyle(.inline(13))
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) { DividerLine(color: Theme.neutral200) }
            }
        }
    }
}

/// An adaptation note: `border-left: 2px solid accent-300; padding-left: 10px` at opacity 0.85.
struct AdaptationNote: View {
    let text: String
    var size: CGFloat = 13

    init(_ text: String, size: CGFloat = 13) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .textStyle(.inline(size, opacity: 0.85))
            .padding(.leading, 10)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.accent300).frame(width: 2) }
    }
}

/// `ratingGraph()`: an SVG `viewBox="0 0 360 80"` at `width: 100%; height: 80px` — the box is
/// scaled uniformly to fit and centred (`preserveAspectRatio` default) — with a 2-unit accent
/// polyline through the rating history, padded 4 horizontally and 6 vertically, ±20 headroom.
struct RatingGraph: View {
    let values: [Int]

    private static let w: CGFloat = 360
    private static let h: CGFloat = 80

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.w, proxy.size.height / Self.h)
            let dx = (proxy.size.width - Self.w * scale) / 2
            let dy = (proxy.size.height - Self.h * scale) / 2
            path.applying(CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale))
                .stroke(Theme.accent, lineWidth: 2 * scale)
        }
    }

    private var path: Path {
        let w = Self.w, h = Self.h
        let minV = CGFloat(values.min() ?? 0) - 20
        let maxV = CGFloat(values.max() ?? 0) + 20
        var path = Path()
        for (i, v) in values.enumerated() {
            let x = (CGFloat(i) / CGFloat(values.count - 1)) * (w - 8) + 4
            let y = h - 6 - ((CGFloat(v) - minV) / (maxV - minV)) * (h - 12)
            // the TS emits the points with one decimal
            let point = CGPoint(x: (x * 10).rounded() / 10, y: (y * 10).rounded() / 10)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
