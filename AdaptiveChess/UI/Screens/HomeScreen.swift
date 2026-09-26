// src/ui/homeScreen.ts: continue game, new game setup, daily challenge, stats snapshot and
// PGN import. Extends the design's visual language (header + cards + segmented controls).

import ChessCore
import ChessServices
import SwiftUI

/// The `HomeScreen` instance fields — main.ts registers one screen per route, so the picked
/// mode, side, level and timer survive switching tabs.
@Observable @MainActor
final class HomeScreenModel {
    enum Timer: Hashable {
        case off
        case preset(Int)
        case custom
    }

    var mode: GameMode = .ai
    var color: PieceColor = .white
    var difficulty: DifficultyMode
    var timer: Timer = .off
    var customBase: Double = 10
    var customInc: Double = 5

    init(difficulty: DifficultyMode) {
        self.difficulty = difficulty
    }
}

struct HomeScreen: View {
    @Environment(AppBoot.self) private var boot

    @State private var pgnText = ""
    @State private var importNote = ""

    var body: some View {
        @Bindable var model = boot.homeScreen
        let state = boot.state
        ScreenPage { vw in
            PageHeader(
                title: "Chess", titleStyle: .gameTitle,
                status: state.playerName.map { "Welcome back, \($0)" } ?? "An opponent that learns you"
            )
            PageColumn(viewportWidth: vw) {
                if let saved = state.saved, !saved.uciMoves.isEmpty {
                    continueCard(saved)
                }
                newGameCard($model)
                dailyCard
                progressCard
                importCard
            }
        }
    }

    // MARK: Continue

    private func continueCard(_ s: SavedGame) -> some View {
        Card(style: .inline) {
            SectionLabel("Continue")
            CardTitle(s.mode == .pvp ? "Pass-and-play game" : "Game vs AI (\(s.aiElo))")
            Text(continueDetail(s)).textStyle(.inline(13, opacity: 0.8))
            Button("Resume") {
                if boot.controller.resume(s) { boot.navigate(.play) }
            }
            .buttonStyle(.classic(.primary, minHeight: 44))
            .accessibilityIdentifier("home-resume")
        }
    }

    private func continueDetail(_ s: SavedGame) -> String {
        let n = s.uciMoves.count
        var text = "\(Int((Double(n) / 2).rounded(.up))) move\(n > 2 ? "s" : "") played"
        if s.timeControl != nil, let cr = s.clockRemaining {
            text += " · \(formatClock(cr.white)) — \(formatClock(cr.black))"
        }
        return text
    }

    // MARK: New game

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        SpaceBetween(spacing: 8, wrap: true) {
            SectionLabel(label)
        } trailing: {
            control()
        }
    }

    private func newGameCard(_ model: Bindable<HomeScreenModel>) -> some View {
        Card(style: .inline) {
            SectionLabel("New game")
            row("Mode") {
                SegmentedControl(options: [.init(GameMode.ai, "vs AI"), .init(GameMode.pvp, "2 players")], selection: model.mode)
                    .accessibilityIdentifier("home-mode")
            }
            if model.wrappedValue.mode == .ai {
                row("Your side") {
                    SegmentedControl(options: [.init(PieceColor.white, "White"), .init(PieceColor.black, "Black")], selection: model.color)
                        .accessibilityIdentifier("home-side")
                }
                row("AI level") {
                    SegmentedControl(options: [.init(DifficultyMode.learn, "Learn"), .init(DifficultyMode.match, "Match"), .init(DifficultyMode.challenge, "Push me")],
                                     selection: model.difficulty)
                        .accessibilityIdentifier("home-level")
                }
            }
            row("Timer") { EmptyView() }
            WrapLayout(spacing: 6) {
                tcTag("Untimed", active: model.wrappedValue.timer == .off) { model.wrappedValue.timer = .off }
                ForEach(Array(timePresets.enumerated()), id: \.offset) { i, tc in
                    tcTag(tc.name, active: model.wrappedValue.timer == .preset(i)) { model.wrappedValue.timer = .preset(i) }
                }
                tcTag("Custom", active: model.wrappedValue.timer == .custom) { model.wrappedValue.timer = .custom }
            }
            if model.wrappedValue.timer == .custom {
                HStack(alignment: .center, spacing: 10) {
                    numberField("Minutes", value: model.customBase)
                    numberField("Increment (s)", value: model.customInc)
                }
            }
            Button("Start game", action: startGame)
                .buttonStyle(.block(.primary, minHeight: 44))
                .accessibilityIdentifier("home-start")
        }
    }

    /// `<button class="tag tag-accent|tag-neutral" style="border:none; min-height:28px">`
    private func tcTag(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Tag(label, active ? .accent : .neutral, minHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    /// `<label style="font-size:12px; color:neutral-600; flex:1">Minutes <input class="input" type="number"></label>`
    private func numberField(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).textStyle(.inline(12, color: Theme.neutral600))
            NumberField(value: value)
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity)
    }

    private func startGame() {
        let model = boot.homeScreen
        var tc: TimeControl? = nil
        switch model.timer {
        case .off: tc = nil
        case .preset(let i): tc = timePresets[i]
        case .custom: tc = customTimeControl(baseMin: model.customBase, incSec: model.customInc)
        }
        boot.state.difficulty = model.difficulty
        boot.state.persist(.difficulty)
        boot.startGame(NewGameOptions(mode: model.mode, playerColor: model.color, difficulty: model.difficulty, timeControl: tc))
        boot.navigate(.play)
    }

    // MARK: Daily challenge

    private var dailyCard: some View {
        let daily = dailyPuzzle()
        let done = isDailyDone(boot.state.progress)
        let streak = boot.state.progress.dailyStreak
        return Card(style: .inline) {
            SpaceBetween(alignment: .baseline) {
                SectionLabel("Daily challenge")
            } trailing: {
                Tag("\(streak) day streak", streak > 0 ? .accent : .neutral)
            }
            CardTitle(daily.title)
            Text("\(daily.prompt) · +\(daily.xp) XP").textStyle(.inline(13, opacity: 0.8))
            if done {
                Tag("Solved today ✓", .accent)
            } else {
                Button("Solve it") {
                    boot.startGame(NewGameOptions(mode: .puzzle, challenge: ChallengeContext(puzzle: daily, isDaily: true)))
                    boot.navigate(.play)
                }
                .buttonStyle(.classic(.primary, minHeight: 44))
                .accessibilityIdentifier("home-daily")
            }
        }
    }

    // MARK: Stats snapshot

    private var progressCard: some View {
        let m = boot.state.model
        let lv = levelForXp(boot.state.progress.xp)
        let style = classifyStyle(m.features)
        return Button {
            boot.navigate(.stats)
        } label: {
            Card(style: .inline) {
                SectionLabel("Your progress")
                HStack(spacing: 0) {
                    Text("Rating \(m.rating)")
                    Spacer(minLength: 0)
                    Text("Level \(lv.level)")
                    Spacer(minLength: 0)
                    Text("\(m.wins)W \(m.losses)L \(m.draws)D")
                }
                .textStyle(.inline(14))
                Text(m.features.games >= 2
                     ? "The AI reads your style as \(style.label.rawValue)."
                     : "Play a few games so the AI can learn your style.")
                    .textStyle(.inline(13, opacity: 0.8))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-progress")
    }

    // MARK: PGN import

    private var importCard: some View {
        Card(style: .inline) {
            SectionLabel("Import game")
            ClassicTextEditor(placeholder: "Paste PGN here…", text: $pgnText, minHeight: 60)
                .accessibilityIdentifier("home-pgn")
            Button("Load PGN", action: importPgn)
                .buttonStyle(.secondary)
                .accessibilityIdentifier("home-load-pgn")
            Text(importNote).textStyle(.inline(12, color: Theme.neutral500))
        }
    }

    private func importPgn() {
        do {
            let (game, _) = try fromPGN(pgnText)
            boot.state.archive.insert(ArchivedGame(
                pgn: pgnText, mode: .pvp, playerColor: .white,
                result: game.result?.message ?? "Imported game", score: game.result?.score ?? "*",
                aiElo: nil, date: Int((Date().timeIntervalSince1970 * 1000).rounded()), analysis: nil, adaptationNotes: [],
                startFen: game.startFEN, uciMoves: game.uciLine()
            ), at: 0)
            boot.state.persist(.archive)
            importNote = "Imported \(game.history.count) moves — see Insights → Recent games."
        } catch {
            importNote = "Could not read that PGN: " + String(describing: error)
        }
    }
}

/// `<input class="input" type="number">`: a decimal field with the `.input` chrome; the value
/// updates on commit like the TS `onchange`.
struct NumberField: View {
    @Binding var value: Double

    @FocusState private var focused: Bool

    var body: some View {
        TextField("", value: $value, format: .number)
            .keyboardType(.decimalPad)
            .focused($focused)
            .modifier(InputChrome(focused: focused))
    }
}
