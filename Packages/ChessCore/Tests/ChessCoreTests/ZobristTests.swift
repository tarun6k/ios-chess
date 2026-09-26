import Testing
@testable import ChessCore

/// Parity fixtures printed from the TypeScript engine by `.porting/tools/zobrist-dump.ts` (vite-node);
/// the TS was removed in Phase 10, see docs/PORTING_NOTES.md to regenerate.
@Suite("Zobrist parity with zobrist.ts")
struct ZobristTests {
    /// The first 20 outputs of `mulberry32(0x9e3779b9)`, i.e. ZOBRIST_PIECES_LO/HI[0…9] interleaved.
    static let first20: [UInt32] = [
        1_541_420_728, 454_851_044, 2_900_350_524, 3_942_498_910, 436_270_539,
        1_292_797_714, 107_332_754, 2_003_106_812, 1_860_262_629, 2_351_451_603,
        2_189_223_826, 1_319_006_189, 3_858_527_959, 1_458_065_988, 439_542_631,
        1_065_433_749, 1_124_176_789, 3_650_098_597, 824_228_062, 2_846_529_103,
    ]
    static let castleLo: [UInt32] = [
        1_132_276_479, 2_401_131_257, 4_009_504_948, 2_872_390_245, 3_156_168_598, 1_450_092_135, 3_125_185_039, 1_579_416_826,
        2_499_533_343, 2_201_395_929, 1_265_955_452, 242_300_711, 1_699_785_080, 499_345_709, 3_339_140_641, 1_120_593_802,
    ]
    static let castleHi: [UInt32] = [
        2_780_142_710, 3_422_620_857, 1_378_038_268, 3_732_251_268, 2_584_493_501, 804_400_912, 922_123_608, 3_316_410_139,
        1_222_892_825, 1_201_445_209, 3_930_564_722, 1_810_926_564, 1_479_517_263, 1_058_310_262, 4_033_593_436, 2_142_141_315,
    ]
    static let epLo: [UInt32] = [2_543_149_993, 382_319_051, 1_230_877_709, 4_082_485_071, 1_102_549_100, 3_234_475_517, 3_173_898_064, 2_729_224_877]
    static let epHi: [UInt32] = [1_879_055_104, 3_977_904_472, 20_146_636, 2_582_474_478, 519_315_190, 3_796_057_724, 3_645_005_477, 1_508_216_349]

    struct HashFixture: Sendable, CustomTestStringConvertible {
        let fen: String
        let lo: UInt32
        let hi: UInt32
        let key: String
        var testDescription: String { fen }
    }

    static let positions: [HashFixture] = [
        HashFixture(fen: Position.startFEN, lo: 1_034_875_793, hi: 1_028_570_074, key: "h44z9t.h0dtqy"),
        HashFixture(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", lo: 4_161_673_709, hi: 3_129_431_474, key: "1wtr3zh.1fr6ks2"),
        HashFixture(fen: "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", lo: 3_795_989_276, hi: 2_874_140_056, key: "1qs182k.1bj6sns"),
        HashFixture(fen: "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", lo: 3_307_624_221, hi: 1_785_149_605, key: "1ip9v6l.tity91"),
        HashFixture(fen: "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", lo: 2_217_077_853, hi: 3_911_961_667, key: "10nzo7x.1sp2wxv"),
        HashFixture(fen: "r4rk1/1pp1qppp/p1np1n2/2b1p1b1/2B1P1B1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", lo: 3_971_249_334, hi: 4_246_375_031, key: "1todnli.1y86jxz"),
        HashFixture(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", lo: 1_620_155_328, hi: 2_000_914_368, key: "qsljuo.x3ajeo"),
    ]

    @Test("mulberry32(0x9e3779b9) reproduces the first 20 TS values")
    func rngStream() {
        var rng = Mulberry32(seed: Zobrist.seed)
        let got = (0..<20).map { _ in rng.next() }
        #expect(got == Self.first20)
    }

    @Test("piece keys are drawn in TS order: lo then hi per index")
    func pieceTable() {
        #expect(Zobrist.pieces.count == 12 * 64)
        for i in 0..<10 {
            #expect(Zobrist.lo(of: Zobrist.pieces[i]) == Self.first20[2 * i])
            #expect(Zobrist.hi(of: Zobrist.pieces[i]) == Self.first20[2 * i + 1])
        }
        #expect(Zobrist.lo(of: Zobrist.pieces[100]) == 358_696_447)
        #expect(Zobrist.hi(of: Zobrist.pieces[100]) == 1_988_909_462)
        #expect(Zobrist.lo(of: Zobrist.pieces[767]) == 2_294_821_445)
        #expect(Zobrist.hi(of: Zobrist.pieces[767]) == 1_653_560_485)
    }

    @Test("castling, en-passant and side keys match the TS tables")
    func otherTables() {
        #expect(Zobrist.castling.map(Zobrist.lo(of:)) == Self.castleLo)
        #expect(Zobrist.castling.map(Zobrist.hi(of:)) == Self.castleHi)
        #expect(Zobrist.enPassant.map(Zobrist.lo(of:)) == Self.epLo)
        #expect(Zobrist.enPassant.map(Zobrist.hi(of:)) == Self.epHi)
        #expect(Zobrist.lo(of: Zobrist.side) == 32_173_505)
        #expect(Zobrist.hi(of: Zobrist.side) == 3_982_899_340)
    }

    @Test("pieceIndex matches pieceZobristIndex")
    func pieceIndex() {
        #expect(Zobrist.pieceIndex(type: .pawn, color: .white, square: 0) == 0)
        #expect(Zobrist.pieceIndex(type: .king, color: .black, square: 63) == 767)
        #expect(Zobrist.pieceIndex(type: .knight, color: .black, square: 5) == (1 + 6) * 64 + 5)
    }

    @Test("position hashes match the TS engine", arguments: positions)
    func positionHash(_ fixture: HashFixture) throws {
        let pos = try Position(fen: fixture.fen)
        #expect(pos.hashLo == fixture.lo)
        #expect(pos.hashHi == fixture.hi)
        #expect(pos.hashKey == fixture.key)
        #expect(pos.hash == UInt64(fixture.hi) << 32 | UInt64(fixture.lo))
    }

    @Test("incremental hash after 1.e4 matches the TS engine (no ep square without an adjacent pawn)")
    func afterE4() throws {
        var pos = Position()
        let e2e4 = try #require(pos.generateLegalMoves().first { $0.from == 12 && $0.to == 28 })
        pos.makeMove(e2e4)
        #expect(pos.fen == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
        #expect(pos.hashLo == 556_141_484)
        #expect(pos.hashHi == 1_773_639_990)
        #expect(pos.hashKey == "9741ik.tbz9di")
    }
}
