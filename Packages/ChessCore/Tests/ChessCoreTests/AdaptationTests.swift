import Testing
@testable import ChessCore

// adaptation.ts against values the TS produced (adaptation-fixtures.json).

@Suite("Adaptation")
struct AdaptationTests {
    let fx = AdaptationFixtures.shared

    @Test("targetElo: mode offset plus the streak band, clamped to 600…2200", arguments: AdaptationFixtures.shared.targetElo)
    func targetEloGrid(_ c: AdaptationFixtures.TargetEloCase) {
        var m = PlayerModel()
        m.rating = c.rating
        m.streak = c.streak
        #expect(targetElo(m, mode: c.mode) == c.result)
    }

    @Test("targetElo spelled out")
    func targetEloRules() {
        var m = PlayerModel()
        m.rating = 1000
        #expect(targetElo(m, mode: .learn) == 910)
        #expect(targetElo(m, mode: .match) == 1000)
        #expect(targetElo(m, mode: .challenge) == 1090)
        m.streak = 3
        #expect(targetElo(m, mode: .match) == 1075) // +25 per consecutive win
        m.streak = 5
        #expect(targetElo(m, mode: .match) == 1120) // capped at +120
        m.streak = -2
        #expect(targetElo(m, mode: .match) == 950)
        m.streak = -8
        #expect(targetElo(m, mode: .match) == 880) // capped at −120
        m.rating = 620
        m.streak = -4
        #expect(targetElo(m, mode: .learn) == 600) // floor
        m.rating = 2190
        m.streak = 6
        #expect(targetElo(m, mode: .challenge) == 2200) // ceiling
    }

    @Test("eloToSkill boundaries", arguments: AdaptationFixtures.shared.eloToSkill)
    func eloToSkillCases(_ c: AdaptationFixtures.EloCase) {
        #expect(eloToSkill(c.elo) == c.skill)
    }

    @Test("planForGame per style with a scripted RNG", arguments: AdaptationFixtures.shared.plans)
    func plan(_ c: AdaptationFixtures.PlanCase) {
        let rng = ScriptedRNG(c.rng)
        let plan = planForGame(c.model, mode: c.mode, aiColor: c.aiColor, rng: { rng.next() })
        #expect(plan == c.plan.plan)
        #expect(plan.notes == c.plan.notes)
        #expect(rng.consumed == c.consumed)
        #expect(rng.exhaustedCalls == 0)
        // The plan's elo is the target elo re-derived from the skill.
        #expect(plan.aiElo == skillToElo(plan.skill))
        #expect(plan.skill == eloToSkill(targetElo(c.model, mode: c.mode)))
    }

    @Test("the counter-plans and their explanations")
    func counterPlans() throws {
        func plan(_ name: String) throws -> AdaptationPlan {
            let c = try #require(fx.plans.first { $0.name == name })
            let rng = ScriptedRNG(c.rng)
            return planForGame(c.model, mode: c.mode, aiColor: c.aiColor, rng: { rng.next() })
        }
        let aggressive = try plan("aggressive-mirror")
        #expect(aggressive.params == EvalParams(aggression: -0.2, spaceWeight: 0, kingSafetyWeight: 0.8, closedPref: 0, mobilityWeight: 1))
        #expect(aggressive.bookTags == [.solid])
        #expect(aggressive.notes[0] == "You attack early, so I kept my king extra safe and played solid setups that punish overextension.")
        #expect(aggressive.mirrorOpening == "Italian Game")
        #expect(aggressive.notes[1] == "You favor the Italian Game — this time I tried it against you.")
        #expect(aggressive.notes[2] == "I watched for chances around your tactical shots.")

        let tactical = try plan("tactical-white")
        #expect(tactical.params == EvalParams(aggression: 0, spaceWeight: 0, kingSafetyWeight: 0.4, closedPref: 0.8, mobilityWeight: 1))
        #expect(tactical.bookTags == [.closed, .solid])
        #expect(tactical.notes[0] == "You thrive in tactics, so I steered toward closed positions with fewer combinations.")
        #expect(tactical.notes.last == "You were winning steadily, so I stepped up my level.")

        let defensive = try plan("defensive")
        #expect(defensive.params == EvalParams(aggression: 0.4, spaceWeight: 0.9, kingSafetyWeight: 0, closedPref: 0, mobilityWeight: 1))
        #expect(defensive.bookTags == [.space, .sharp])
        #expect(defensive.notes[0] == "You play patiently, so I grabbed space and squeezed slowly instead of forcing matters.")

        let positional = try plan("positional-tie")
        #expect(positional.params == EvalParams(aggression: 0.5, spaceWeight: 0, kingSafetyWeight: 0, closedPref: 0, mobilityWeight: 1.3))
        #expect(positional.bookTags == [.open, .sharp])
        #expect(positional.notes[0] == "You like quiet maneuvering, so I opened the position and created sharp play.")
        #expect(positional.notes[1] == "I expected your Queen's Gambit Declined and prepared against it.")
        #expect(positional.notes.last == "You were on a rough streak, so I eased off and allowed myself more human mistakes.")

        let materialistic = try plan("materialistic")
        #expect(materialistic.params == EvalParams(aggression: 0.5, spaceWeight: 0.4, kingSafetyWeight: 0, closedPref: 0, mobilityWeight: 1))
        #expect(materialistic.bookTags == [.sharp])
        #expect(materialistic.notes[0] == "You grab material readily, so I aimed for initiative and gambit-style pressure over pawns.")

        let fresh = try plan("fresh")
        #expect(fresh.params == .neutral)
        #expect(fresh.bookTags.isEmpty)
        #expect(fresh.mirrorOpening == nil)
        #expect(fresh.notes == ["Your style is still balanced — I played neutrally while I learn your patterns."])
        #expect(fresh.styleLabel == .balanced)
    }

    @Test("opening prep needs three games of the favourite and mirrors on a roll below 0.25")
    func openingPrep() {
        var m = PlayerModel()
        m.openings = [OpeningStat(name: "London System", count: 2, asWhite: 2, wins: 1)]
        let none = ScriptedRNG([])
        let p0 = planForGame(m, mode: .match, aiColor: .white, rng: { none.next() })
        #expect(p0.mirrorOpening == nil && none.consumed == 0)
        #expect(!p0.notes.contains { $0.contains("London System") })
        m.openings[0].count = 3
        let mirror = ScriptedRNG([0.2499])
        let p1 = planForGame(m, mode: .match, aiColor: .white, rng: { mirror.next() })
        #expect(p1.mirrorOpening == "London System")
        #expect(p1.notes.contains("You favor the London System — this time I tried it against you."))
        let prepared = ScriptedRNG([0.25])
        let p2 = planForGame(m, mode: .match, aiColor: .white, rng: { prepared.next() })
        #expect(p2.mirrorOpening == nil)
        #expect(p2.notes.contains("I expected your London System and prepared against it."))
    }

    @Test("the weakness note names every key like the TS")
    func weaknessNotes() {
        let names: [WeaknessKey: String] = [
            .hangingPieces: "undefended pieces", .missedTactics: "tactical shots", .backRank: "back-rank weaknesses",
            .endgame: "endgame technique", .opening: "opening play", .kingSafety: "king safety",
        ]
        for key in WeaknessKey.allCases {
            var m = PlayerModel()
            m.weaknesses[key] = 1
            let plan = planForGame(m, mode: .match, aiColor: .white, rng: { 0.5 })
            #expect(plan.notes.contains("I watched for chances around your \(names[key]!)."))
        }
    }

    @Test("aiColor does not change the plan (closedSign is 1 for both colours in the TS)")
    func aiColorIgnored() {
        for c in fx.plans {
            let w = ScriptedRNG(c.rng), b = ScriptedRNG(c.rng)
            #expect(planForGame(c.model, mode: c.mode, aiColor: .white, rng: { w.next() }) ==
                planForGame(c.model, mode: c.mode, aiColor: .black, rng: { b.next() }))
        }
    }

    @Test("pickBookMove", arguments: AdaptationFixtures.shared.pickBook)
    func pickBook(_ c: AdaptationFixtures.PickBookCase) {
        let plan = AdaptationPlan(skill: 10, aiElo: 1400, params: .neutral, bookTags: c.bookTags, mirrorOpening: nil, notes: [], styleLabel: .balanced)
        let rng = ScriptedRNG(c.rng)
        #expect(pickBookMove(c.sans, plan: plan, rng: { rng.next() }) == c.result)
        #expect(rng.consumed == c.consumed)
        #expect(rng.exhaustedCalls == 0)
    }
}
