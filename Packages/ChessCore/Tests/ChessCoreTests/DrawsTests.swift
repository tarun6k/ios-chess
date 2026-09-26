import Testing
@testable import ChessCore

// tests/draws.test.ts, one Swift test per TS `it`, same names.

@Suite("stalemate")
struct StalemateTests {
    @Test("is detected and drawn")
    func detectedAndDrawn() throws {
        let g = try Game(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        #expect(g.result?.kind == .stalemate)
        #expect(g.result?.score == "1/2-1/2")
    }

    @Test("reached by a move")
    func reachedByMove() throws {
        var g = try Game(fen: "7k/5K2/8/6Q1/8/8/8/8 w - - 0 1")
        g.playSAN("Qg6") // not check; black king h8 has no moves
        #expect(g.result?.kind == .stalemate)
    }
}

@Suite("repetition")
struct RepetitionTests {
    private func shuffle(_ g: inout Game, _ times: Int) {
        for _ in 0..<times {
            g.playSAN("Nf3"); g.playSAN("Nf6"); g.playSAN("Ng1"); g.playSAN("Ng8")
        }
    }

    @Test("threefold is claimable at 3 occurrences (not auto)")
    func threefoldClaimable() {
        var g = Game()
        shuffle(&g, 2) // start position now seen 3 times
        #expect(g.result == nil)
        #expect(g.repetitionCount() == 3)
        #expect(g.claimableDraw() == .threefold)
        #expect(g.claimDraw() == true)
        #expect(g.result?.kind == .threefold)
    }

    @Test("fivefold is an automatic draw")
    func fivefoldAutomatic() {
        var g = Game()
        shuffle(&g, 4) // 5th occurrence of the start position
        #expect(g.result?.kind == .fivefold)
    }

    @Test("positions with different castling rights are not repetitions")
    func castlingRightsDistinguishPositions() throws {
        var g = try Game(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        // King shuffles kill castling rights, so "same-looking" positions differ.
        g.playSAN("Ke2"); g.playSAN("Ke7"); g.playSAN("Ke1"); g.playSAN("Ke8")
        #expect(g.repetitionCount() == 1)
    }
}

@Suite("fifty and seventy-five move rules")
struct MoveRuleTests {
    @Test("fifty-move draw is claimable at halfmove 100")
    func fiftyMoveClaimable() throws {
        var g = try Game(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 99 80")
        #expect(g.claimableDraw() == nil)
        g.playSAN("Ra2")
        #expect(g.claimableDraw() == .fiftyMove)
        #expect(g.claimDraw() == true)
        #expect(g.result?.kind == .fiftyMove)
    }

    @Test("seventy-five-move rule is automatic")
    func seventyFiveMoveAutomatic() throws {
        var g = try Game(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 149 100")
        g.playSAN("Ra2")
        #expect(g.result?.kind == .seventyFiveMove)
    }

    @Test("pawn move resets the clock")
    func pawnMoveResetsClock() throws {
        var g = try Game(fen: "4k3/8/8/8/8/8/4P3/R3K3 w - - 99 80")
        g.playSAN("e3")
        #expect(g.position.halfmove == 0)
        #expect(g.claimableDraw() == nil)
    }
}

@Suite("insufficient material")
struct InsufficientMaterialTests {
    /// The TS test body shared by the generated cases.
    private func check(_ fen: String, drawn: Bool, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let g = try Game(fen: fen)
        if drawn { #expect(g.result?.kind == .insufficient, sourceLocation: sourceLocation) }
        else { #expect(g.result == nil, sourceLocation: sourceLocation) }
    }

    @Test("K vs K is a draw")
    func kVsK() throws { try check("4k3/8/8/8/8/8/8/4K3 w - - 0 1", drawn: true) }

    @Test("K+B vs K is a draw")
    func kbVsK() throws { try check("4k3/8/8/8/8/8/8/2B1K3 w - - 0 1", drawn: true) }

    @Test("K+N vs K is a draw")
    func knVsK() throws { try check("4k3/8/8/8/8/8/8/1N2K3 w - - 0 1", drawn: true) }

    @Test("K+B vs K+B same color (both dark) is a draw")
    func kbVsKbSameColor() throws { try check("4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1", drawn: true) }

    @Test("K+B vs K+B opposite colors is not an automatic draw")
    func kbVsKbOppositeColors() throws { try check("4k1b1/8/8/8/8/8/8/2B1K3 w - - 0 1", drawn: false) }

    @Test("K+N vs K+N is not an automatic draw")
    func knVsKn() throws { try check("4kn2/8/8/8/8/8/8/1N2K3 w - - 0 1", drawn: false) }

    @Test("K+R vs K is not an automatic draw")
    func krVsK() throws { try check("4k3/8/8/8/8/8/8/R3K3 w - - 0 1", drawn: false) }

    @Test("K+P vs K is not an automatic draw")
    func kpVsK() throws { try check("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", drawn: false) }

    @Test("K+NN vs K is not an automatic draw")
    func knnVsK() throws { try check("4k3/8/8/8/8/8/8/NN2K3 w - - 0 1", drawn: false) }

    @Test("capture into K+B vs K ends the game immediately")
    func captureIntoInsufficient() throws {
        var g = try Game(fen: "4k3/8/8/3r4/8/8/B7/4K3 w - - 0 1")
        #expect(g.playSAN("Bxd5") == "Bxd5")
        #expect(g.result?.kind == .insufficient)
    }
}

@Suite("dead position")
struct DeadPositionTests {
    @Test("K+N vs K has no mating potential for either side")
    func knVsKIsDead() throws {
        let pos = try Position(fen: "4k3/8/8/8/8/8/8/1N2K3 w - - 0 1")
        #expect(pos.isDeadPosition == true)
    }

    @Test("K+N vs K+N is not dead (helpmates exist)")
    func knVsKnIsNotDead() throws {
        let pos = try Position(fen: "4kn2/8/8/8/8/8/8/1N2K3 w - - 0 1")
        #expect(pos.isDeadPosition == false)
    }
}

@Suite("agreement, resignation, timeout")
struct AgreementResignationTimeoutTests {
    @Test("draw offer / accept flow")
    func drawOfferAccept() {
        var g = Game()
        g.playSAN("e4")
        g.offerDraw(.white)
        #expect(g.drawOffer == .white)
        #expect(g.acceptDraw() == true)
        #expect(g.result?.kind == .agreement)
    }

    @Test("making a move implicitly declines a pending offer")
    func moveDeclinesOffer() {
        var g = Game()
        g.offerDraw(.white)
        g.playSAN("e4")
        #expect(g.drawOffer == nil)
        #expect(g.result == nil)
    }

    @Test("resignation ends the game")
    func resignationEndsGame() {
        var g = Game()
        g.resign(.white)
        #expect(g.result?.kind == .resignation)
        #expect(g.result?.winner == .black)
        #expect(g.result?.score == "0-1")
    }

    @Test("timeout: opponent with mating material wins")
    func timeoutOpponentWithMaterialWins() throws {
        var g = try Game(fen: "4k3/8/8/8/8/8/8/Q3K3 b - - 0 1")
        g.timeout(.black)
        #expect(g.result?.kind == .timeout)
        #expect(g.result?.winner == .white)
    }

    @Test("timeout vs bare king is a draw")
    func timeoutVsBareKingIsDraw() throws {
        var g = try Game(fen: "4k3/8/8/8/8/8/4P3/4K3 b - - 0 1")
        // White flags: Black has only a king → cannot mate → draw
        g.timeout(.white)
        #expect(g.result?.kind == .timeoutDraw)
        #expect(g.result?.score == "1/2-1/2")
    }

    @Test("timeout vs K+N when a helpmate exists is a loss (FIDE 6.9)")
    func timeoutVsKnightWithHelpmate() throws {
        // Black flags; White has K+N+P — mate is constructible, so White wins.
        var b = try Game(fen: "4k3/8/8/8/8/8/4P3/1N2K3 b - - 0 1")
        b.timeout(.black)
        #expect(b.result?.kind == .timeout)
        #expect(b.result?.winner == .white)

        // K+N vs K+N: flag fall → opponent CAN helpmate → win on time, not a draw.
        var c = try Game(fen: "4kn2/8/8/8/8/8/8/1N2K3 b - - 0 1")
        c.timeout(.black)
        #expect(c.result?.kind == .timeout)
        #expect(c.result?.winner == .white)
    }
}
