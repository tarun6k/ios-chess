import Testing
@testable import ChessCore

// tests/notation.test.ts, one Swift test per TS `it`, same names.

@Suite("FEN")
struct FENTests {
    static let fens = [
        Position.startFEN,
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 12 34",
        "4k3/8/8/8/8/8/8/4K3 b - - 0 1",
    ]

    @Test("round-trips")
    func roundTrips() throws {
        for fen in Self.fens { #expect(try Position(fen: fen).fen == fen) }
    }
}

@Suite("SAN")
struct SANTests {
    @Test("file disambiguation (Rad1 vs Rgd1)")
    func fileDisambiguation() throws {
        let pos = try Position(fen: "4k3/8/8/8/8/8/8/R5RK w - - 0 1")
        let legals = pos.generateLegalMoves()
        let sans = legals.map { toSAN(pos, $0, legalMoves: legals) }
        #expect(sans.contains("Rad1"))
        #expect(sans.contains("Rgd1"))
    }

    @Test("rank disambiguation (R1a3 vs R5a3)")
    func rankDisambiguation() throws {
        let pos = try Position(fen: "4k3/8/8/R7/8/8/8/R3K3 w - - 0 1")
        let legals = pos.generateLegalMoves()
        let sans = legals.map { toSAN(pos, $0, legalMoves: legals) }
        #expect(sans.contains("R1a3"))
        #expect(sans.contains("R5a3"))
    }

    @Test("no false disambiguation when the other piece is pinned")
    func noFalseDisambiguationWhenPinned() throws {
        // Ne2 is pinned by the e7 rook; Na1 can reach c2 without "Nac2"
        let pos = try Position(fen: "4k3/4r3/8/8/8/8/4N3/N3K3 w - - 0 1")
        let legals = pos.generateLegalMoves()
        let sans = legals.map { toSAN(pos, $0, legalMoves: legals) }
        #expect(sans.contains("Nc2"))
        #expect(!sans.contains("Nac2"))
    }

    @Test("parses long algebraic as fallback")
    func parsesLongAlgebraic() throws {
        let pos = try Position(fen: Position.startFEN)
        let m = fromSAN(pos, "e2e4")
        #expect(m != nil)
        #expect(m?.uci == "e2e4")
    }

    @Test("castling SAN with zeros is tolerated")
    func castlingWithZeros() throws {
        var g = try Game(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        #expect(g.playSAN("0-0") == "O-O")
    }
}

@Suite("PGN")
struct PGNTests {
    @Test("round-trips a game with castling, capture, ep and promotion")
    func roundTrips() throws {
        var g = Game()
        let line = ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "O-O", "Nf6", "d4", "exd4", "e5", "d5",
                    "exf6", "dxc4", "fxg7", "Rg8", "Nxd4", "Rxg7"]
        for s in line { #expect(g.playSAN(s) != nil) }
        let pgn = toPGN(g, headers: ["White": "Player", "Black": "AI", "Date": "2026.08.11"])
        let (g2, headers) = try fromPGN(pgn)
        #expect(headers["White"] == "Player")
        #expect(g2.sanLine() == g.sanLine())
        #expect(g2.position.fen == g.position.fen)
    }

    @Test("imports PGN with comments, NAGs and variations")
    func importsAnnotatedPGN() throws {
        let pgn = "[Event \"Test\"]\n\n1. e4 {best by test} e5 $1 2. Nf3 (2. f4 exf4) 2... Nc6 1/2-1/2"
        let (game, _) = try fromPGN(pgn)
        #expect(game.sanLine() == ["e4", "e5", "Nf3", "Nc6"])
    }

    @Test("exports FEN header for non-standard starts")
    func exportsFENHeader() throws {
        var g = try Game(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
        g.playSAN("Ra8+")
        let pgn = toPGN(g)
        #expect(pgn.contains("[FEN \"4k3/8/8/8/8/8/8/R3K3 w - - 0 1\"]"))
        let (g2, _) = try fromPGN(pgn)
        #expect(g2.sanLine() == ["Ra8+"])
    }
}

@Suite("zobrist consistency")
struct ZobristConsistencyTests {
    @Test("incremental hash matches full recompute over random games")
    func incrementalHashMatchesRecompute() throws {
        // The TS LCG: seed = (seed * 1103515245 + 12345) & 0x7fffffff, evaluated in JS doubles.
        var seed = 12345.0
        func rnd() -> Double {
            let product = seed * 1_103_515_245 + 12345
            seed = Double(Int32(truncatingIfNeeded: Int64(product)) & 0x7fff_ffff)
            return seed / Double(0x7fff_ffff)
        }
        for _ in 0..<5 {
            var pos = try Position(fen: Position.startFEN)
            for _ in 0..<120 {
                let moves = pos.generateLegalMoves()
                if moves.isEmpty { break }
                pos.makeMove(moves[Int((rnd() * Double(moves.count)).rounded(.down))])
                var check = pos.clone()
                check.recomputeHash()
                #expect(check.hashLo == pos.hashLo)
                #expect(check.hashHi == pos.hashHi)
            }
        }
    }

    @Test("unmake restores the exact FEN")
    func unmakeRestoresFEN() throws {
        var pos = try Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        let fen = pos.fen
        for m in pos.generateLegalMoves() {
            pos.makeMove(m)
            pos.unmakeMove()
            #expect(pos.fen == fen)
        }
    }
}
