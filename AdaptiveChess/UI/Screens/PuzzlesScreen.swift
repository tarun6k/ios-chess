// src/ui/puzzlesScreen.ts: the daily challenge, "made for you" puzzles built from recorded
// mistakes, the curated puzzle tiers, endgame drills and constraint games.

import ChessCore
import ChessServices
import SwiftUI

struct PuzzlesScreen: View {
    @Environment(AppBoot.self) private var boot

    private static let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        let progress = boot.state.progress
        ScreenPage { vw in
            PageHeader(title: "Challenges", status: "\(progress.counters.puzzlesSolved) solved · \(progress.xp) XP")
            PageColumn(viewportWidth: vw) {
                dailySection(progress)
                if !boot.state.mistakes.isEmpty {
                    madeForYou
                }
                ForEach([1, 2, 3], id: \.self) { tier in
                    let list = puzzles.filter { $0.tier == tier }
                    if !list.isEmpty {
                        let tierName = tier == 1 ? "Warm-up" : tier == 2 ? "Sharpen" : "Master"
                        section("Puzzles · \(tierName)") {
                            ForEach(list) { p in
                                puzzleCard(p, status: progress.solvedPuzzles.contains(p.id) ? "Solved ✓" : "+\(p.xp) XP")
                            }
                        }
                    }
                }
                drillsSection(progress)
                constraintsSection(progress)
            }
        }
    }

    // MARK: sections

    private func dailySection(_ progress: PlayerProgress) -> some View {
        let daily = dailyPuzzle()
        return section("Daily challenge") {
            puzzleCard(daily, status: isDailyDone(progress) ? "Solved today ✓" : "+\(daily.xp) XP · streak \(progress.dailyStreak)", isDaily: true)
        }
    }

    private var madeForYou: some View {
        section("Made for you") {
            ForEach(Array(boot.state.mistakes.prefix(5).enumerated()), id: \.offset) { _, mk in
                let when = Date(timeIntervalSince1970: Double(mk.date) / 1000)
                let day = Self.days[Calendar.current.component(.weekday, from: when) - 1]
                cardButton {
                    boot.startGame(NewGameOptions(mode: .puzzle, challenge: ChallengeContext(mistake: mk)))
                    boot.navigate(.play)
                } content: {
                    CardKicker("From your games")
                    Text("You missed this on \(day)").textStyle(.cardTitle(15))
                    Text("You lost \(String(format: "%.1f", Double(mk.cpLoss) / 100)) pawns of advantage here — find the better move. Untimed · +15 XP")
                        .textStyle(.inline(12.5, opacity: 0.8))
                }
            }
        }
    }

    private func drillsSection(_ progress: PlayerProgress) -> some View {
        section("Endgame drills") {
            ForEach(drills) { d in
                let done = progress.completedDrills.contains(d.id)
                cardButton {
                    boot.startGame(NewGameOptions(mode: .drill, challenge: ChallengeContext(drill: d)))
                    boot.navigate(.play)
                } content: {
                    SpaceBetween(alignment: .baseline) {
                        Text(d.title).textStyle(.cardTitle(15))
                    } trailing: {
                        Tag(done ? "Done ✓" : "Goal: \(d.goal.rawValue)", done ? .accent : .neutral)
                    }
                    Text("\(d.description) Untimed · +\(d.xp) XP").textStyle(.inline(12.5, opacity: 0.8))
                }
            }
        }
    }

    private func constraintsSection(_ progress: PlayerProgress) -> some View {
        section("Constraint games") {
            ForEach(constraints) { c in
                let done = progress.completedConstraints.contains(c.id)
                cardButton {
                    boot.startGame(NewGameOptions(mode: .constraint, challenge: ChallengeContext(constraint: c)))
                    boot.navigate(.play)
                } content: {
                    SpaceBetween(alignment: .baseline) {
                        Text(c.title).textStyle(.cardTitle(15))
                    } trailing: {
                        Tag(done ? "Done ✓" : "vs AI", done ? .accent : .outline)
                    }
                    Text("\(c.description) Win condition declared up front · +\(c.xp) XP").textStyle(.inline(12.5, opacity: 0.8))
                }
            }
        }
    }

    // MARK: pieces

    private func startPuzzle(_ p: Puzzle, isDaily: Bool) {
        boot.startGame(NewGameOptions(mode: .puzzle, challenge: ChallengeContext(puzzle: p, isDaily: isDaily)))
        boot.navigate(.play)
    }

    private func puzzleCard(_ p: Puzzle, status: String, isDaily: Bool = false) -> some View {
        let kindLabel: String
        switch p.kind {
        case .mate1: kindLabel = "Mate in 1"
        case .mate2: kindLabel = "Mate in 2"
        case .mate3: kindLabel = "Mate in 3"
        case .tactic: kindLabel = "Win material"
        case .defense: kindLabel = "Defense"
        }
        return cardButton {
            startPuzzle(p, isDaily: isDaily)
        } content: {
            SpaceBetween(alignment: .baseline) {
                Text(p.title).textStyle(.cardTitle(15))
            } trailing: {
                Tag(kindLabel, .neutral)
            }
            Text("\(p.prompt) Untimed · \(status)").textStyle(.inline(12.5, opacity: 0.8))
        }
        .accessibilityIdentifier("puzzle-\(p.id)")
    }

    /// `<div class="card" style="cursor:pointer" onclick=…>`
    private func cardButton<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            Card(style: .card) { content() }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `section(title, ...cards)`: a column with gap 10 under a LABEL.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
