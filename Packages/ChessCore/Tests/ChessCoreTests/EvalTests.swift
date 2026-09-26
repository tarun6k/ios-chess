import Testing
@testable import ChessCore

@Suite("eval")
struct EvalTests {
    let fx = AIFixtures.shared

    @Test("piece values and every piece-square table match the TypeScript")
    func tablesMatch() throws {
        #expect(pieceValues == fx.tables.pieceValue)
        #expect(PieceSquareTables.pawn == fx.tables.pst["pawn"])
        #expect(PieceSquareTables.knight == fx.tables.pst["knight"])
        #expect(PieceSquareTables.bishop == fx.tables.pst["bishop"])
        #expect(PieceSquareTables.rook == fx.tables.pst["rook"])
        #expect(PieceSquareTables.queen == fx.tables.pst["queen"])
        #expect(PieceSquareTables.kingMG == fx.tables.pst["kingMG"])
        #expect(PieceSquareTables.kingEG == fx.tables.pst["kingEG"])
        #expect(fx.tables.pst.count == 7)
        #expect(PieceSquareTables.passedPawnBonus == fx.tables.passedBonus)
        #expect(PieceSquareTables.knightMovesD == fx.tables.knightMovesD)
        #expect(PieceSquareTables.knightMovesF == fx.tables.knightMovesF)
        #expect(EvalParams.neutral == fx.tables.neutralParams)
        #expect(mateScore == fx.mate)
        for (name, table) in fx.tables.pst { #expect(table.count == 64, "\(name)") }
    }

    @Test("static eval equals the TS eval", arguments: AIFixtures.shared.evals)
    func staticEvalParity(_ c: AIFixtures.EvalCase) throws {
        let pos = try Position(fen: c.fen)
        #expect(evaluate(pos, params: try fx.params(c.params)) == c.score)
    }

    @Test("the parity set covers every adaptation knob")
    func parityCoverage() {
        #expect(fx.evals.count >= 12 * 7)
        let sets = Set(fx.evals.map(\.params))
        #expect(sets.count == fx.paramSets.count)
        let everything = fx.paramSets["everything"]
        #expect(everything?.aggression != 0)
        #expect(everything?.spaceWeight != 0)
        #expect(everything?.kingSafetyWeight != 0)
        #expect(everything?.closedPref != 0)
        #expect(everything?.mobilityWeight == 0)
    }

    @Test("start position is balanced and the eval is colour-symmetric")
    func symmetry() throws {
        #expect(evaluate(Position()) == 0)
        // Mirroring the board and swapping colours negates the score (up to Math.round's half-up bias).
        // closedPref is the exception: the TS adds the locked-pawn bonus as a white-positive term.
        let pos = try Position(fen: "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4")
        let mirrored = try Position(fen: "rnbqk2r/pppp1ppp/5n2/2b1p3/4P3/2N2N2/PPPP1PPP/R1BQKB1R b KQkq - 4 4")
        for (name, params) in fx.paramSets where params.closedPref == 0 {
            #expect(abs(evaluate(pos, params: params) + evaluate(mirrored, params: params)) <= 1, "\(name)")
        }
    }

    @Test("jsRound rounds halves toward +∞ like Math.round")
    func rounding() {
        #expect(jsRound(2.5) == 3)
        #expect(jsRound(-2.5) == -2)
        #expect(jsRound(-0.5) == 0)
        #expect(jsRound(0.49999) == 0)
        #expect(jsRound(-1.5) == -1)
        #expect(jsRound(-1.51) == -2)
        #expect(jsRound(17) == 17)
    }
}
