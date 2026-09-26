import os
import Testing
@testable import ChessCore

// tests/ai.test.ts `describe('search')` plus fixed-depth parity against the TypeScript search.

@Suite("search")
struct SearchTests {
    let fx = AIFixtures.shared

    @Test("finds mate in 1")
    func mateInOne() throws {
        var s = Search()
        // Back-rank: Ra8#
        let pos = try Position(fen: "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1")
        let r = s.search(pos, options: SearchOptions(maxDepth: 3, moveTimeMs: 3000))
        #expect(r.best?.uci == "a1a8")
        #expect(r.score > mateScore - 1000)
    }

    @Test("finds mate in 2")
    func mateInTwo() throws {
        var s = Search()
        // K+R+R vs K with king cut off.
        let pos = try Position(fen: "7k/R7/1R6/8/8/8/8/4K3 w - - 0 1")
        let r = s.search(pos, options: SearchOptions(maxDepth: 4, moveTimeMs: 5000))
        // Rb8+ (or Ra8+ after Rb7...) — verify search sees forced mate
        #expect(r.score > mateScore - 1000)
    }

    @Test("does not hang the queen at decent skill")
    func queenNotHung() throws {
        var s = Search()
        // Queen attacked by a pawn; must move or be lost for nothing.
        let pos = try Position(fen: "rnb1kbnr/pppp1ppp/8/4p3/4P1q1/5P2/PPPP2PP/RNBQKBNR b KQkq - 0 3")
        let r = s.search(pos, options: SearchOptions(maxDepth: 3, moveTimeMs: 3000))
        let best = try #require(r.best?.uci)
        #expect(best.hasPrefix("g4")) // queen moves away
    }

    @Test("takes a free rook")
    func freeRook() throws {
        var s = Search()
        let pos = try Position(fen: "k7/8/8/3r4/4Q3/8/8/4K3 w - - 0 1")
        let r = s.search(pos, options: SearchOptions(maxDepth: 3, moveTimeMs: 3000))
        #expect(r.best?.uci == "e4d5")
    }

    @Test("root moves are sorted best-first with exact scores near the top")
    func rootMovesSorted() throws {
        var s = Search()
        let pos = try Position(fen: "k7/8/8/3r4/4Q3/8/8/4K3 w - - 0 1")
        let r = s.search(pos, options: SearchOptions(maxDepth: 3, moveTimeMs: 3000))
        for i in 1..<r.rootMoves.count {
            #expect(r.rootMoves[i - 1].score >= r.rootMoves[i].score)
        }
    }

    // MARK: - Parity with the TypeScript search

    @Test("fixed-depth search returns the TS best move, score, node count, root scores and PV",
          arguments: AIFixtures.shared.searches)
    func fixedDepthParity(_ c: AIFixtures.SearchCase) throws {
        var s = Search()
        let pos = try Position(fen: c.fen)
        let r = s.search(pos, options: SearchOptions(
            maxDepth: c.maxDepth, moveTimeMs: unlimitedMoveTime, params: try fx.params(c.params), historyKeys: c.historyKeys
        ))
        let got = r.ucis
        #expect(got.best == c.result.best)
        #expect(r.score == c.result.score)
        #expect(r.depth == c.result.depth)
        #expect(r.nodes == c.result.nodes)
        #expect(got.rootMoves == c.result.rootMoves)
        #expect(got.pv == c.result.pv)
    }

    @Test("the parity set is varied")
    func parityCoverage() {
        #expect(fx.searches.count >= 12)
        #expect(Set(fx.searches.map(\.fen)).count >= 12)
        #expect(fx.searches.contains { $0.params != "neutral" })
        #expect(fx.searches.contains { !$0.historyKeys.isEmpty })
    }

    @Test("stalemate and checkmate return no move, like the TS")
    func terminalPositions() throws {
        for c in fx.terminal {
            var s = Search()
            let r = s.search(try Position(fen: c.fen), options: SearchOptions(maxDepth: 3, moveTimeMs: unlimitedMoveTime))
            #expect(r.best == nil)
            #expect(r.score == c.result.score)
            #expect(r.depth == 0)
            #expect(r.nodes == 0)
            #expect(r.rootMoves.isEmpty)
            #expect(r.pv.isEmpty)
        }
    }

    @Test("repetition awareness: a position repeated in the history is scored as a draw")
    func repetitionDraw() throws {
        // After 1.Nf3 Nf6 2.Ng1 Ng8 3.Nf3 Nf6 4.Ng1 Ng8 the position after Nf3 has occurred twice, so a
        // third Nf3 is a draw by repetition when the game history is supplied.
        var game = Game()
        game.playLine(["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"])
        let keys = [Position().hashKey] + game.history.map(\.key)
        var s = Search()
        let noHistory = s.search(game.position, options: SearchOptions(maxDepth: 3, moveTimeMs: unlimitedMoveTime))
        var s2 = Search()
        let withHistory = s2.search(game.position, options: SearchOptions(maxDepth: 3, moveTimeMs: unlimitedMoveTime, historyKeys: keys))
        #expect(withHistory.rootMoves.first { $0.move.uci == "g1f3" }?.score == 0)
        #expect(noHistory.nodes != withHistory.nodes)

        // 50-move rule: with halfmove 99 and no pawn to move, every child is a draw on entry.
        var s3 = Search()
        let fifty = s3.search(try Position(fen: "k7/8/8/8/8/8/8/1R2K3 w - - 99 60"), options: SearchOptions(maxDepth: 3, moveTimeMs: unlimitedMoveTime))
        #expect(fifty.score == 0)
        #expect(fifty.rootMoves.count == 15)
        #expect(fifty.rootMoves.allSatisfy { $0.score == 0 })
        #expect(fifty.nodes == 3 * fifty.rootMoves.count) // three iterations, one node per root move
    }

    @Test("history keys that are not position keys are ignored")
    func badHistoryKeys() throws {
        let c = fx.searches[0]
        var s = Search()
        let r = s.search(try Position(fen: c.fen), options: SearchOptions(
            maxDepth: c.maxDepth, moveTimeMs: unlimitedMoveTime, historyKeys: ["", "nonsense", "1.2.3", "zz"]
        ))
        #expect(r.nodes == c.result.nodes)
        #expect(Zobrist.hash(fromKey: "nonsense") == nil)
        #expect(Zobrist.hash(fromKey: Position().hashKey) == Position().hash)
    }

    // MARK: - Limits and cancellation

    @Test("a tiny time budget stops at the 50 ms floor of the hard deadline")
    func timeLimit() throws {
        var s = Search()
        let clock = ContinuousClock()
        let start = clock.now
        // deadline = now + max(50, 1) ms; soft stop = now + 0.6 ms, checked only between iterations.
        let r = s.search(Position(), options: SearchOptions(maxDepth: 30, moveTimeMs: 1))
        let elapsed = clock.now - start
        #expect(r.depth >= 1)
        #expect(r.depth < 30)
        #expect(r.best != nil)
        #expect(elapsed < .seconds(1), "\(elapsed)")
    }

    @Test("a cancelled search returns the depth-0 fallback: first legal move, all scores 0")
    func cancelledBeforeStart() throws {
        var s = Search()
        let pos = try Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        let legal = pos.generateLegalMoves()
        let r = s.search(pos, options: SearchOptions(maxDepth: 6, moveTimeMs: unlimitedMoveTime, isCancelled: { true }))
        #expect(r.best == legal[0])
        #expect(r.score == 0)
        #expect(r.depth == 0)
        #expect(r.nodes == 0)
        #expect(r.rootMoves.map(\.move) == legal)
        #expect(r.rootMoves.allSatisfy { $0.score == 0 })
        #expect(r.pv == [legal[0]])
    }

    @Test("cooperative cancellation mid-search keeps the last completed depth")
    func cancelledMidSearch() throws {
        let pos = try Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        var reference = Search()
        let full = reference.search(pos, options: SearchOptions(maxDepth: 2, moveTimeMs: unlimitedMoveTime))

        // The flag is polled every 2048 nodes; flip it on the 16th poll (after ~30k nodes: depth 2 is
        // done, depth 3 needs 62k nodes on its own and depth 5 far more).
        let polls = OSAllocatedUnfairLock(initialState: 0)
        var s = Search()
        let r = s.search(pos, options: SearchOptions(maxDepth: 5, moveTimeMs: unlimitedMoveTime, isCancelled: {
            polls.withLock { $0 += 1; return $0 >= 16 }
        }))
        #expect(polls.withLock { $0 } == 16)
        #expect(r.depth == 2, "depth \(r.depth) after \(r.nodes) nodes")
        #expect(r.best != nil)
        #expect(r.ucis.rootMoves == full.ucis.rootMoves)
        #expect(r.nodes == full.nodes) // nodes reported are those of the last completed depth
        for i in 1..<r.rootMoves.count { #expect(r.rootMoves[i - 1].score >= r.rootMoves[i].score) }
    }

    @Test("SearchCancellation is a thread-safe flag")
    func cancellationToken() async throws {
        let token = SearchCancellation()
        #expect(!token.isCancelled)
        let pos = try Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        let result = Task.detached {
            var s = Search()
            return s.search(pos, options: SearchOptions(maxDepth: 40, moveTimeMs: unlimitedMoveTime, isCancelled: { token.isCancelled }))
        }
        try await Task.sleep(for: .milliseconds(200))
        token.cancel()
        #expect(token.isCancelled)
        let r = await result.value
        #expect(r.best != nil)
        #expect(r.depth < 40)
    }

    @Test("the transposition table persists across searches until clear()")
    func clearResetsState() throws {
        let c = fx.searches[0]
        let pos = try Position(fen: c.fen)
        var s = Search()
        let opts = SearchOptions(maxDepth: c.maxDepth, moveTimeMs: unlimitedMoveTime)
        let first = s.search(pos, options: opts)
        #expect(first.nodes == c.result.nodes)
        let second = s.search(pos, options: opts) // warm TT + history: a different tree
        #expect(second.best == first.best)
        s.clear()
        let third = s.search(pos, options: opts)
        #expect(third.nodes == first.nodes)
        #expect(third.ucis.rootMoves == first.ucis.rootMoves)
    }

    // MARK: - Speed

    @Test("nodes per second (for PORTING_PLAN Notes)")
    func speed() throws {
        let positions = [
            ("start d5", Position(), 5),
            ("kiwipete d4", try Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"), 4),
            ("t-promo d6", try Position(fen: try #require(fx.puzzles.first { $0.id == "t-promo" }).fen), 6),
        ]
        var totalNodes = 0
        var total = Duration.zero
        let clock = ContinuousClock()
        for (name, pos, depth) in positions {
            var s = Search()
            let start = clock.now
            let r = s.search(pos, options: SearchOptions(maxDepth: depth, moveTimeMs: unlimitedMoveTime))
            let elapsed = clock.now - start
            totalNodes += r.nodes
            total += elapsed
            let secs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            print("search speed \(name): \(r.nodes) nodes in \(Int(secs * 1000)) ms = \(Int(Double(r.nodes) / secs)) nodes/sec")
            #expect(r.depth == depth)
        }
        let secs = Double(total.components.seconds) + Double(total.components.attoseconds) / 1e18
        print("search speed overall: \(totalNodes) nodes in \(Int(secs * 1000)) ms = \(Int(Double(totalNodes) / secs)) nodes/sec")
    }
}
