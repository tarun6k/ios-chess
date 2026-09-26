// Ported 1:1 from src/ai/adaptation.ts — turns the player model into concrete AI behavior:
//  - rubber-band difficulty (Learn / Match / Challenge)
//  - eval-parameter counter-play against the player's style
//  - opening preparation against (or mirroring) the player's repertoire
//
// TypeScript name → Swift name
//   DifficultyMode                 → DifficultyMode (DifficultyMode.swift, persisted by SavedGame since Phase 2)
//   AdaptationPlan                 → same name; `bookTags: string[]` → `[OpeningTag]`
//   targetElo(model, mode)         → targetElo(_:mode:)
//   planForGame(model, mode, ai)   → planForGame(_:mode:aiColor:rng:) — `Math.random` is the injected `rng`
//   pickBookMove(sans, plan)       → pickBookMove(_:plan:rng:)

public struct AdaptationPlan: Hashable, Sendable {
    public var skill: Double
    public var aiElo: Int
    public var params: EvalParams
    /// book tags the AI prefers this game
    public var bookTags: [OpeningTag]
    /// chance to mirror the player's own favorite opening
    public var mirrorOpening: String?
    /// human-readable notes shown in the post-game "how I adapted" summary
    public var notes: [String]
    public var styleLabel: StyleLabel

    public init(skill: Double, aiElo: Int, params: EvalParams, bookTags: [OpeningTag], mirrorOpening: String?,
                notes: [String], styleLabel: StyleLabel) {
        self.skill = skill
        self.aiElo = aiElo
        self.params = params
        self.bookTags = bookTags
        self.mirrorOpening = mirrorOpening
        self.notes = notes
        self.styleLabel = styleLabel
    }
}

/// Target AI elo for a mode, with losing-streak easing and win hardening.
public func targetElo(_ model: PlayerModel, mode: DifficultyMode) -> Int {
    let offset = mode == .learn ? -90 : mode == .challenge ? 90 : 0
    // Rubber band: each win nudges the AI up, a losing streak eases it off.
    let band = max(-120, min(120, model.streak * 25))
    return max(600, min(2200, model.rating + offset + band))
}

/// TS `names` in planForGame: how a weakness is described in the adaptation note.
private let weaknessDisplayNames: [WeaknessKey: String] = [
    .hangingPieces: "undefended pieces",
    .missedTactics: "tactical shots",
    .backRank: "back-rank weaknesses",
    .endgame: "endgame technique",
    .opening: "opening play",
    .kingSafety: "king safety",
]

/// - Parameter rng: uniform [0, 1) source for the 25 % mirror-opening roll (TS `Math.random`).
public func planForGame(_ model: PlayerModel, mode: DifficultyMode, aiColor: PieceColor,
                        rng: () -> Double = systemUnitRandom) -> AdaptationPlan {
    let label = classifyStyle(model.features).label
    var notes: [String] = []
    var params = EvalParams.neutral
    var bookTags: [OpeningTag] = []

    // closedPref is a white-positive eval term; flip so it favors the AI's wish.
    // TS: `const closedSign = aiColor === WHITE ? 1 : 1;` — both branches are 1, so `aiColor` has no effect
    // (see "Faithfully-ported bugs" in PORTING_PLAN.md).
    let closedSign: Double = 1
    switch label {
    case .aggressive:
        params.kingSafetyWeight = 0.8
        params.aggression = -0.2
        bookTags = [.solid]
        notes.append("You attack early, so I kept my king extra safe and played solid setups that punish overextension.")
    case .tactical:
        params.closedPref = 0.8 * closedSign
        params.kingSafetyWeight = 0.4
        bookTags = [.closed, .solid]
        notes.append("You thrive in tactics, so I steered toward closed positions with fewer combinations.")
    case .defensive:
        params.spaceWeight = 0.9
        params.aggression = 0.4
        bookTags = [.space, .sharp]
        notes.append("You play patiently, so I grabbed space and squeezed slowly instead of forcing matters.")
    case .positional:
        params.aggression = 0.5
        params.mobilityWeight = 1.3
        bookTags = [.open, .sharp]
        notes.append("You like quiet maneuvering, so I opened the position and created sharp play.")
    case .materialistic:
        params.aggression = 0.5
        params.spaceWeight = 0.4
        bookTags = [.sharp]
        notes.append("You grab material readily, so I aimed for initiative and gambit-style pressure over pawns.")
    case .balanced:
        notes.append("Your style is still balanced — I played neutrally while I learn your patterns.")
    }

    // Opening preparation
    var mirrorOpening: String? = nil
    if let fav = model.openings.first, fav.count >= 3 {
        if rng() < 0.25 {
            mirrorOpening = fav.name
            notes.append("You favor the \(fav.name) — this time I tried it against you.")
        } else {
            notes.append("I expected your \(fav.name) and prepared against it.")
        }
    }

    // Weakness exploitation note (the exploitation itself emerges from play +
    // targeted challenges; we surface intent honestly).
    if let weak = topWeaknesses(model, n: 1).first {
        notes.append("I watched for chances around your \(weaknessDisplayNames[weak.key] ?? weak.key.rawValue).")
    }

    let elo = targetElo(model, mode: mode)
    let skill = eloToSkill(elo)
    if model.streak <= -3 {
        notes.append("You were on a rough streak, so I eased off and allowed myself more human mistakes.")
    } else if model.streak >= 3 {
        notes.append("You were winning steadily, so I stepped up my level.")
    }

    return AdaptationPlan(skill: skill, aiElo: skillToElo(skill), params: params, bookTags: bookTags,
                          mirrorOpening: mirrorOpening, notes: notes, styleLabel: label)
}

/// Pick a book move for the AI given the SAN line so far, or nil.
/// - Parameter rng: uniform [0, 1) source for the pick (TS `Math.random`).
public func pickBookMove(_ sans: [String], plan: AdaptationPlan, rng: () -> Double = systemUnitRandom) -> String? {
    if sans.count >= 10 { return nil }
    // Mirroring: follow the favorite opening's own line where possible (it is in
    // the BOOK by name), otherwise use tag-preferred continuations.
    let options = bookContinuations(sans, preferTags: plan.bookTags.isEmpty ? nil : plan.bookTags)
    if options.isEmpty { return nil }
    return options[min(options.count - 1, Int(rng() * Double(options.count)))]
}
