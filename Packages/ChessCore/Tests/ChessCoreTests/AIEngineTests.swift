import os
import Testing
@testable import ChessCore

// worker.ts handlers (move / hint / analyze / judge) driven directly.

@Suite("AI engine")
struct AIEngineTests {
    let fx = AIFixtures.shared
    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    @Test("analyze reproduces the TS post-game analysis", arguments: AIFixtures.shared.analyze)
    func analyzeParity(_ c: AIFixtures.AnalyzeCase) throws {
        let engine = AIEngine()
        let res = try engine.handleAnalyze(AnalyzeRequest(startFEN: c.startFen, uciMoves: c.uciMoves, perMoveMs: unlimitedMoveTime))
        #expect(res.moves == c.moves)
    }

    @Test("analyze rejects an illegal move with the TS message")
    func analyzeIllegal() throws {
        let engine = AIEngine()
        let err = #expect(throws: AIEngineError.self) {
            try engine.handleAnalyze(AnalyzeRequest(startFEN: Self.startFEN, uciMoves: ["e2e4", "e7e5", "e2e5"], perMoveMs: unlimitedMoveTime))
        }
        #expect(err == .illegalMoveInLine("e2e5"))
        #expect(err?.description == "illegal move in line: e2e5")
        #expect(AIEngineError.noLegalMoves.description == "no legal moves")
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
    }

    @Test("a legal book move bypasses the search")
    func bookMove() throws {
        let engine = AIEngine()
        let res = try engine.handleMove(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 10, moveTimeMs: 1000, bookMove: "e2e4"))
        #expect(res == MoveResponse(uci: "e2e4", score: 0, depth: 0, nodes: 0, choiceIndex: 0, bestUci: "e2e4"))
    }

    @Test("an illegal book move falls through to the search")
    func illegalBookMove() throws {
        let engine = AIEngine(random: { 0.99 })
        let res = try engine.handleMove(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 20, moveTimeMs: 300, bookMove: "e2e5"))
        #expect(res.depth >= 1)
        #expect(res.nodes > 0)
        #expect(AIEngine.uciToMove(Position(), res.uci) != nil)
        #expect(res.choiceIndex == 0) // skill 20 has no noise
        #expect(res.uci == res.bestUci)
    }

    @Test("move request: persona depth, exact scores and deterministic choice")
    func moveDeterministic() throws {
        // skill 8 → depth 4; a constant RNG of 0.99 never opens the blunder window and adds the
        // same noise to every candidate, so the engine best (b1c3, from the depth-4 fixture) is chosen.
        let c = try #require(fx.searches.first { $0.fen == Self.startFEN && $0.maxDepth == 4 && $0.historyKeys.isEmpty })
        let engine = AIEngine(random: { 0.99 })
        let res = try engine.handleMove(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 8, moveTimeMs: unlimitedMoveTime))
        #expect(personaForSkill(8, moveTimeMs: 0).maxDepth == 4)
        #expect(res.uci == c.result.best)
        #expect(res.bestUci == c.result.best)
        #expect(res.score == c.result.score)
        #expect(res.depth == c.result.depth)
        #expect(res.nodes == c.result.nodes)
        #expect(res.choiceIndex == 0)
    }

    @Test("move request with a low-skill persona picks within the loss bound and reports the index")
    func moveLowSkill() throws {
        // The engine's RNG must be @Sendable; feed it from a locked box.
        let box = LockedLCG(TestLCG(seed: 3))
        var s = Search()
        let reference = s.search(try Position(fen: Self.startFEN), options: SearchOptions(maxDepth: 2, moveTimeMs: unlimitedMoveTime))
        var indices = Set<Int>()
        for _ in 0..<20 {
            // A fresh engine each time: a warm transposition table would change the root scores.
            let engine = AIEngine(random: { box.next() })
            let res = try engine.handleMove(MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 0, moveTimeMs: unlimitedMoveTime))
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
    func noLegalMoves() throws {
        let engine = AIEngine()
        for c in fx.terminal {
            #expect(throws: AIEngineError.noLegalMoves) {
                try engine.handleMove(MoveRequest(fen: c.fen, historyKeys: [], skill: 10, moveTimeMs: 100))
            }
            #expect(throws: AIEngineError.noLegalMoves) {
                try engine.handleHint(HintRequest(fen: c.fen, historyKeys: []))
            }
        }
        #expect(throws: FENError.self) {
            try engine.handleMove(MoveRequest(fen: "not a fen", historyKeys: [], skill: 10, moveTimeMs: 100))
        }
    }

    @Test("hint finds the mate and reports the mover's score")
    func hint() throws {
        let engine = AIEngine()
        let res = try engine.handleHint(HintRequest(fen: "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", historyKeys: []))
        #expect(res.uci == "a1a8")
        #expect(res.score == mateScore - 1)
        // controller.ts treats a hint below -90_000 as "the puzzle is lost": Black in check, Kh8 forced, then Qf8#/Qg7#.
        let lost = try engine.handleHint(HintRequest(fen: "6k1/5Q2/6K1/8/8/8/8/8 b - - 0 1", historyKeys: []))
        #expect(lost.uci == "g8h8")
        #expect(lost.score == -(mateScore - 2))
        #expect(lost.score < -90_000)
    }

    @Test("move requests honour cancellation")
    func cancellation() throws {
        let engine = AIEngine()
        let res = try engine.handleMove(
            MoveRequest(fen: Self.startFEN, historyKeys: [], skill: 20, moveTimeMs: unlimitedMoveTime),
            isCancelled: { true }
        )
        #expect(res.depth == 0)
        #expect(res.nodes == 0)
        #expect(res.uci == Position().generateLegalMoves()[0].uci)
    }
}

/// A `TestLCG` behind a lock so it can back the engine's `@Sendable` RNG.
final class LockedLCG: Sendable {
    private let state: OSAllocatedUnfairLock<TestLCG>

    init(_ lcg: TestLCG) { state = OSAllocatedUnfairLock(initialState: lcg) }

    func next() -> Double { state.withLock { $0.next() } }
}
