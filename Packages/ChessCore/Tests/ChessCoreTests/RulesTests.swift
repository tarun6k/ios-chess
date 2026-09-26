import Testing
@testable import ChessCore

// tests/rules.test.ts, one Swift test per TS `it`, same names.

@Suite("piece movement")
struct PieceMovementTests {
    @Test("pawn cannot capture straight ahead")
    func pawnCannotCaptureStraightAhead() throws {
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
    func knightJumpsOverPieces() throws {
        let pos = try Position(fen: "4k3/8/8/8/8/1p6/1pp5/N3K3 w - - 0 1")
        // a1 knight is boxed in by pawns but jumps over them to capture on b3/c2
        #expect(uciMoves(pos).filter { $0.hasPrefix("a1") } == ["a1b3", "a1c2"])
    }

    @Test("king cannot move to an attacked square")
    func kingCannotMoveToAttackedSquare() throws {
        let pos = try Position(fen: "4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
        let moves = uciMoves(pos).filter { $0.hasPrefix("e1") }
        #expect(!moves.contains("e1d2"))
        #expect(!moves.contains("e1f2"))
        #expect(moves.contains("e1d1"))
    }

    @Test("pinned piece cannot expose the king")
    func pinnedPieceCannotExposeKing() throws {
        // Bishop on e2 pinned by rook on e8 against king e1
        let pos = try Position(fen: "4r1k1/8/8/8/8/8/4B3/4K3 w - - 0 1")
        let bishopMoves = uciMoves(pos).filter { $0.hasPrefix("e2") }
        #expect(bishopMoves == [])
    }
}

@Suite("castling")
struct CastlingTests {
    static let base = "r3k2r/8/8/8/8/8/8/R3K2R"

    @Test("both sides can castle both ways when all conditions hold")
    func bothSidesCanCastle() throws {
        let pos = try Position(fen: Self.base + " w KQkq - 0 1")
        let moves = uciMoves(pos)
        #expect(moves.contains("e1g1"))
        #expect(moves.contains("e1c1"))
    }

    @Test("cannot castle while in check")
    func cannotCastleInCheck() throws {
        let pos = try Position(fen: "r3k2r/8/8/8/8/8/4r3/R3K2R w KQkq - 0 1")
        let moves = uciMoves(pos)
        #expect(!moves.contains("e1g1"))
        #expect(!moves.contains("e1c1"))
    }

    @Test("cannot castle through an attacked square")
    func cannotCastleThroughAttack() throws {
        // Black rook on f8 covers f1
        let pos = try Position(fen: "5rk1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        #expect(!uciMoves(pos).contains("e1g1"))
        #expect(uciMoves(pos).contains("e1c1"))
    }

    @Test("cannot castle into check")
    func cannotCastleIntoCheck() throws {
        // Black rook covers g1
        let pos = try Position(fen: "4k1r1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        #expect(!uciMoves(pos).contains("e1g1"))
    }

    @Test("queenside b1 may be attacked (only king path matters)")
    func queensideB1MayBeAttacked() throws {
        // Black rook covers b1 — castling long is still legal
        let pos = try Position(fen: "1r5k/8/8/8/8/8/8/R3K3 w Q - 0 1")
        #expect(uciMoves(pos).contains("e1c1"))
    }

    @Test("rights lost after king or rook moves")
    func rightsLostAfterKingOrRookMoves() throws {
        var g = try Game(fen: Self.base + " w KQkq - 0 1")
        g.playSAN("Ke2"); g.playSAN("Kd8"); g.playSAN("Ke1"); g.playSAN("Ke8")
        #expect(!uciMoves(g.position).contains("e1g1"))
        #expect(!uciMoves(g.position).contains("e1c1"))
    }

    @Test("rights lost when the rook is captured on its square")
    func rightsLostWhenRookCaptured() throws {
        var g = try Game(fen: "4k3/8/8/8/8/8/6b1/R3K2R b KQ - 0 1")
        g.playSAN("Bxh1")
        #expect(g.position.castling.rawValue & 1 == 0) // WK gone
        #expect(g.position.castling.rawValue & 2 == 2) // WQ remains
    }
}

@Suite("en passant")
struct EnPassantTests {
    @Test("is offered immediately after a double push and expires after one move")
    func offeredThenExpires() throws {
        var g = try Game(fen: "4k3/2p5/8/1P6/8/8/8/4K3 b - - 0 1")
        g.playSAN("c5")
        #expect(uciMoves(g.position).contains("b5c6"))
        g.playSAN("Kd1") // decline
        g.playSAN("Kd8")
        #expect(!uciMoves(g.position).contains("b5c6"))
    }

    @Test("ep capture removes the captured pawn")
    func captureRemovesPawn() throws {
        var g = try Game(fen: "4k3/2p5/8/1P6/8/8/8/4K3 b - - 0 1")
        g.playSAN("c5")
        let san = g.playSAN("bxc6")
        #expect(san == "bxc6")
        #expect(g.position.fen.split(separator: " ")[0] == "4k3/8/2P5/8/8/8/8/4K3")
    }

    @Test("ep capture that exposes the king is illegal")
    func captureExposingKingIsIllegal() throws {
        // After exd3 e.p. BOTH pawns leave rank 4, exposing the a4 king to Qh4.
        let pos = try Position(fen: "8/8/8/8/k2Pp2Q/8/8/4K3 b - d3 0 1")
        #expect(!uciMoves(pos).contains("e4d3"))
        // The same capture is legal when the queen is elsewhere.
        let pos2 = try Position(fen: "8/8/8/8/k2Pp3/8/8/4K2Q b - d3 0 1")
        #expect(uciMoves(pos2).contains("e4d3"))
    }
}

@Suite("promotion")
struct PromotionTests {
    @Test("offers all four promotion pieces")
    func offersAllFourPieces() throws {
        let pos = try Position(fen: "8/4P3/8/8/8/8/k7/4K3 w - - 0 1")
        let promos = uciMoves(pos).filter { $0.hasPrefix("e7e8") }
        #expect(promos.sorted() == ["e7e8b", "e7e8n", "e7e8q", "e7e8r"])
    }

    @Test("capture-promotion works and is notated correctly")
    func capturePromotion() throws {
        var g = try Game(fen: "3r3k/4P3/8/8/8/8/8/4K3 w - - 0 1")
        let san = g.playSAN("exd8=Q+")
        #expect(san == "exd8=Q+")
    }

    @Test("underpromotion to knight works and is not auto-queened")
    func underpromotionToKnight() throws {
        var g = try Game(fen: "4k3/6P1/8/8/8/8/8/4K3 w - - 0 1")
        let san = g.playSAN("g8=N")
        #expect(san == "g8=N")
        #expect(g.position.fen.split(separator: " ")[0] == "4k1N1/8/8/8/8/8/8/4K3")
    }
}

@Suite("check and mate")
struct CheckAndMateTests {
    @Test("scholars mate")
    func scholarsMate() {
        var g = Game()
        for m in ["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#"] {
            #expect(g.playSAN(m) != nil)
        }
        #expect(g.result?.kind == .checkmate)
        #expect(g.result?.winner == .white)
        #expect(g.result?.score == "1-0")
    }

    @Test("back rank mate")
    func backRankMate() throws {
        var g = try Game(fen: "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1")
        #expect(g.playSAN("Ra8#") == "Ra8#")
        #expect(g.result?.kind == .checkmate)
    }

    @Test("only legal replies to check are block, capture, or king move")
    func onlyLegalRepliesToCheck() throws {
        // Qe6 gives check along the e-file; black king e8.
        let pos = try Position(fen: "4k3/8/4Q3/8/8/8/8/4K3 b - - 0 1")
        let moves = uciMoves(pos)
        for m in moves { #expect(m.hasPrefix("e8")) }
    }
}
