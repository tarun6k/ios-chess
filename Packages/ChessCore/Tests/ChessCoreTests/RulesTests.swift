import Testing
@testable import ChessCore

/// The Position-level cases of tests/rules.test.ts (the Game / SAN cases follow in Phase 2).
@Suite("rules: move generation")
struct RulesTests {
    private func uciMoves(_ pos: Position) -> [String] {
        pos.generateLegalMoves().map(\.uci).sorted()
    }

    // MARK: piece movement

    @Test("pawn cannot capture straight ahead")
    func pawnNoForwardCapture() throws {
        let pos = try Position(fen: "4k3/8/8/3p4/3P4/8/8/4K3 w - - 0 1")
        #expect(uciMoves(pos).filter { $0.hasPrefix("d4") } == [])
    }

    @Test("pawn double push only from start rank and not through pieces")
    func pawnDoublePush() throws {
        let pos = try Position(fen: "4k3/8/8/8/8/4p3/4P3/4K3 w - - 0 1")
        #expect(uciMoves(pos).filter { $0.hasPrefix("e2") } == [])
        let pos2 = try Position(fen: "4k3/8/8/8/4p3/8/4P3/4K3 w - - 0 1")
        #expect(uciMoves(pos2).filter { $0.hasPrefix("e2") } == ["e2e3"])
    }

    @Test("knight jumps over pieces")
    func knightJumps() throws {
        let pos = try Position(fen: "4k3/8/8/8/8/1p6/1pp5/N3K3 w - - 0 1")
        // a1 knight is boxed in by pawns but jumps over them to capture on b3/c2
        #expect(uciMoves(pos).filter { $0.hasPrefix("a1") } == ["a1b3", "a1c2"])
    }

    @Test("king cannot move to an attacked square")
    func kingAvoidsAttackedSquares() throws {
        let pos = try Position(fen: "4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
        let moves = uciMoves(pos).filter { $0.hasPrefix("e1") }
        #expect(!moves.contains("e1d2"))
        #expect(!moves.contains("e1f2"))
        #expect(moves.contains("e1d1"))
    }

    @Test("pinned piece cannot expose the king")
    func pinnedPiece() throws {
        // Bishop on e2 pinned by rook on e8 against king e1
        let pos = try Position(fen: "4r1k1/8/8/8/8/8/4B3/4K3 w - - 0 1")
        #expect(uciMoves(pos).filter { $0.hasPrefix("e2") } == [])
    }

    // MARK: castling

    static let castlingBase = "r3k2r/8/8/8/8/8/8/R3K2R"

    @Test("both sides can castle both ways when all conditions hold")
    func castlingAllowed() throws {
        let pos = try Position(fen: Self.castlingBase + " w KQkq - 0 1")
        let moves = uciMoves(pos)
        #expect(moves.contains("e1g1"))
        #expect(moves.contains("e1c1"))
    }

    @Test("cannot castle while in check")
    func noCastlingInCheck() throws {
        let pos = try Position(fen: "r3k2r/8/8/8/8/8/4r3/R3K2R w KQkq - 0 1")
        let moves = uciMoves(pos)
        #expect(!moves.contains("e1g1"))
        #expect(!moves.contains("e1c1"))
    }

    @Test("cannot castle through an attacked square")
    func noCastlingThroughAttack() throws {
        // Black rook on f8 covers f1
        let pos = try Position(fen: "5rk1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        #expect(!uciMoves(pos).contains("e1g1"))
        #expect(uciMoves(pos).contains("e1c1"))
    }

    @Test("cannot castle into check")
    func noCastlingIntoCheck() throws {
        // Black rook covers g1
        let pos = try Position(fen: "4k1r1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        #expect(!uciMoves(pos).contains("e1g1"))
    }

    @Test("queenside b1 may be attacked (only king path matters)")
    func queensideB1Attacked() throws {
        // Black rook covers b1 — castling long is still legal
        let pos = try Position(fen: "1r5k/8/8/8/8/8/8/R3K3 w Q - 0 1")
        #expect(uciMoves(pos).contains("e1c1"))
    }

    @Test("castling rights update through make/unmake")
    func castlingRightsMakeUnmake() throws {
        var pos = try Position(fen: "4k3/8/8/8/8/8/6b1/R3K2R b KQ - 0 1")
        let bxh1 = try #require(pos.generateLegalMoves().first { $0.uci == "g2h1" })
        pos.makeMove(bxh1)
        #expect(!pos.castling.contains(.whiteKingside)) // WK gone
        #expect(pos.castling.contains(.whiteQueenside)) // WQ remains
        pos.unmakeMove()
        #expect(pos.castling == [.whiteKingside, .whiteQueenside])
    }

    // MARK: en passant

    @Test("ep is offered only right after a double push with an adjacent enemy pawn")
    func enPassantOffer() throws {
        var pos = try Position(fen: "4k3/2p5/8/1P6/8/8/8/4K3 b - - 0 1")
        let c5 = try #require(pos.generateLegalMoves().first { $0.uci == "c7c5" })
        pos.makeMove(c5)
        #expect(pos.enPassant == parseSquare("c6"))
        #expect(uciMoves(pos).contains("b5c6"))
        let kd1 = try #require(pos.generateLegalMoves().first { $0.uci == "e1d1" })
        pos.makeMove(kd1) // decline
        #expect(pos.enPassant == -1)
        let kd8 = try #require(pos.generateLegalMoves().first { $0.uci == "e8d8" })
        pos.makeMove(kd8)
        #expect(!uciMoves(pos).contains("b5c6"))
    }

    @Test("ep capture removes the captured pawn")
    func enPassantCapture() throws {
        var pos = try Position(fen: "4k3/2p5/8/1P6/8/8/8/4K3 b - - 0 1")
        pos.makeMove(try #require(pos.generateLegalMoves().first { $0.uci == "c7c5" }))
        let bxc6 = try #require(pos.generateLegalMoves().first { $0.uci == "b5c6" })
        #expect(bxc6.flags == .enPassant)
        pos.makeMove(bxc6)
        #expect(pos.fen.split(separator: " ")[0] == "4k3/8/2P5/8/8/8/8/4K3")
        pos.unmakeMove()
        #expect(pos.fen.split(separator: " ")[0] == "4k3/8/8/1Pp5/8/8/8/4K3")
    }

    @Test("ep capture that exposes the king is illegal")
    func enPassantPin() throws {
        // After exd3 e.p. BOTH pawns leave rank 4, exposing the a4 king to Qh4.
        let pos = try Position(fen: "8/8/8/8/k2Pp2Q/8/8/4K3 b - d3 0 1")
        #expect(!uciMoves(pos).contains("e4d3"))
        // The same capture is legal when the queen is elsewhere.
        let pos2 = try Position(fen: "8/8/8/8/k2Pp3/8/8/4K2Q b - d3 0 1")
        #expect(uciMoves(pos2).contains("e4d3"))
    }

    // MARK: promotion

    @Test("offers all four promotion pieces")
    func promotionChoices() throws {
        let pos = try Position(fen: "8/4P3/8/8/8/8/k7/4K3 w - - 0 1")
        let promos = uciMoves(pos).filter { $0.hasPrefix("e7e8") }
        #expect(promos == ["e7e8b", "e7e8n", "e7e8q", "e7e8r"])
    }

    @Test("capture-promotion and underpromotion place the chosen piece")
    func promotionMakeUnmake() throws {
        var pos = try Position(fen: "3r3k/4P3/8/8/8/8/8/4K3 w - - 0 1")
        let exd8q = try #require(pos.generateLegalMoves().first { $0.uci == "e7d8q" })
        pos.makeMove(exd8q)
        #expect(pos.fen.split(separator: " ")[0] == "3Q3k/8/8/8/8/8/8/4K3")
        #expect(pos.isInCheck())
        pos.unmakeMove()
        #expect(pos.fen == "3r3k/4P3/8/8/8/8/8/4K3 w - - 0 1")

        var pos2 = try Position(fen: "4k3/6P1/8/8/8/8/8/4K3 w - - 0 1")
        let g8n = try #require(pos2.generateLegalMoves().first { $0.uci == "g7g8n" })
        #expect(g8n.promotion == .knight)
        pos2.makeMove(g8n)
        #expect(pos2.fen.split(separator: " ")[0] == "4k1N1/8/8/8/8/8/8/4K3")
    }

    // MARK: check

    @Test("only legal replies to check are block, capture, or king move")
    func repliesToCheck() throws {
        // Qe6 gives check along the e-file; the bare black king on e8 must move.
        let pos = try Position(fen: "4k3/8/4Q3/8/8/8/8/4K3 b - - 0 1")
        #expect(pos.isInCheck())
        for m in uciMoves(pos) { #expect(m.hasPrefix("e8")) }
    }

    @Test("checkmate and stalemate leave no legal moves")
    func noLegalMoves() throws {
        let mate = try Position(fen: "R5k1/5ppp/8/8/8/8/8/4K3 b - - 0 1")
        #expect(mate.isInCheck())
        #expect(!mate.hasLegalMoves)
        let stalemate = try Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        #expect(!stalemate.isInCheck())
        #expect(!stalemate.hasLegalMoves)
        #expect(Position().hasLegalMoves)
    }

    // MARK: material

    @Test("material scan, insufficient material and dead positions")
    func material() throws {
        let start = Position()
        #expect(start.material(of: .white).count == 15)
        #expect(start.material(of: .black).map(\.type).filter { $0 == .pawn }.count == 8)
        #expect(!start.isInsufficientMaterial)
        #expect(try Position(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1").isInsufficientMaterial)
        #expect(try Position(fen: "4k3/8/8/8/8/8/8/4KB2 w - - 0 1").isInsufficientMaterial)
        #expect(try Position(fen: "4k3/8/8/8/8/8/8/4KN2 w - - 0 1").isInsufficientMaterial)
        #expect(try Position(fen: "2b1k3/8/8/8/8/8/8/4KB2 w - - 0 1").isInsufficientMaterial) // same-coloured bishops
        #expect(try !Position(fen: "3bk3/8/8/8/8/8/8/4KB2 w - - 0 1").isInsufficientMaterial) // opposite-coloured bishops
        #expect(try !Position(fen: "4k3/8/8/8/8/8/8/4KNN1 w - - 0 1").isInsufficientMaterial) // two knights
        #expect(try !Position(fen: "4k3/8/8/8/8/8/8/4KP2 w - - 0 1").isInsufficientMaterial)

        let bareKings = try Position(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        #expect(!bareKings.hasMatingPotential(.white))
        #expect(bareKings.isDeadPosition)
        let knightVsPawn = try Position(fen: "4k3/8/8/8/8/8/4p3/4KN2 w - - 0 1")
        #expect(knightVsPawn.hasMatingPotential(.white)) // a helping blocker exists
        #expect(!knightVsPawn.isDeadPosition)
        let loneKnight = try Position(fen: "4k3/8/8/8/8/8/8/4KN2 w - - 0 1")
        #expect(!loneKnight.hasMatingPotential(.white))
        #expect(try Position(fen: "4k3/8/8/8/8/8/8/4KNN1 w - - 0 1").hasMatingPotential(.white))
    }
}
