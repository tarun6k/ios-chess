import Darwin
import Testing
@testable import ChessCore

// tests/ai.test.ts `describe('persona')` plus parity with the TypeScript persona tables and RNG path.

@Suite("persona")
struct PersonaTests {
    let fx = AIFixtures.shared

    private func rootMoves(_ scores: [Int]) -> [RootMove] {
        // The TS tests use move ids 1, 2, 3…; any distinct packed moves will do.
        scores.enumerated().map { RootMove(move: Move(raw: UInt32($0.offset + 1)), score: $0.element) }
    }

    @Test("max skill always plays the best move")
    func maxSkillPlaysBest() {
        let moves = rootMoves([100, 80, -200])
        let p = personaForSkill(20, moveTimeMs: 1000)
        var lcg = TestLCG(seed: 42)
        for _ in 0..<50 { #expect(chooseMove(moves, persona: p) { lcg.next() } == 0) }
    }

    @Test("low skill sometimes deviates but stays within the drop bound")
    func lowSkillDeviatesWithinBound() {
        let moves = rootMoves([100, 60, -900])
        let p = personaForSkill(2, moveTimeMs: 1000)
        var lcg = TestLCG(seed: 7)
        var deviations = 0
        for _ in 0..<200 {
            let idx = chooseMove(moves, persona: p) { lcg.next() }
            #expect(idx != 2) // -900 is beyond maxDropCp 320
            if idx != 0 { deviations += 1 }
        }
        #expect(deviations > 0)
    }

    @Test("never abandons a found mate")
    func neverAbandonsMate() {
        let moves = rootMoves([mateScore - 5, 50])
        let p = personaForSkill(0, moveTimeMs: 1000)
        for _ in 0..<50 { #expect(chooseMove(moves, persona: p) == 0) }
    }

    // MARK: - Parity

    @Test("skill → persona table and Elo match the TS")
    func personaTable() {
        for c in fx.personas {
            #expect(personaForSkill(c.skill, moveTimeMs: 1234.5) == c.persona, "skill \(c.skill)")
            #expect(skillToElo(c.skill) == c.elo, "skill \(c.skill)")
        }
        #expect(fx.personas.count >= 21)
        for c in fx.eloToSkill { #expect(eloToSkill(c.elo) == c.skill, "elo \(c.elo)") }
        // Boundaries of the depth/drop/blunder ladders.
        #expect(personaForSkill(2, moveTimeMs: 0).maxDepth == 2)
        #expect(personaForSkill(2.01, moveTimeMs: 0).maxDepth == 3)
        #expect(personaForSkill(16, moveTimeMs: 0).maxDepth == 5)
        #expect(personaForSkill(16.01, moveTimeMs: 0).maxDepth == 8)
        #expect(personaForSkill(15, moveTimeMs: 0).maxDropCp == 30)
        #expect(personaForSkill(14.99, moveTimeMs: 0).maxDropCp == 80)
        #expect(personaForSkill(-5, moveTimeMs: 0) == personaForSkill(0, moveTimeMs: 0))
        #expect(personaForSkill(99, moveTimeMs: 0) == personaForSkill(20, moveTimeMs: 0))
    }

    @Test("the test LCG reproduces the JS sequence exactly")
    func lcgSequence() {
        var lcg42 = TestLCG(seed: 42)
        for expected in fx.rng.lcgSeed42 { #expect(lcg42.next() == expected) }
        var lcg7 = TestLCG(seed: 7)
        for expected in fx.rng.lcgSeed7 { #expect(lcg7.next() == expected) }
        #expect(fx.rng.lcgSeed42.count == 20)
    }

    @Test("Box–Muller gaussian matches the TS to within a couple of ulps")
    func gaussianSequence() {
        // The formula is identical; the last bit can differ because V8 evaluates Math.log / Math.cos with
        // its own fdlibm port while Swift uses Apple's libm (the TS app itself differs between Chrome and
        // Safari here). 1 of these 20 values is off by one ulp; chooseMoveParity shows the picks agree.
        var lcg = TestLCG(seed: 42)
        var exact = 0
        for expected in fx.rng.gaussianSeed42 {
            let got = gaussian { lcg.next() }
            #expect(abs(got - expected) <= 2 * expected.ulp, "\(got) vs \(expected)")
            if got == expected { exact += 1 }
        }
        #expect(fx.rng.gaussianSeed42.count == 20)
        #expect(exact >= 18)
    }

    @Test("gaussian re-draws zero uniforms")
    func gaussianSkipsZero() {
        var draws = [0.0, 0.0, 0.5, 0.0, 0.25]
        let g = gaussian { draws.removeFirst() }
        #expect(draws.isEmpty)
        // u = 0.5, v = 0.25 → sqrt(-2 ln 0.5) * cos(π/2)
        #expect(abs(g - (-2 * log(0.5)).squareRoot() * cos(2 * Double.pi * 0.25)) < 1e-15)
    }

    @Test("chooseMove picks the same indices as the TS for a seeded RNG", arguments: AIFixtures.shared.rng.chooseMove)
    func chooseMoveParity(_ c: AIFixtures.ChooseMoveCase) {
        let moves = rootMoves(c.scores)
        let p = personaForSkill(c.skill, moveTimeMs: 1000)
        var lcg = TestLCG(seed: c.seed)
        var picks: [Int] = []
        for _ in 0..<c.n { picks.append(chooseMove(moves, persona: p) { lcg.next() }) }
        #expect(picks == c.picks)
    }

    // MARK: - Guarantees

    @Test("never hangs a piece outside the loss bound, at any skill")
    func lossBound() {
        var lcg = TestLCG(seed: 2024)
        for skill in stride(from: 0.0, through: 20, by: 0.5) {
            let p = personaForSkill(skill, moveTimeMs: 1000)
            for _ in 0..<200 {
                // Random sorted root list: best ∈ [-300, 300], then drops of up to 700cp.
                var scores = [Int(lcg.next() * 600) - 300]
                for _ in 0..<Int(1 + lcg.next() * 12) { scores.append(scores.last! - Int(lcg.next() * 700)) }
                let idx = chooseMove(rootMoves(scores), persona: p) { lcg.next() }
                #expect(scores[0] - scores[idx] <= p.maxDropCp, "skill \(skill) picked \(scores[idx]) of \(scores)")
            }
        }
    }

    @Test("a forced loss is never chosen while a non-losing move exists")
    func avoidsForcedLoss() {
        let moves = rootMoves([30, -mateScore + 3, -mateScore + 1])
        let p = personaForSkill(0, moveTimeMs: 1000)
        var lcg = TestLCG(seed: 11)
        for _ in 0..<100 { #expect(chooseMove(moves, persona: p) { lcg.next() } == 0) }
        // When every move loses, the candidates are the mates themselves and the noise decides.
        let allLost = rootMoves([-mateScore + 3, -mateScore + 1])
        var picked = Set<Int>()
        for _ in 0..<100 { picked.insert(chooseMove(allLost, persona: p) { lcg.next() }) }
        #expect(picked == [0, 1])
    }

    @Test("single or empty root lists return index 0")
    func degenerate() {
        let p = personaForSkill(5, moveTimeMs: 1000)
        #expect(chooseMove([], persona: p) == 0)
        #expect(chooseMove(rootMoves([-500]), persona: p) == 0)
    }
}
