import Testing
@testable import ChessCore

/// The Position-level cases of tests/notation.test.ts (SAN / PGN follow in Phase 2).
@Suite("FEN and hashing")
struct NotationTests {
    static let fens = [
        Position.startFEN,
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 12 34",
        "4k3/8/8/8/8/8/8/4K3 b - - 0 1",
    ]

    @Test("FEN round-trips", arguments: fens)
    func fenRoundTrip(_ fen: String) throws {
        #expect(try Position(fen: fen).fen == fen)
    }

    @Test("FEN parsing follows the TS: lax clocks, en-passant square, errors")
    func fenParsing() throws {
        let pos = try Position(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3")
        #expect(pos.enPassant == 20)
        #expect(pos.halfmove == 0 && pos.fullmove == 1)
        #expect(pos.fen == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        #expect(try Position(fen: "4k3/8/8/8/8/8/8/4K3 w - - 7 x").fullmove == 1)   // parseInt('x') || 1
        #expect(try Position(fen: "4k3/8/8/8/8/8/8/4K3 w - - x 9").halfmove == 0)   // parseInt('x') || 0
        #expect(try Position(fen: "  4k3/8/8/8/8/8/8/4K3   w  -  - 3 4 ").fen == "4k3/8/8/8/8/8/8/4K3 w - - 3 4")
        #expect(throws: FENError.invalidFEN("4k3/8/8/8/8/8/8/4K3 w -")) { try Position(fen: "4k3/8/8/8/8/8/8/4K3 w -") }
        #expect(throws: FENError.invalidPiece("x")) { try Position(fen: "4k3/8/8/8/8/8/8/4Kx2 w - - 0 1") }
    }

    @Test("squares, pieces and move packing match the TS constants")
    func typesParity() {
        #expect(squareName(0) == "a1" && squareName(7) == "h1" && squareName(56) == "a8" && squareName(63) == "h8")
        #expect(parseSquare("e4") == 28 && parseSquare("a1") == 0 && parseSquare("h8") == 63)
        #expect(parseSquare("i1") == nil && parseSquare("a9") == nil && parseSquare("a") == nil)
        #expect(fileOf(28) == 4 && rankOf(28) == 3 && squareAt(file: 4, rank: 3) == 28)
        #expect(Piece(type: .queen, color: .black).code == -5)
        #expect(Piece(type: .king, color: .white).code == 6)
        #expect(Piece(code: -3).type == .bishop && Piece(code: -3).color == .black)
        #expect(Piece.empty.type == .empty && Piece.empty.color == .black) // TS colorOf(0) === BLACK
        #expect(Piece(fenCharacter: "n") == Piece(type: .knight, color: .black))
        #expect(Piece(fenCharacter: "Q")?.fenCharacter == "Q")
        #expect(Piece(fenCharacter: "1") == nil)

        let m = Move(from: 12, to: 28, flags: .doublePush)
        #expect(m.raw == 12 | (28 << 6) | (2 << 12))
        #expect(m.from == 12 && m.to == 28 && m.flags == .doublePush && m.promotion == .empty)
        #expect(m.uci == "e2e4")
        let promo = Move(from: 52, to: 60, promotion: .queen)
        #expect(promo.raw == 52 | (60 << 6) | (5 << 16))
        #expect(promo.uci == "e7e8q")
        #expect(Move(from: 4, to: 6, flags: .castleKingside).raw == 4 | (6 << 6) | (4 << 12))
        #expect(CastlingRights.all.rawValue == 15)
        #expect(MoveFlags.enPassant.rawValue == 1 && MoveFlags.castleQueenside.rawValue == 8)
    }

    @Test("incremental hash matches full recompute over random games")
    func incrementalHash() {
        // The TS LCG: seed = (seed * 1103515245 + 12345) & 0x7fffffff, evaluated in JS doubles.
        var seed = 12345.0
        func rnd() -> Double {
            let product = seed * 1_103_515_245 + 12345
            seed = Double(Int32(truncatingIfNeeded: Int64(product)) & 0x7fff_ffff)
            return seed / Double(0x7fff_ffff)
        }
        for _ in 0..<5 {
            var pos = Position()
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
    func unmakeRestoresFen() throws {
        var pos = try Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        let fen = pos.fen
        let hash = pos.hash
        for m in pos.generateLegalMoves() {
            pos.makeMove(m)
            pos.unmakeMove()
            #expect(pos.fen == fen)
            #expect(pos.hash == hash)
        }
    }

    @Test("clone drops the undo history; a plain copy keeps its own")
    func cloneSemantics() throws {
        var pos = Position()
        pos.makeMove(try #require(pos.generateLegalMoves().first { $0.uci == "e2e4" }))
        var copy = pos
        copy.unmakeMove()
        #expect(copy.fen == Position.startFEN)
        #expect(pos.fen != Position.startFEN)
        let cloned = pos.clone()
        #expect(cloned.fen == pos.fen && cloned.hash == pos.hash)
    }
}
