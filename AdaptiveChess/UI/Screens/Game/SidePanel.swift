// gameScreen.ts `sidePanel()` and its cards: challenge, mode, timer, captured pieces, moves,
// the action rows, the review arrows and the note line under them.

import ChessCore
import ChessServices
import SwiftUI

struct SidePanel: View {
    @Environment(AppBoot.self) private var boot
    let reviewing: Bool

    var body: some View {
        let controller = boot.controller
        let model = boot.playScreen
        VStack(alignment: .leading, spacing: 20) {
            if controller.isChallengeGame {
                challengeCard
            }
            if reviewing {
                ReviewCard()
            } else {
                modeCard
                timerCard
            }
            capturedCard
            movesCard
            if !reviewing {
                buttonRows
            } else {
                reviewButtons
            }
            if !model.drawNote.isEmpty {
                Text(model.drawNote)
                    .textStyle(.inline(13, color: Theme.neutral500, italic: true))
                    .accessibilityIdentifier("play-note")
            }
        }
    }

    // MARK: Mode

    private var modeCard: some View {
        let controller = boot.controller
        let model = boot.playScreen
        let isPvp = controller.mode == .pvp
        return Card(style: .inline) {
            SpaceBetween {
                SectionLabel("Mode")
            } trailing: {
                SegmentedControl(
                    options: [.init(GameMode.pvp, "2 players"), .init(GameMode.ai, "vs AI")],
                    selection: Binding(get: { isPvp ? GameMode.pvp : .ai }, set: { model.switchMode($0, boot: boot) })
                )
                .accessibilityIdentifier("play-mode")
            }
            if !isPvp && !controller.isChallengeGame {
                DividerLine()
                SpaceBetween {
                    SectionLabel("AI level")
                } trailing: {
                    SegmentedControl(
                        options: [.init(DifficultyMode.learn, "Learn"), .init(DifficultyMode.match, "Match"), .init(DifficultyMode.challenge, "Push me")],
                        selection: Binding(get: { controller.difficulty }, set: { model.setDifficulty($0, boot: boot) })
                    )
                    .accessibilityIdentifier("play-level")
                }
                Text("AI plays around \(controller.aiElo) — your rating \(boot.state.model.rating)")
                    .textStyle(.inline(12, color: Theme.neutral500))
            }
        }
    }

    // MARK: Timer

    private var timerCard: some View {
        let controller = boot.controller
        let model = boot.playScreen
        let g = controller.game
        let on = controller.timerOn
        return Card(style: .inline) {
            SpaceBetween {
                SectionLabel("Timer")
            } trailing: {
                SegmentedControl(
                    options: [.init(true, "On"), .init(false, "Off")],
                    selection: Binding(get: { on }, set: { model.setTimer($0, boot: boot) })
                )
                .accessibilityIdentifier("play-timer")
            }
            if on {
                if g.history.isEmpty {
                    // preset picker before the game starts (same visual language)
                    DividerLine()
                    WrapLayout(spacing: 6) {
                        ForEach(timePresets, id: \.name) { tc in
                            let active = controller.timeControl?.name == tc.name
                            Button {
                                model.pickPreset(tc, boot: boot)
                            } label: {
                                Tag(tc.name, active ? .accent : .neutral, minHeight: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(active ? [.isSelected] : [])
                        }
                    }
                }
                let running = g.result == nil && controller.timerOn
                let w = controller.clock?.remaining.white ?? controller.timeControl?.baseMs ?? 0
                let b = controller.clock?.remaining.black ?? controller.timeControl?.baseMs ?? 0
                DividerLine()
                clockRow("White", ms: w, active: running && g.turn == .white)
                DividerLine()
                clockRow("Black", ms: b, active: running && g.turn == .black)
            } else {
                Text("Untimed game — take your time.")
                    .textStyle(.inline(13, color: Theme.neutral500, italic: true))
            }
        }
    }

    /// `clockStyle(active, low)`: 22px tabular digits, dark red under 20 s, accent-700 for the
    /// side to move, with a 2px accent underline on the running clock.
    private func clockRow(_ label: String, ms: Int, active: Bool) -> some View {
        let low = ms < 20000 && ms > 0
        return SpaceBetween(alignment: .baseline) {
            SectionLabel(label)
        } trailing: {
            Text(formatClock(ms))
                .textStyle(.inline(22, color: low ? Color(hex: 0x8A2C1C) : active ? Theme.accent700 : Theme.text, tabularNumbers: true))
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(active ? Theme.accent : .clear).frame(height: 2)
                }
                .accessibilityIdentifier("play-clock-\(label.lowercased())")
        }
    }

    // MARK: Captured

    private var capturedCard: some View {
        let g = boot.controller.game
        return Card(style: .inline) {
            SectionLabel("Captured")
            capturedRow("by White", types: g.capturedBy(.white), dark: false)
            capturedRow("by Black", types: g.capturedBy(.black), dark: true)
        }
    }

    private func capturedRow(_ label: String, types: [PieceType], dark: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .textStyle(.inline(12, color: Theme.neutral500))
                .frame(width: 64, alignment: .leading)
            if types.isEmpty {
                Text("—").foregroundStyle(Theme.neutral400)
            } else {
                capturedChip(types, dark: dark)
            }
        }
        .frame(minHeight: 26, alignment: .leading)
    }

    /// `chip(content, dark)`: 30px glyphs on a wood plate (240px texture under a light or dark
    /// gradient), padding 4 × 10, radius 4; white-styled pieces on the dark chip.
    private func capturedChip(_ types: [PieceType], dark: Bool) -> some View {
        PieceGlyphRun(types: types, style: dark ? .white : .black, fontSize: 30, lineHeight: 1.2)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background {
                ZStack {
                    Image("wood")
                        .resizable()
                        .frame(width: 240, height: 480)
                    LinearGradient(
                        colors: dark
                            ? [Color(r: 40, g: 24, b: 8, a: 0.35), Color(r: 40, g: 24, b: 8, a: 0.40)]
                            : [Color(r: 247, g: 233, b: 206, a: 0.78), Color(r: 241, g: 224, b: 190, a: 0.78)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .accessibilityLabel(types.map { PieceGlyphs.name($0) }.joined(separator: ", "))
    }

    // MARK: Moves

    private var movesCard: some View {
        let g = boot.controller.game
        let startPos = g.positionAt(0)
        let blackFirst = startPos.turn == .black
        let pairCount = Int((Double(g.history.count + (blackFirst ? 1 : 0)) / 2).rounded(.up))
        return Card(style: .inline, gap: 8) {
            SectionLabel("Moves")
            CapHeight(maxHeight: 220) {
                ViewThatFits(in: .vertical) {
                    moveList(startPos: startPos, blackFirst: blackFirst, pairCount: pairCount)
                    ScrollView {
                        moveList(startPos: startPos, blackFirst: blackFirst, pairCount: pairCount)
                    }
                    .defaultScrollAnchor(.bottom)
                }
            }
            .accessibilityElement(children: .contain) // the cells keep their SAN labels
            .accessibilityIdentifier("play-moves")
        }
    }

    private func moveList(startPos: Position, blackFirst: Bool, pairCount: Int) -> some View {
        let g = boot.controller.game
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<pairCount, id: \.self) { i in
                let wPly = blackFirst ? i * 2 - 1 : i * 2
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(startPos.fullmove + i).")
                            .textStyle(.inline(14, color: Theme.neutral500, tabularNumbers: true))
                            .frame(width: 32, alignment: .leading)
                        Group {
                            if wPly >= 0 {
                                moveCell(wPly)
                            } else {
                                Text("…").textStyle(.inline(14, tabularNumbers: true))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        moveCell(wPly + 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                    Rectangle().fill(Theme.neutral200).frame(height: 1)
                }
            }
            if g.history.isEmpty {
                Text("No moves yet — White opens.")
                    .textStyle(.inline(13, color: Theme.neutral500, italic: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `moveCell(ply)`: the SAN with its judgment mark; tapping enters review after that ply.
    @ViewBuilder
    private func moveCell(_ ply: Int) -> some View {
        let controller = boot.controller
        let model = boot.playScreen
        let g = controller.game
        if ply < g.history.count {
            let h = g.history[ply]
            let judgment: Judgment? = controller.analysis.flatMap { ply < $0.count ? $0[ply].judgment : nil }
            let mark = judgment.map(JudgmentStyle.mark) ?? ""
            let current = reviewing && model.reviewPly == ply + 1
            Button {
                model.reviewPly = ply + 1
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(h.san)
                        .textStyle(.inline(14, weight: current ? 600 : 400, color: current ? Theme.accent700 : Theme.text, tabularNumbers: true))
                    if let judgment, !mark.isEmpty {
                        Text(mark)
                            .textStyle(.inline(12, color: JudgmentStyle.color(judgment) ?? Theme.text, tabularNumbers: true))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(h.san)
        } else {
            Text("").textStyle(.inline(14))
        }
    }

    // MARK: Actions

    private var buttonRows: some View {
        let controller = boot.controller
        let model = boot.playScreen
        let g = controller.game
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("New game") { model.newGameSameSettings(boot: boot) }
                    .buttonStyle(.classic(.primary, minHeight: 44))
                    .accessibilityIdentifier("play-new-game")
                Button("Undo") {
                    model.resetLocal()
                    controller.undo()
                }
                .buttonStyle(.classic(.secondary, minHeight: 44))
                .disabled(!controller.takebacksAllowed)
                .accessibilityIdentifier("play-undo")
            }
            if g.status == .active && g.history.count > 0 && !controller.isChallengeGame {
                let hintAllowed = controller.hintsLeft > 0 && controller.humanTurn
                WrapLayout(spacing: 6) {
                    Button("Hint (\(controller.hintsLeft))") {
                        Task { await controller.useHint() }
                    }
                    .buttonStyle(.classic(.ghost, minHeight: 44))
                    .disabled(!hintAllowed)
                    .accessibilityIdentifier("play-hint")
                    Button(g.claimableDraw() != nil ? "Claim draw" : "Offer draw") { controller.offerDraw() }
                        .buttonStyle(.classic(.ghost, minHeight: 44))
                        .accessibilityIdentifier("play-draw")
                    Button("Resign") { controller.resign() }
                        .buttonStyle(.classic(.ghost, minHeight: 44))
                        .accessibilityIdentifier("play-resign")
                }
            }
            if controller.puzzleState == .wrong {
                Button("Try again") { controller.retryPuzzle() }
                    .buttonStyle(.block(.primary))
                    .accessibilityIdentifier("play-retry")
            }
            if g.status == .finished && !model.showGameOver {
                Button("Game summary") { model.showGameOver = true }
                    .buttonStyle(.block(.secondary))
                    .accessibilityIdentifier("play-summary")
            }
        }
    }

    // MARK: Challenge

    private var challengeCard: some View {
        let controller = boot.controller
        let c = controller.challenge ?? ChallengeContext()
        let title = c.puzzle?.title ?? c.drill?.title ?? c.constraint?.title ?? "Find the best move"
        let detail = c.puzzle?.prompt ?? c.drill?.description ?? c.constraint?.description
            ?? (c.mistake != nil ? "From one of your recent games — this time, find the move you missed." : "")
        return Card(style: .inline) {
            SectionLabel(c.isDaily ? "Daily challenge" : "Challenge")
            CardTitle(title)
            Text(detail).textStyle(.inline(13, opacity: 0.8))
            if controller.puzzleState == .solved {
                Tag("Solved · +\(c.puzzle?.xp ?? 15) XP", .accent)
            } else if controller.puzzleState == .wrong {
                Tag("Not quite — try again", .outline)
            }
        }
    }

    // MARK: Review navigation

    private var reviewButtons: some View {
        let model = boot.playScreen
        let g = boot.controller.game
        func step(_ d: Int) {
            model.reviewPly = max(0, min(g.history.count, (model.reviewPly ?? 0) + d))
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("⏮") { step(-1_000_000_000) }
                    .accessibilityLabel("First move")
                    .accessibilityIdentifier("play-review-first")
                Button("◀") { step(-1) }
                    .accessibilityLabel("Previous move")
                    .accessibilityIdentifier("play-review-prev")
                Button("▶") { step(1) }
                    .accessibilityLabel("Next move")
                    .accessibilityIdentifier("play-review-next")
                Button("⏭") { step(1_000_000_000) }
                    .accessibilityLabel("Last move")
                    .accessibilityIdentifier("play-review-last")
            }
            .buttonStyle(.classic(.secondary, minHeight: 44, fill: true))
            Button("Back to game") {
                model.reviewPly = nil
                model.showGameOver = false
            }
            .buttonStyle(.block(.primary))
            .accessibilityIdentifier("play-review-back")
        }
    }
}
