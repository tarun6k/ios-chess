// TS src/app/controller.ts (plus the promise wrappers of src/app/aiClient.ts): one live game — rules,
// clocks, AI, challenges, autosave, and the post-game bookkeeping (facts, player model, background
// analysis, personalised puzzles). Dependencies arrive through protocols: `AIService` (the `AIEngine`
// actor in production, a scripted stand-in in tests), `FeedbackService` (sounds and haptics),
// `ClockTimeSource` (`Date.now()` / `setTimeout` / `setInterval`) and the `AppState` store.
//
// Concurrency: the TS fires promises and guards their late replies with `moveSeq`. Here every AI
// round-trip runs in a tracked `Task` that is cancelled on newGame / resume / undo / resign / dispose;
// the `moveSeq` and `game.status` guards stay as the second line of defence because the engine only
// polls cancellation between search iterations, so a cancelled request can still hand back a reply.
// `subscribe` / `emit` become `@Observable` tracking plus a `revision` counter bumped where the TS emits.

import ChessCore
import Foundation
import Observation

/// TS `ChallengeContext`.
public struct ChallengeContext: Hashable, Sendable {
    public var puzzle: Puzzle?
    public var drill: Drill?
    public var constraint: ConstraintGame?
    public var isDaily: Bool
    /// personalized mistake-replay
    public var mistake: RecordedMistake?

    public init(puzzle: Puzzle? = nil, drill: Drill? = nil, constraint: ConstraintGame? = nil,
                isDaily: Bool = false, mistake: RecordedMistake? = nil) {
        self.puzzle = puzzle
        self.drill = drill
        self.constraint = constraint
        self.isDaily = isDaily
        self.mistake = mistake
    }
}

/// TS `NewGameOptions`.
public struct NewGameOptions: Hashable, Sendable {
    public var mode: GameMode
    /// for vs-AI modes
    public var playerColor: PieceColor?
    public var difficulty: DifficultyMode?
    public var timeControl: TimeControl?
    public var challenge: ChallengeContext?
    public var startFen: String?

    public init(mode: GameMode, playerColor: PieceColor? = nil, difficulty: DifficultyMode? = nil,
                timeControl: TimeControl? = nil, challenge: ChallengeContext? = nil, startFen: String? = nil) {
        self.mode = mode
        self.playerColor = playerColor
        self.difficulty = difficulty
        self.timeControl = timeControl
        self.challenge = challenge
        self.startFen = startFen
    }
}

/// TS `PuzzleState` without its `null` member (the controller stores `PuzzleState?`).
public enum PuzzleState: String, Hashable, Sendable {
    case solving
    case wrong
    case solved
}

/// TS `postGame: { notes, offersReady }`.
public struct PostGame: Hashable, Sendable {
    public var notes: [String]
    public var offersReady: Bool

    public init(notes: [String], offersReady: Bool) {
        self.notes = notes
        self.offersReady = offersReady
    }
}

@Observable @MainActor
public final class GameController {
    public private(set) var game = Game()
    public private(set) var mode: GameMode = .ai
    public private(set) var playerColor: PieceColor = .white
    public private(set) var difficulty: DifficultyMode = .match
    public private(set) var clock: ChessClock? = nil
    public private(set) var timeControl: TimeControl? = nil
    public private(set) var timerOn = false
    public private(set) var plan: AdaptationPlan? = nil
    public private(set) var aiSkill: Double = 8
    public private(set) var aiElo = skillToElo(8)
    public var hintsLeft = 3
    public private(set) var hintMove: Move? = nil
    public private(set) var thinking = false
    public private(set) var challenge: ChallengeContext? = nil
    public private(set) var puzzleState: PuzzleState? = nil
    /// plies the player has to mate (mate-in-N)
    public private(set) var puzzleMovesLeft = 0
    public private(set) var gameOverHandled = false
    public private(set) var postGame: PostGame? = nil
    public private(set) var analysis: [AnalyzedMove]? = nil
    public private(set) var analysisPending = false
    /// `Date.now()` of the last move, on the time source's `nowMs` scale.
    public private(set) var lastMoveAt: Int
    /// Bumped wherever the TS called `emit()`; observe it to be told about every change at once.
    public private(set) var revision = 0
    /// guards stale async AI replies
    @ObservationIgnored private var moveSeq = 0
    /// increments whenever a different game is loaded — UI uses it to reset local state
    public private(set) var gameId = 0

    @ObservationIgnored private let state: AppState
    @ObservationIgnored private let ai: any AIService
    @ObservationIgnored private let feedback: any FeedbackService
    @ObservationIgnored private let time: any ClockTimeSource
    @ObservationIgnored private let random: () -> Double

    // In-flight asynchronous work. Everything but the post-game analysis belongs to the game in
    // progress and is cancelled by `cancelAIWork()`; the analysis belongs to the archived game and
    // survives a new game (as in the TS), but not `dispose()`.
    @ObservationIgnored private var aiTask: Task<Void, Never>? = nil
    @ObservationIgnored private var pacingTimer: ClockTimer? = nil
    @ObservationIgnored private var hintTasks: [Int: Task<HintResponse?, Never>] = [:]
    @ObservationIgnored private var nextHintTaskId = 0
    @ObservationIgnored private var drawTask: Task<Void, Never>? = nil
    @ObservationIgnored private var puzzleCheckTask: Task<Void, Never>? = nil
    @ObservationIgnored private var analysisTask: Task<Void, Never>? = nil
    /// Tracked tasks started and not yet finished (tests wait for this to settle).
    @ObservationIgnored var inflightRequests = 0

    public init(state: AppState, ai: any AIService, feedback: any FeedbackService,
                timeSource: any ClockTimeSource, random: @escaping () -> Double = systemUnitRandom) {
        self.state = state
        self.ai = ai
        self.feedback = feedback
        self.time = timeSource
        self.random = random
        lastMoveAt = timeSource.nowMs
    }

    private func emit() { revision &+= 1 }

    /// `Date.now()` where the TS stores or displays it: Unix milliseconds from the time source's wall clock.
    private var wallMs: Int { Int((time.now.timeIntervalSince1970 * 1000).rounded()) }

    // ── game setup ────────────────────────────────────────────────────────────

    /// Throws `FENError` like `new Game(fen)` when the start FEN is invalid.
    public func newGame(mode: GameMode, playerColor: PieceColor? = nil, difficulty: DifficultyMode? = nil,
                        timeControl: TimeControl? = nil, challenge: ChallengeContext? = nil,
                        startFen: String? = nil) throws {
        try newGame(NewGameOptions(mode: mode, playerColor: playerColor, difficulty: difficulty,
                                   timeControl: timeControl, challenge: challenge, startFen: startFen))
    }

    public func newGame(_ opts: NewGameOptions) throws {
        cancelAIWork()
        moveSeq += 1
        gameId += 1
        clock?.dispose()
        mode = opts.mode
        playerColor = opts.playerColor ?? .white
        difficulty = opts.difficulty ?? state.difficulty
        challenge = opts.challenge
        timeControl = opts.timeControl
        timerOn = opts.timeControl != nil
        hintsLeft = isChallengeGame ? 0 : 3
        hintMove = nil
        thinking = false
        puzzleState = nil
        gameOverHandled = false
        postGame = nil
        analysis = nil
        lastMoveAt = time.nowMs

        var fen = opts.startFen ?? Position.startFEN
        if let puzzle = challenge?.puzzle {
            fen = puzzle.fen
            playerColor = try Position(fen: fen).turn
            puzzleState = .solving
            switch puzzle.kind {
            case .mate1: puzzleMovesLeft = 1
            case .mate2: puzzleMovesLeft = 2
            case .mate3: puzzleMovesLeft = 3
            case .tactic, .defense: puzzleMovesLeft = 1
            }
        } else if let mistake = challenge?.mistake {
            fen = mistake.fen
            playerColor = try Position(fen: fen).turn
            puzzleState = .solving
            puzzleMovesLeft = 1
        } else if let drill = challenge?.drill {
            fen = drill.fen
            playerColor = drill.playerColor
        } else if let constraintFen = challenge?.constraint?.fen {
            fen = constraintFen
        }

        game = try Game(fen: fen)

        // Adaptation plan for AI opponents
        if isVsAi {
            let p = planForGame(state.model, mode: difficulty, aiColor: playerColor.opponent, rng: random)
            plan = p
            aiSkill = p.skill
            aiElo = p.aiElo
            if challenge?.drill != nil || challenge?.puzzle != nil || challenge?.mistake != nil {
                aiSkill = 20 // challenges: the AI defends/replies at full strength
            }
        } else {
            plan = nil
        }

        if let timeControl {
            clock = ChessClock(timeControl, timeSource: time)
            wireClock()
        } else {
            clock = nil
        }

        save()
        emit()
        maybeTriggerAi()
    }

    /// Restores a saved game; false when the FEN or a move no longer replays (the TS `try / catch`).
    /// Like the TS, a failed replay leaves the controller holding the partially replayed game.
    @discardableResult
    public func resume(_ saved: SavedGame) -> Bool {
        cancelAIWork()
        moveSeq += 1
        gameId += 1
        clock?.dispose()
        guard let fresh = try? Game(fen: saved.startFen) else { return false }
        game = fresh
        for uci in saved.uciMoves {
            guard let m = uciToMove(uci) else { return false }
            game.play(m)
        }
        mode = saved.mode
        playerColor = saved.playerColor
        difficulty = saved.difficulty
        timeControl = saved.timeControl
        timerOn = saved.timerOn
        hintsLeft = saved.hintsLeft
        aiSkill = saved.aiSkill
        aiElo = saved.aiElo
        challenge = saved.challengeId.flatMap { challengeById($0) }
        puzzleState = challenge?.puzzle != nil || challenge?.mistake != nil ? .solving : nil
        plan = isVsAi ? planForGame(state.model, mode: difficulty, aiColor: playerColor.opponent, rng: random) : nil
        if plan != nil && !saved.adaptationNotes.isEmpty { plan?.notes = saved.adaptationNotes }
        thinking = false
        gameOverHandled = false
        postGame = nil
        analysis = nil
        if let tc = saved.timeControl, let remaining = saved.clockRemaining {
            let c = ChessClock(tc, timeSource: time)
            c.remaining = ClockRemaining(white: remaining.white, black: remaining.black)
            clock = c
            wireClock()
            if game.status == .active && !game.history.isEmpty {
                c.start(game.turn)
            }
        } else {
            clock = nil
        }
        lastMoveAt = time.nowMs
        emit()
        maybeTriggerAi()
        return true
    }

    private func challengeById(_ id: String) -> ChallengeContext? {
        if let puzzle = puzzles.first(where: { $0.id == id }) { return ChallengeContext(puzzle: puzzle) }
        if let drill = drills.first(where: { $0.id == id }) { return ChallengeContext(drill: drill) }
        if let constraint = constraints.first(where: { $0.id == id }) { return ChallengeContext(constraint: constraint) }
        return nil
    }

    public var isVsAi: Bool { mode != .pvp }

    public var isChallengeGame: Bool {
        challenge?.puzzle != nil || challenge?.drill != nil || challenge?.constraint != nil || challenge?.mistake != nil
    }

    public var takebacksAllowed: Bool {
        state.settings.takebacks && !isChallengeGame && !timerOn && !game.history.isEmpty
    }

    // ── clocks ────────────────────────────────────────────────────────────────

    private func wireClock() {
        guard let clock else { return }
        clock.onTick = { [weak self] in self?.emit() }
        clock.onLowTime = { [weak self] c in
            guard let self else { return }
            if c == playerColor || mode == .pvp {
                feedback.play(.lowTime)
                feedback.trigger(.warning)
            }
            emit()
        }
        clock.onFlag = { [weak self] c in
            guard let self else { return }
            game.timeout(c)
            onGameEnd()
            emit()
        }
    }

    /// Only meaningful before the game starts or for display; a running timed game cannot be un-timed
    /// (that would be cheating the challenge).
    public func setTimerOn(_ on: Bool) {
        if game.history.isEmpty {
            timerOn = on
            if !on {
                clock?.dispose()
                clock = nil
                timeControl = nil
            }
            save()
        }
        emit()
    }

    // ── moves ─────────────────────────────────────────────────────────────────

    public func uciToMove(_ uci: String) -> Move? {
        game.position.generateLegalMoves().first { $0.uci == uci }
    }

    /// Is it the human's turn (for input gating)?
    public var humanTurn: Bool {
        if game.status != .active { return false }
        if mode == .pvp { return true }
        return game.turn == playerColor
    }

    public func legalTargetsFrom(_ sq: Int) -> [Move] {
        game.position.legalMoves(from: sq)
    }

    /// Constraint gating for the player's own rules (silent queen).
    public func moveAllowedByConstraint(_ m: Move) -> Bool {
        if challenge?.constraint?.kind == .silentQueen &&
            game.turn == playerColor &&
            game.position.board[m.from].type == .queen {
            return false
        }
        return true
    }

    /// Play a (already validated legal) move for whoever's turn it is.
    @discardableResult
    public func playMove(_ m: Move) -> Bool {
        if game.status != .active { return false }
        let mover = game.turn
        let isEp = m.flags.contains(.enPassant)
        let isCapture = !game.position.board[m.to].isEmpty || isEp
        let promo = m.promotion
        let castle = !m.flags.intersection([.castleKingside, .castleQueenside]).isEmpty
        let thinkMs = time.nowMs - lastMoveAt

        guard let san = game.play(m, clockMs: clock?.remaining[mover], thinkMs: thinkMs) else { return false }
        moveSeq += 1
        lastMoveAt = time.nowMs
        hintMove = nil

        // feedback
        if game.result?.kind == .checkmate { /* end sound below */ }
        else if san.contains("+") { feedback.play(.check) }
        else if promo != .empty { feedback.play(.promote) }
        else if castle { feedback.play(.castle) }
        else if isCapture { feedback.play(.capture) }
        else { feedback.play(.move) }
        feedback.trigger(isCapture ? .medium : .light)

        // progression counters
        if mover == playerColor || mode == .pvp {
            if isEp { state.progress.counters.enPassants += 1 }
            if promo != .empty && promo != .queen { state.progress.counters.underpromotions += 1 }
        }

        // clock press
        let nowFinished = game.result != nil
        if let clock, !nowFinished {
            if game.history.count == 1 { clock.start(game.turn) } else { clock.press(mover) }
        }

        // puzzle validation
        if puzzleState == .solving && mover == playerColor {
            validatePuzzleMove(m)
        }

        save()

        if nowFinished {
            clock?.pause()
            onGameEnd()
        } else {
            maybeTriggerAi()
        }
        emit()
        return true
    }

    // ── AI ────────────────────────────────────────────────────────────────────

    private func historyKeys() -> [String] {
        [game.positionAt(0).hashKey] + game.history.map(\.key)
    }

    /// Runs `body` as a main-actor task counted in `inflightRequests`.
    private func track<T: Sendable>(_ body: @escaping @MainActor () async -> T) -> Task<T, Never> {
        inflightRequests += 1
        return Task { @MainActor [weak self] in
            let value = await body()
            self?.inflightRequests -= 1
            return value
        }
    }

    /// Cancels every request that belongs to the game in progress (not the post-game analysis).
    private func cancelAIWork() {
        aiTask?.cancel()
        aiTask = nil
        pacingTimer?.cancel()
        pacingTimer = nil
        for task in hintTasks.values { task.cancel() }
        hintTasks.removeAll()
        drawTask?.cancel()
        drawTask = nil
        puzzleCheckTask?.cancel()
        puzzleCheckTask = nil
    }

    /// Leaving the game for good: cancels all AI work, including a pending analysis, and stops the clock.
    public func dispose() {
        cancelAIWork()
        analysisTask?.cancel()
        analysisTask = nil
        clock?.dispose()
    }

    public func maybeTriggerAi() {
        if !isVsAi || game.status != .active { return }
        if game.turn == playerColor { return }
        let seq = moveSeq
        thinking = true
        emit()

        let persona = personaForSkill(aiSkill, moveTimeMs: 0)
        // Move-time cap: quick at low depth; scale with clock pressure if timed.
        var moveTimeMs = Double(900 + persona.maxDepth * 300)
        if let clock {
            let mine = Double(clock.remaining[game.turn])
            moveTimeMs = min(moveTimeMs, max(150, mine / 40))
        }

        let sans = game.sanLine()
        let bookUci = plan != nil && !isChallengeGame ? bookMoveUci(sans) : nil

        // Humanlike pacing: don't answer instantly
        let started = time.nowMs
        let request = MoveRequest(
            fen: game.position.fen,
            historyKeys: historyKeys(),
            skill: challenge?.drill != nil ? 20 : aiSkill,
            moveTimeMs: moveTimeMs,
            params: plan?.params,
            bookMove: bookUci
        )
        aiTask?.cancel()
        pacingTimer?.cancel()
        pacingTimer = nil
        let ai = self.ai
        aiTask = track { [weak self] in
            do {
                let res = try await ai.move(request)
                guard let self, !Task.isCancelled, seq == moveSeq, game.status == .active else { return }
                let delay = max(0, 450 - (time.nowMs - started))
                pacingTimer = time.schedule(afterMs: delay) { [weak self] in
                    guard let self, seq == moveSeq, game.status == .active else { return }
                    pacingTimer = nil
                    thinking = false
                    if let m = uciToMove(res.uci) { playMove(m) } else { emit() }
                }
            } catch is CancellationError {
                // The reply is no longer wanted (new game, undo, resign or dispose).
            } catch {
                guard let self, !Task.isCancelled, seq == moveSeq else { return }
                // Failsafe: play any legal move rather than stalling the game.
                thinking = false
                if let first = game.legalMoves().first { playMove(first) }
            }
        }
    }

    private func bookMoveUci(_ sans: [String]) -> String? {
        guard let plan, game.startFEN == Position.startFEN else { return nil }
        guard let bookSan = pickBookMove(sans, plan: plan, rng: random) else { return nil }
        guard var g2 = try? Game(fen: game.startFEN) else { return nil }
        for s in sans { g2.playSAN(s) }
        let before = g2.history.count
        if g2.playSAN(bookSan) == nil { return nil }
        return g2.history[before].move.uci
    }

    // ── puzzle flow ───────────────────────────────────────────────────────────

    private func validatePuzzleMove(_ m: Move) {
        let p = challenge?.puzzle
        let uci = m.uci

        if let mistake = challenge?.mistake {
            if uci == mistake.bestUci { puzzleSolved() } else { puzzleWrong() }
            return
        }
        guard let p else { return }

        if p.kind == .tactic || p.kind == .defense {
            if uci == p.solution { puzzleSolved() } else { puzzleWrong() }
            return
        }

        // mate-in-N: any move keeping the forced mate within budget is correct.
        puzzleMovesLeft -= 1
        if game.result?.kind == .checkmate { puzzleSolved(); return }
        if puzzleMovesLeft <= 0 { puzzleWrong(); return }
        // ask the engine whether mate is still forced (opponent to move, getting mated)
        let request = HintRequest(fen: game.position.fen, historyKeys: historyKeys())
        let ai = self.ai
        puzzleCheckTask?.cancel()
        puzzleCheckTask = track { [weak self] in
            guard let res = try? await ai.hint(request) else { return }
            guard let self, !Task.isCancelled else { return }
            // score is from the OPPONENT's POV: a forced mate against them is a big negative
            if res.score < -90_000 {
                // still winning — let the AI defend and continue
            } else {
                puzzleWrong()
                emit()
            }
        }
    }

    private func puzzleSolved() {
        puzzleState = .solved
        feedback.trigger(.success)
        feedback.play(.gameWin)
        let p = challenge?.puzzle
        if let p, !state.progress.solvedPuzzles.contains(p.id) {
            state.progress.solvedPuzzles.append(p.id)
            state.progress.xp += p.xp
        } else if challenge?.mistake != nil {
            state.progress.xp += 15
        }
        state.progress.counters.puzzlesSolved += 1
        if challenge?.isDaily == true { completeDaily(&state.progress, now: time.now) }
        _ = refreshBadges(&state.progress, state.model)
        state.persist(.progress)
        state.saved = nil
        state.persist(.saved)
        emit()
    }

    private func puzzleWrong() {
        puzzleState = .wrong
        feedback.play(.error)
        feedback.trigger(.warning)
        emit()
    }

    /// Restarts the current puzzle or mistake replay (their FENs came from the catalogue, so this cannot throw).
    public func retryPuzzle() {
        guard let challenge, challenge.puzzle != nil || challenge.mistake != nil else { return }
        try? newGame(NewGameOptions(mode: .puzzle, challenge: challenge))
    }

    // ── player actions ────────────────────────────────────────────────────────

    public func undo() {
        if !takebacksAllowed { return }
        cancelAIWork()
        moveSeq += 1
        thinking = false
        // vs AI: undo the AI's reply too, back to the player's turn
        let n = isVsAi && game.turn == playerColor && game.history.count >= 2 ? 2 : 1
        for _ in 0..<n { game.undo() }
        hintMove = nil
        save()
        emit()
        maybeTriggerAi()
    }

    public func resign() {
        if game.status != .active { return }
        cancelAIWork()
        let resigner = mode == .pvp ? game.turn : playerColor
        game.resign(resigner)
        clock?.pause()
        onGameEnd()
        emit()
    }

    public func offerDraw() {
        if game.status != .active { return }
        let offerer = mode == .pvp ? game.turn : playerColor
        // claimable draws happen immediately
        if game.claimableDraw() != nil {
            game.claimDraw()
            clock?.pause()
            onGameEnd()
            emit()
            return
        }
        game.offerDraw(offerer)
        if isVsAi {
            // AI decides: accept when clearly worse or dead-drawn late game.
            let seq = moveSeq
            let request = HintRequest(fen: game.position.fen, historyKeys: historyKeys())
            let ai = self.ai
            drawTask?.cancel()
            drawTask = track { [weak self] in
                guard let res = try? await ai.hint(request) else { return }
                guard let self, !Task.isCancelled, seq == moveSeq, game.status == .active else { return }
                // res.score is from the side to move's POV
                let aiToMove = game.turn != playerColor
                let aiScore = aiToMove ? res.score : -res.score
                let lateEven = game.history.count > 60 && abs(aiScore) < 40
                if aiScore < -180 || lateEven {
                    game.acceptDraw()
                    clock?.pause()
                    onGameEnd()
                } else {
                    game.declineDraw()
                }
                emit()
            }
        }
        emit()
    }

    /// pass-and-play: the other player accepts
    public func acceptDraw() {
        if game.acceptDraw() {
            clock?.pause()
            onGameEnd()
        }
        emit()
    }

    public func declineDraw() {
        game.declineDraw()
        emit()
    }

    public func useHint() async {
        if hintsLeft <= 0 || !humanTurn { return }
        hintsLeft -= 1
        state.progress.counters.hintsUsed += 1
        state.persist(.progress)
        let seq = moveSeq
        let request = HintRequest(fen: game.position.fen, historyKeys: historyKeys())
        let ai = self.ai
        let id = nextHintTaskId
        nextHintTaskId += 1
        let task = track { try? await ai.hint(request) }
        hintTasks[id] = task
        let res = await task.value
        hintTasks[id] = nil
        // A failed or cancelled request leaves the hint unanswered (the TS promise simply rejected).
        guard let res, seq == moveSeq else { return }
        hintMove = uciToMove(res.uci)
        save()
        emit()
    }

    // ── endgame bookkeeping ───────────────────────────────────────────────────

    private func onGameEnd() {
        if gameOverHandled { return }
        guard let result = game.result else { return }
        gameOverHandled = true
        let playerWon = result.winner == playerColor
        let drew = result.winner == nil

        // end feedback
        if mode == .pvp { feedback.play(.gameDraw) }
        else if playerWon { feedback.play(.gameWin); feedback.trigger(.success) }
        else if drew { feedback.play(.gameDraw) }
        else { feedback.play(.gameLoss); feedback.trigger(.warning) }

        // Challenge outcomes
        if let d = challenge?.drill {
            let ok = d.goal == .win ? playerWon : (playerWon || drew)
            if ok && !state.progress.completedDrills.contains(d.id) {
                state.progress.completedDrills.append(d.id)
                state.progress.xp += d.xp
            }
        }
        if let c = challenge?.constraint {
            var ok = false
            switch c.kind {
            case .silentQueen:
                ok = playerWon
            case .knightMate:
                let last = game.history.last
                ok = playerWon && result.kind == .checkmate && (last?.san.hasPrefix("N") ?? false)
            case .rookOdds:
                let survived = game.history.count >= 40
                ok = survived && !(result.kind == .checkmate && result.winner != playerColor)
            }
            if ok && !state.progress.completedConstraints.contains(c.id) {
                state.progress.completedConstraints.append(c.id)
                state.progress.xp += c.xp
            }
        }

        // Stats + model for real games (not puzzles)
        if challenge?.puzzle == nil && challenge?.mistake == nil {
            state.progress.counters.gamesPlayed += 1
            if mode == .pvp || playerWon {
                if playerWon { state.progress.counters.gamesWon += 1 }
            }
            if playerWon && result.kind == .checkmate { state.progress.counters.checkmates += 1 }
            if playerWon && result.kind == .timeout { state.progress.counters.winsOnTime += 1 }
            let startTurn = game.positionAt(0).turn
            let castled = game.history.enumerated().contains { i, h in
                let moverIsPlayer = (i % 2 == 0) == (startTurn == playerColor)
                return moverIsPlayer && (h.san == "O-O" || h.san == "O-O-O")
            }
            state.progress.counters.castledGames = castled ? state.progress.counters.castledGames + 1 : 0

            if isVsAi && mode == .ai {
                // rating + model update; giant-slayer badge check
                if playerWon && aiElo >= state.model.rating + 200 && !state.progress.badges.contains("giant-slayer") {
                    state.progress.badges.append("giant-slayer")
                }
                updateModelAfterGame(&state.model, game: game, playerColor: playerColor, analysis: nil,
                                     vsAI: true, aiElo: aiElo, now: wallMs)
                if let plan {
                    state.model.lastAdaptation = plan.notes
                    postGame = PostGame(notes: plan.notes, offersReady: true)
                }
                state.progress.xp += playerWon ? 40 : drew ? 20 : 10
                state.persist(.model)
                // background analysis → weakness profiling + mistake recording
                runPostGameAnalysis()
            }
            _ = refreshBadges(&state.progress, state.model)
            state.persist(.progress)
            archiveGame()
        }

        state.saved = nil
        state.persist(.saved)
    }

    private func runPostGameAnalysis() {
        if analysisPending || game.history.count < 4 { return }
        analysisPending = true
        let startFen = game.startFEN
        let uciMoves = game.uciLine()
        let gameRef = game
        let playerColor = self.playerColor
        let request = AnalyzeRequest(startFEN: startFen, uciMoves: uciMoves, perMoveMs: 250)
        let ai = self.ai
        analysisTask = track { [weak self] in
            let outcome: Result<AnalyzeResponse, any Error>
            do { outcome = .success(try await ai.analyze(request)) } catch { outcome = .failure(error) }
            guard let self else { return }
            guard case .success(let res) = outcome else {
                analysisPending = false
                return
            }
            analysisPending = false
            analysis = res.moves
            // fold weaknesses + accuracy into the model (the game itself was already
            // tallied in onGameEnd — here we only add what analysis reveals)
            let weak = extractWeaknesses(gameRef, playerColor: playerColor, analysis: res.moves)
            for (k, v) in weak {
                state.model.weaknesses[k] += v
            }
            let startTurn = gameRef.positionAt(0).turn
            let playerMoves = res.moves.enumerated()
                .filter { ply, _ in (ply % 2 == 0 ? startTurn : startTurn.opponent) == playerColor }
                .map(\.element)
            if !playerMoves.isEmpty {
                let cpLoss = Double(playerMoves.reduce(0) { $0 + $1.cpLoss }) / Double(playerMoves.count)
                let avg = state.model.features.avgCpLoss
                state.model.features.avgCpLoss = avg != 0 ? avg * 0.8 + cpLoss * 0.2 : cpLoss
            }
            state.persist(.model)
            // record big mistakes for personalized challenges
            var mistakes: [RecordedMistake] = []
            var pos = gameRef.positionAt(0)
            for (ply, a) in res.moves.enumerated() {
                if pos.turn == playerColor && a.cpLoss >= 200 && a.bestUci != a.uci {
                    mistakes.append(RecordedMistake(
                        fen: pos.fen, playedUci: a.uci, bestUci: a.bestUci,
                        cpLoss: a.cpLoss, date: wallMs, playerColor: playerColor
                    ))
                }
                if ply < gameRef.history.count { pos.makeMove(gameRef.history[ply].move) }
            }
            if !mistakes.isEmpty { state.recordMistakes(Array(mistakes.prefix(5))) }
            // attach analysis to the newest archive entry
            if let newest = state.archive.first, newest.uciMoves.joined(separator: " ") == uciMoves.joined(separator: " ") {
                state.archive[0].analysis = res.moves
                state.persist(.archive)
            }
            emit()
        }
    }

    private func archiveGame() {
        let now = time.now
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let date = "\(parts.year ?? 0).\(pad2(parts.month ?? 0)).\(pad2(parts.day ?? 0))"
        let aiName = "AI (\(aiElo))"
        let entry = ArchivedGame(
            pgn: toPGN(game, headers: [
                "White": mode == .pvp ? "White" : playerColor == .white ? "You" : aiName,
                "Black": mode == .pvp ? "Black" : playerColor == .black ? "You" : aiName,
                "Date": date,
            ]),
            mode: mode,
            playerColor: playerColor,
            result: game.result?.message ?? "",
            score: game.result?.score ?? "*",
            aiElo: isVsAi ? aiElo : nil,
            date: wallMs,
            analysis: nil,
            adaptationNotes: plan?.notes ?? [],
            startFen: game.startFEN,
            uciMoves: game.uciLine()
        )
        state.archive.insert(entry, at: 0)
        if state.archive.count > 100 { state.archive.removeLast(state.archive.count - 100) }
        state.persist(.archive)
    }

    // ── persistence ───────────────────────────────────────────────────────────

    public func save() {
        if game.status == .finished || puzzleState == .solved {
            state.saved = nil
        } else {
            state.saved = SavedGame(
                mode: mode,
                startFen: game.startFEN,
                uciMoves: game.uciLine(),
                thinkMs: game.history.map { $0.thinkMs ?? 0 },
                playerColor: playerColor,
                difficulty: difficulty,
                timeControl: timeControl,
                clockRemaining: clock.map { ClockRemaining(white: $0.remaining.white, black: $0.remaining.black) },
                timerOn: timerOn,
                hintsLeft: hintsLeft,
                challengeId: challenge?.puzzle?.id ?? challenge?.drill?.id ?? challenge?.constraint?.id,
                adaptationNotes: plan?.notes ?? [],
                aiSkill: aiSkill,
                aiElo: aiElo,
                savedAt: wallMs
            )
        }
        state.persist(.saved)
    }
}

/// `String(n).padStart(2, '0')`.
private func pad2(_ n: Int) -> String {
    n < 10 ? "0\(n)" : "\(n)"
}
