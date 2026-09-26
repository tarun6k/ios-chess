// Ported 1:1 from src/ai/persona.ts.
//
// TypeScript name → Swift name
//   Persona                          → Persona (skill / moveTimeMs are Doubles like the TS numbers; the
//                                       integral fields are Ints)
//   personaForSkill(skill, ms)       → personaForSkill(_:moveTimeMs:)
//   skillToElo / eloToSkill          → same names (Elo is integral: playerModel.ts rounds the rating)
//   gaussian(rng)                    → gaussian(_:) (internal, Box–Muller)
//   chooseMove(rootMoves, p, rng)    → chooseMove(_:persona:rng:) — `rng` is a `() -> Double` in [0, 1)
//                                       like `Math.random`, injectable for tests

import Darwin

/// Skill → search budget and human-like error model.
///
/// skill 0..20 maps roughly onto 600..2200 Elo. Two mechanisms produce
/// plausible (not random) mistakes:
///  1. Gaussian evaluation noise before choosing among root moves — weaker
///     "eyes": close alternatives become interchangeable.
///  2. Occasional deliberate pick of a mildly worse candidate (bounded loss),
///     which reads as a human inaccuracy, never a piece hung for nothing —
///     EXCEPT at very low skill, where bounded real blunders are allowed.
public struct Persona: Hashable, Sendable, Codable {
    /// 0..20
    public var skill: Double
    public var maxDepth: Int
    public var moveTimeMs: Double
    /// sigma of gaussian noise applied to root scores
    public var noiseCp: Int
    /// never pick a move more than this below the best
    public var maxDropCp: Int
    /// chance to consider the wider (worse) candidate set
    public var blunderRate: Double

    public init(skill: Double, maxDepth: Int, moveTimeMs: Double, noiseCp: Int, maxDropCp: Int, blunderRate: Double) {
        self.skill = skill
        self.maxDepth = maxDepth
        self.moveTimeMs = moveTimeMs
        self.noiseCp = noiseCp
        self.maxDropCp = maxDropCp
        self.blunderRate = blunderRate
    }
}

public func personaForSkill(_ skill: Double, moveTimeMs: Double) -> Persona {
    let s = max(0, min(20, skill))
    return Persona(
        skill: s,
        maxDepth: s <= 2 ? 2 : s <= 6 ? 3 : s <= 11 ? 4 : s <= 16 ? 5 : 8,
        moveTimeMs: moveTimeMs,
        noiseCp: jsRound((20 - s) * (20 - s) * 0.55),        // 0 @20 … 220 @0
        maxDropCp: s >= 15 ? 30 : s >= 10 ? 80 : s >= 5 ? 160 : 320,
        blunderRate: s >= 15 ? 0.02 : s >= 10 ? 0.06 : s >= 5 ? 0.12 : 0.22
    )
}

/// Approximate Elo for a skill level (for display and rating updates).
public func skillToElo(_ skill: Double) -> Int {
    jsRound(600 + max(0, min(20, skill)) * 80)
}

public func eloToSkill(_ elo: Int) -> Double {
    max(0, min(20, Double(elo - 600) / 80))
}

/// Standard normal deviate by Box–Muller, exactly as persona.ts computes it.
func gaussian(_ rng: () -> Double) -> Double {
    var u = 0.0, v = 0.0
    while u == 0 { u = rng() }
    while v == 0 { v = rng() }
    return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
}

/// JS `Math.random()`: uniform in [0, 1).
@Sendable public func systemUnitRandom() -> Double {
    Double.random(in: 0..<1)
}

/// Choose the move to play from exact-scored root moves (best first).
/// Returns the chosen index into rootMoves.
public func chooseMove(_ rootMoves: [RootMove], persona: Persona, rng: () -> Double = systemUnitRandom) -> Int {
    if rootMoves.count <= 1 { return 0 }
    let best = rootMoves[0].score

    // Never throw away a found mate, and never walk into one if avoidable.
    if best > mateScore - 1000 { return 0 }

    let blunderWindow = rng() < persona.blunderRate
    let drop = blunderWindow ? persona.maxDropCp : min(persona.maxDropCp, 60)

    // Candidates: within `drop` cp of best, and not losing on the spot.
    let floor = best - drop
    var candidates: [Int] = []
    for i in 0..<rootMoves.count {
        let s = rootMoves[i].score
        if s < floor { break } // sorted
        if s < -(mateScore - 1000) + 2000 && best > -(mateScore - 1000) { continue } // don't pick a forced loss
        candidates.append(i)
    }
    if candidates.isEmpty { return 0 }

    // Perceived score = true score + noise; pick the max.
    var bestIdx = candidates[0]
    var bestPerceived = -Double.infinity
    for i in candidates {
        let perceived = Double(rootMoves[i].score) + gaussian(rng) * Double(persona.noiseCp)
        if perceived > bestPerceived { bestPerceived = perceived; bestIdx = i }
    }
    return bestIdx
}
