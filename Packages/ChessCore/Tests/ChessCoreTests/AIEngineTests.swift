import Foundation
import os
import Testing
@testable import ChessCore

// worker.ts handlers (move / hint / analyze / judge) through the AIEngine actor.

@Suite("AI engine")
struct AIEngineTests {
    let fx = AIFixtures.shared
    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    /// A depth-8 search from here took the TS 19 M nodes.
    static let deepFEN = "rnb1kbnr/pppp1ppp/8/4p3/4P1q1/5P2/PPPP2PP/RNBQKBNR b KQkq - 0 3"

    @Test("analyze reproduces the TS post-game analysis", arguments: AIFixtures.shared.analyze)
    func analyzeParity(_ c: AIFixtures.AnalyzeCase) async throws {
        let engine = AIEngine()
        let res = try await engine.analyze(AnalyzeRequest(startFEN: c.startFen, uciMoves: c.uciMoves, perMoveMs: unlimitedMoveTime))
        #expect(res.moves == c.moves)
    }

    /// All four fixture games in release. At -Onone the Opera and King's Gambit analyses take 70–95 s each
    /// (TS: 16 s / 12 s under Node), so the debug suite only runs the two short ones; `swift test -c release`
    /// is the parity check.
    static var analysisGames: [AdaptationFixtures.GameCase] {
        #if DEBUG
        AdaptationFixtures.shared.games.filter { $0.id == "scholars" || $0.id == "rook-endgame" }
        #else
        AdaptationFixtures.shared.games
        #endif
    }

    @Test("analyze judges the fixture games like the TS", arguments: analysisGames)
    func analyzeGames(_ c: AdaptationFixtures.GameCase) async throws {
        let game = try AdaptationFixtures.shared.build(c)
        let engine = AIEngine()
        let clock = ContinuousClock()
        let started = clock.now
        let res = try await engine.analyze(AnalyzeRequest(startFEN: c.startFen, uciMoves: game.uciLine(), perMoveMs: unlimitedMoveTime))
        print("analysis \(c.id): \(game.history.count) plies in \((clock.now - started).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))")
        #expect(res.moves == c.analysis)
        #expect(res.moves.map(\.judgment) == c.analysis.map(\.judgment))
        for m in res.moves {
            #expect(m.judgment == AIEngine.judge(cpLoss: m.cpLoss, isBest: m.bestUci == m.uci))
        }
    }

    @Test("analyze rejects an illegal move with the TS message")
    func analyzeIllegal() async throws {
        let engine = AIEngine()
        let err = await #expect(throws: AIEngineError.self) {
            try await engine.analyze(AnalyzeRequest(startFEN: Self.startFEN, uciMoves: ["e2e4", "e7e5", "e2e5"], perMoveMs: unlimitedMoveTime))
        }
        #expect(err == .illegalMoveInLine("e2e5"))
        #expect(err?.description == "illegal move in line: e2e5")
        #expect(AIEngineError.noLegalMoves.description == "no legal moves")
    }

    @Test("analyze defaults to the aiClient.ts budget of 350 ms per move")
    func analyzeDefaultBudget() {
        #expect(AnalyzeRequest(startFEN: Self.startFEN, uciMoves: []).perMoveMs == 350)
    }

    @Test("judge thresholds")
    func judge() {
        #expect(AIEngine.judge(cpLoss: 0, isBest: true) == .best)
        #expect(AIEngine.judge(cpLoss: 300, isBest: true) == .best)
        #expect(AIEngine.judge(cpLoss: 0, isBest: false) == .good)
        #expect(AIEngine.judge(cpLoss: 49, isBest: false) == .good)
        #expect(AIEngine.judge(cpLoss: 50, isBest: false) == .inaccuracy)
        #expect(AIEngine.judge(cpLoss: 119, isBest: false) == .inaccuracy)
        #expect(AIEngine.judge(cpLoss: 120, isBest: false) == .mistake)
        #expect(AIEngine.judge(cpLoss: 249, isBest: false) == .mistake)
        #expect(AIEngine.judge(cpLoss: 250, isBest: false) == .blunder)
        #expect(Judgment.allCases == [.best, .good, .inaccuracy, .mistake, .blunder])
    }

    @Test("a legal book move bypasses the search")
    func bookMove() async throws {
        let engine = AIEngine()
        let res = try await engine.move(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 10, moveTimeMs: 1000, bookMove: "e2e4"))
        #expect(res == MoveResponse(uci: "e2e4", score: 0, depth: 0, nodes: 0, choiceIndex: 0, bestUci: "e2e4"))
    }

    @Test("an illegal book move falls through to the search")
    func illegalBookMove() async throws {
        let engine = AIEngine(random: { 0.99 })
        let res = try await engine.move(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 20, moveTimeMs: 300, bookMove: "e2e5"))
        #expect(res.depth >= 1)
        #expect(res.nodes > 0)
        #expect(AIEngine.uciToMove(Position(), res.uci) != nil)
        #expect(res.choiceIndex == 0) // skill 20 has no noise
        #expect(res.uci == res.bestUci)
    }

    @Test("move request: persona depth, exact scores and deterministic choice")
    func moveDeterministic() async throws {
        // skill 8 → depth 4; a constant RNG of 0.99 never opens the blunder window and adds the
        // same noise to every candidate, so the engine best (b1c3, from the depth-4 fixture) is chosen.
        let c = try #require(fx.searches.first { $0.fen == Self.startFEN && $0.maxDepth == 4 && $0.historyKeys.isEmpty })
        let engine = AIEngine(random: { 0.99 })
        let res = try await engine.move(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 8, moveTimeMs: unlimitedMoveTime))
        #expect(personaForSkill(8, moveTimeMs: 0).maxDepth == 4)
        #expect(res.uci == c.result.best)
        #expect(res.bestUci == c.result.best)
        #expect(res.score == c.result.score)
        #expect(res.depth == c.result.depth)
        #expect(res.nodes == c.result.nodes)
        #expect(res.choiceIndex == 0)
    }

    @Test("move request with a low-skill persona picks within the loss bound and reports the index")
    func moveLowSkill() async throws {
        // The engine's RNG must be @Sendable; feed it from a locked box.
        let box = LockedLCG(TestLCG(seed: 3))
        var s = Search()
        let reference = s.search(try Position(fen: Self.startFEN), options: SearchOptions(maxDepth: 2, moveTimeMs: unlimitedMoveTime))
        var indices = Set<Int>()
        for _ in 0..<20 {
            // A fresh engine each time: a warm transposition table would change the root scores.
            let engine = AIEngine(random: { box.next() })
            let res = try await engine.move(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 0, moveTimeMs: unlimitedMoveTime))
            #expect(res.depth == 2)
            #expect(res.bestUci == reference.best?.uci)
            let chosen = try #require(reference.rootMoves.first { $0.move.uci == res.uci })
            #expect(res.score == chosen.score)
            #expect(reference.score - chosen.score <= 320)
            #expect(res.choiceIndex < reference.rootMoves.count)
            indices.insert(res.choiceIndex)
        }
        #expect(indices.count > 1) // skill 0 (noise 220cp) does not always play the engine move
    }

    @Test("move / hint on a finished game report no legal moves")
    func noLegalMoves() async throws {
        let engine = AIEngine()
        for c in fx.terminal {
            await #expect(throws: AIEngineError.noLegalMoves) {
                try await engine.move(MoveRequest(fen: c.fen, historyKeys: [], skill: 10, moveTimeMs: 100))
            }
            await #expect(throws: AIEngineError.noLegalMoves) {
                try await engine.hint(HintRequest(fen: c.fen, historyKeys: []))
            }
        }
        await #expect(throws: FENError.self) {
            try await engine.move(MoveRequest(fen: "not a fen", historyKeys: [], skill: 10, moveTimeMs: 100))
        }
    }

    @Test("hint finds the mate and reports the mover's score")
    func hint() async throws {
        let engine = AIEngine()
        let res = try await engine.hint(HintRequest(fen: "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", historyKeys: []))
        #expect(res.uci == "a1a8")
        #expect(res.score == mateScore - 1)
        // controller.ts treats a hint below -90_000 as "the puzzle is lost": Black in check, Kh8 forced, then Qf8#/Qg7#.
        let lost = try await engine.hint(HintRequest(fen: "6k1/5Q2/6K1/8/8/8/8/8 b - - 0 1", historyKeys: []))
        #expect(lost.uci == "g8h8")
        #expect(lost.score == -(mateScore - 2))
        #expect(lost.score < -90_000)
    }

    @Test("the engine works off the main thread even when called from the main actor")
    @MainActor
    func offMainThread() async throws {
        let sawMainThread = OSAllocatedUnfairLock(initialState: (calls: 0, onMain: false))
        // skill 0 consults the RNG in chooseMove, which runs on the actor's executor.
        let engine = AIEngine(random: {
            sawMainThread.withLock { $0.calls += 1; $0.onMain = $0.onMain || Thread.isMainThread }
            return 0.5
        })
        _ = try await engine.move(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 0, moveTimeMs: unlimitedMoveTime))
        let seen = sawMainThread.withLock { $0 }
        #expect(seen.calls > 0)
        #expect(!seen.onMain)
    }

    @Test("a stopped search throws CancellationError instead of a partial result")
    func cancelledFlag() async throws {
        let engine = AIEngine()
        await #expect(throws: CancellationError.self) {
            try await engine.handleMove(
                MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 20, moveTimeMs: unlimitedMoveTime),
                isCancelled: { true }
            )
        }
        await #expect(throws: CancellationError.self) {
            try await engine.handleHint(HintRequest(fen: Self.startFEN, historyKeys: []), isCancelled: { true })
        }
        await #expect(throws: CancellationError.self) {
            try await engine.handleAnalyze(
                AnalyzeRequest(startFEN: Self.startFEN, uciMoves: ["e2e4"], perMoveMs: unlimitedMoveTime), isCancelled: { true }
            )
        }
    }

    /// Wraps `Task.isCancelled` so a test can count how often the engine polled it, and how many of those
    /// polls happened after the cancellation.
    final class PollCounter: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (total: 0, cancelled: 0))
        var total: Int { state.withLock { $0.total } }
        var cancelled: Int { state.withLock { $0.cancelled } }

        func poll() -> Bool {
            let c = Task.isCancelled
            state.withLock {
                $0.total += 1
                if c { $0.cancelled += 1 }
            }
            return c
        }
    }

    @Test("cancelling the awaiting Task stops a long move search at the next poll")
    func taskCancellation() async throws {
        let engine = AIEngine()
        // A depth-8 search from deepFEN would run for many seconds; the cancelled Task throws instead.
        let request = MoveRequest(fen: Self.deepFEN, historyKeys: [], skill: 20, moveTimeMs: unlimitedMoveTime)
        let task = Task { try await engine.move(request) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        // The same request with the poll observed: after the cancellation the search polls exactly once
        // more (its 2048-node check throws TimeUp and the iteration is abandoned) and handleMove once
        // (which throws) — no further work happens, whatever the thread scheduling.
        let polls = PollCounter()
        let observed = Task { try await engine.handleMove(request, isCancelled: { polls.poll() }) }
        try await Task.sleep(for: .milliseconds(150))
        observed.cancel()
        await #expect(throws: CancellationError.self) { try await observed.value }
        #expect(polls.total >= 2)
        #expect(polls.cancelled == 2)

        // The engine is still usable afterwards.
        let res = try await engine.move(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 3, moveTimeMs: unlimitedMoveTime))
        #expect(res.depth == 3)
    }

    @Test("cancelling the awaiting Task stops a long analysis at the next poll")
    func analyzeCancellation() async throws {
        let engine = AIEngine()
        let opera = try #require(AdaptationFixtures.shared.game("opera"))
        let game = try AdaptationFixtures.shared.build(opera)
        let request = AnalyzeRequest(startFEN: opera.startFen, uciMoves: game.uciLine(), perMoveMs: unlimitedMoveTime)
        let task = Task { try await engine.analyze(request) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        // One poll inside the running search (TimeUp), one in handleAnalyze after it (the throw).
        let polls = PollCounter()
        let observed = Task { try await engine.handleAnalyze(request, isCancelled: { polls.poll() }) }
        try await Task.sleep(for: .milliseconds(100))
        observed.cancel()
        await #expect(throws: CancellationError.self) { try await observed.value }
        #expect(polls.total >= 2)
        #expect(polls.cancelled == 2)
    }
}

/// A `TestLCG` behind a lock so it can back the engine's `@Sendable` RNG.
final class LockedLCG: Sendable {
    private let state: OSAllocatedUnfairLock<TestLCG>

    init(_ lcg: TestLCG) { state = OSAllocatedUnfairLock(initialState: lcg) }

    func next() -> Double { state.withLock { $0.next() } }
}
