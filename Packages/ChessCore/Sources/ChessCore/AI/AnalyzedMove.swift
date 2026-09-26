// TS `Judgment` and `AnalyzedMove` from src/ai/protocol.ts. The worker protocol itself is ported in
// Phase 3; these two types live here already because `ArchivedGame.analysis` persists them.

public enum Judgment: String, Codable, Hashable, Sendable, CaseIterable {
    case best
    case good
    case inaccuracy
    case mistake
    case blunder
}

/// One reviewed ply of post-game analysis. Evaluations are integral centipawns (the TS search
/// scores are `Math.round`ed evals and mate scores), so they are `Int`.
public struct AnalyzedMove: Codable, Hashable, Sendable {
    public var uci: String
    /// eval (white POV, cp) after the move was played
    public var evalAfter: Int
    /// eval (white POV, cp) of the position before the move, i.e. best play
    public var evalBefore: Int
    public var bestUci: String
    public var judgment: Judgment
    /// centipawn loss from the mover's perspective
    public var cpLoss: Int

    public init(uci: String, evalAfter: Int, evalBefore: Int, bestUci: String, judgment: Judgment, cpLoss: Int) {
        self.uci = uci
        self.evalAfter = evalAfter
        self.evalBefore = evalBefore
        self.bestUci = bestUci
        self.judgment = judgment
        self.cpLoss = cpLoss
    }
}
