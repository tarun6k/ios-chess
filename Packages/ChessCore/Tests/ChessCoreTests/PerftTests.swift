import Testing
@testable import ChessCore

/// Standard perft reference positions (chessprogramming.org), ported from tests/perft.test.ts.
@Suite("perft")
struct PerftTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let fen: String
        let counts: [Int]
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "start position", fen: Position.startFEN,
             counts: [20, 400, 8902, 197_281, 4_865_609]),
        Case(name: "kiwipete", fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
             counts: [48, 2039, 97_862, 4_085_603]),
        Case(name: "position 3 (en passant pins)", fen: "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
             counts: [14, 191, 2812, 43_238, 674_624]),
        Case(name: "position 4 (promotions)", fen: "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
             counts: [6, 264, 9467, 422_333]),
        Case(name: "position 5", fen: "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
             counts: [44, 1486, 62_379, 2_103_487]),
        Case(name: "position 6", fen: "r4rk1/1pp1qppp/p1np1n2/2b1p1b1/2B1P1B1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
             counts: [46, 2060, 88_933, 3_812_850]), // Stockfish-verified for this exact FEN
    ]

    @Test("node counts match the reference positions", arguments: cases)
    func perft(_ c: Case) throws {
        var pos = try Position(fen: c.fen)
        let fenBefore = pos.fen
        let clock = ContinuousClock()
        for d in 1...c.counts.count {
            var nodes = 0
            let elapsed = clock.measure { nodes = pos.perft(depth: d) }
            #expect(nodes == c.counts[d - 1], "\(c.name) depth \(d)")
            if nodes >= 1_000_000 {
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let ms = Int((seconds * 1000).rounded())
                let mnps = Int((Double(nodes) / seconds / 1e5).rounded())
                print("perft: \(c.name) depth \(d) = \(nodes) nodes in \(ms) ms (\(mnps / 10).\(mnps % 10) Mnps)")
            }
        }
        #expect(pos.fen == fenBefore, "perft must restore the position")
    }
}
