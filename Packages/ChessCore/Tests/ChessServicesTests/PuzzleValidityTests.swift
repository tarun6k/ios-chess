import Testing
import ChessCore
@testable import ChessServices

// tests/puzzles.test.ts: every shipped puzzle is engine-verified at depth 8 with an 8 s budget — mates
// are forced in exactly N and the stored solution is (one of) the best moves. Serialized so each search
// gets the whole budget.

@Suite("puzzle catalogue validity", .serialized)
struct PuzzleValidityTests {
    @Test("engine-verified", arguments: puzzles.map(\.id))
    func verify(_ id: String) throws {
        let p = try #require(puzzles.first { $0.id == id })
        let pos = try Position(fen: p.fen)
        var s = Search()
        let r = s.search(pos, options: SearchOptions(maxDepth: 8, moveTimeMs: 8000))
        let best = try #require(r.rootMoves.first)

        if let n = p.kind.mateIn {
            #expect(best.score > mateScore - 1000, "must be a forced mate")
            #expect(mateScore - best.score == 2 * n - 1, "mate distance in plies")
            // the stored solution must also force mate at the same distance
            let sol = try #require(r.rootMoves.first { $0.move.uci == p.solution }, "solution move exists")
            #expect(sol.score == best.score)
        } else {
            let sol = try #require(r.rootMoves.first { $0.move.uci == p.solution }, "solution move exists")
            #expect(best.score - sol.score <= 30, "solution within 30cp of best")
            if p.kind == .tactic { #expect(sol.score > 100, "tactic clearly favorable") }
            else { #expect(sol.score > -60, "defense survives") }
        }
    }

    @Test("drill and constraint FENs load")
    func drillAndConstraintFens() throws {
        for d in drills { _ = try Position(fen: d.fen) }
        for c in constraints {
            if let fen = c.fen { _ = try Position(fen: fen) }
        }
    }
}

@Suite("puzzle catalogue")
struct PuzzleCatalogueTests {
    @Test("ships 15 puzzles, 4 drills and 3 constraint games with unique ids")
    func counts() {
        #expect(puzzles.count == 15 && drills.count == 4 && constraints.count == 3)
        let ids = puzzles.map(\.id) + drills.map(\.id) + constraints.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(puzzles.filter { $0.tier == 1 }.count == 6 && puzzles.filter { $0.tier == 2 }.count == 8 && puzzles.filter { $0.tier == 3 }.count == 1)
    }

    @Test("is identical to the TS data")
    func parity() throws {
        let f = ServicesFixtures.shared
        #expect(puzzles == f.puzzles)
        #expect(drills == f.drills)
        #expect(constraints == f.constraints)

        // …and encodes to the very same JSON (kinds, colours and the optional constraint FEN included).
        let raw = try ServicesFixtures.rawObjects()
        #expect(try canonicalJSON(encoding: puzzles) == canonicalJSON(#require(raw["puzzles"])))
        #expect(try canonicalJSON(encoding: drills) == canonicalJSON(#require(raw["drills"])))
        #expect(try canonicalJSON(encoding: constraints) == canonicalJSON(#require(raw["constraints"])))
    }

    @Test("kinds carry their mate distance")
    func kinds() {
        #expect(PuzzleKind.mate1.mateIn == 1 && PuzzleKind.mate2.mateIn == 2 && PuzzleKind.mate3.mateIn == 3)
        #expect(PuzzleKind.tactic.mateIn == nil && PuzzleKind.defense.mateIn == nil)
        #expect(PuzzleKind.allCases.map(\.rawValue) == ["mate1", "mate2", "mate3", "tactic", "defense"])
    }

    @Test("solutions are legal moves of their positions")
    func solutionsLegal() throws {
        for p in puzzles {
            let pos = try Position(fen: p.fen)
            #expect(pos.generateLegalMoves().contains { $0.uci == p.solution }, "\(p.id)")
        }
    }
}
