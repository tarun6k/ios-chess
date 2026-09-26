import Testing
@testable import ChessCore

// tests/puzzles.test.ts: every shipped puzzle is engine-verified at depth 8 with an 8 s budget.
// Phase 5 ports the puzzle catalogue itself; until then the FENs come from the fixture (ai-dump.ts
// ran the same search with an unlimited budget and recorded best / score / node count).

@Suite("puzzle validity", .serialized)
struct PuzzleSearchTests {
    @Test("depth-8 verification", arguments: AIFixtures.shared.puzzles)
    func verify(_ p: AIFixtures.PuzzleCase) throws {
        let pos = try Position(fen: p.fen)
        var s = Search()
        let r = s.search(pos, options: SearchOptions(maxDepth: 8, moveTimeMs: 8000))
        let best = try #require(r.rootMoves.first)

        if p.kind.hasPrefix("mate") {
            let n = try #require(Int(p.kind.dropFirst(4)))
            #expect(best.score > mateScore - 1000, "must be a forced mate")
            #expect(mateScore - best.score == 2 * n - 1, "mate distance in plies")
            // the stored solution must also force mate at the same distance
            let sol = try #require(r.rootMoves.first { $0.move.uci == p.solution }, "solution move exists")
            #expect(sol.score == best.score)
        } else {
            let sol = try #require(r.rootMoves.first { $0.move.uci == p.solution }, "solution move exists")
            #expect(best.score - sol.score <= 30, "solution within 30cp of best")
            if p.kind == "tactic" { #expect(sol.score > 100, "tactic clearly favorable") }
            else { #expect(sol.score > -60, "defense survives") }
        }

        // When the search ran to the fixture's depth inside the budget, it must be the TS tree exactly.
        if r.depth == p.depth {
            #expect(r.best?.uci == p.best)
            #expect(r.score == p.bestScore)
            #expect(r.nodes == p.nodes)
            #expect(r.rootMoves.first { $0.move.uci == p.solution }?.score == p.solutionScore)
        } else {
            print("puzzle \(p.id): stopped at depth \(r.depth) after \(r.nodes) nodes (TS depth \(p.depth) took \(p.nodes) nodes)")
        }
    }
}
