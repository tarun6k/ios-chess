// TS src/app/puzzles.ts: the curated challenges. Every puzzle here was verified with the app's own
// search engine (see PuzzleValidityTests): mate-in-N puzzles have a forced mate in exactly N, tactics
// have a clear best move. The data is copied verbatim.

import ChessCore

public enum PuzzleKind: String, Codable, Hashable, Sendable, CaseIterable {
    case mate1
    case mate2
    case mate3
    case tactic
    case defense

    /// N for the `mateN` kinds (TS `parseInt(p.kind.slice(4), 10)`), nil for tactics and defence.
    public var mateIn: Int? {
        rawValue.hasPrefix("mate") ? Int(rawValue.dropFirst(4)) : nil
    }
}

public struct Puzzle: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: PuzzleKind
    /// 1 = easy … 3 = hard
    public var tier: Int
    public var title: String
    public var fen: String
    /// engine-best first move, used for hints and "solution" display
    public var solution: String
    public var prompt: String
    public var xp: Int

    public init(id: String, kind: PuzzleKind, tier: Int, title: String, fen: String, solution: String, prompt: String, xp: Int) {
        self.id = id
        self.kind = kind
        self.tier = tier
        self.title = title
        self.fen = fen
        self.solution = solution
        self.prompt = prompt
        self.xp = xp
    }
}

/// TS `PUZZLES`.
public let puzzles: [Puzzle] = [
    Puzzle(id: "m1-backrank", kind: .mate1, tier: 1, title: "Back-rank strike", fen: "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", solution: "a1a8", prompt: "White mates in one.", xp: 10),
    Puzzle(id: "m1-corner", kind: .mate1, tier: 1, title: "Cornered king", fen: "k7/8/1K6/8/8/8/8/7R w - - 0 1", solution: "h1h8", prompt: "White mates in one.", xp: 10),
    Puzzle(id: "m1-longdiag", kind: .mate1, tier: 1, title: "The long reach", fen: "7k/6pp/8/8/8/8/8/Q6K w - - 0 1", solution: "a1a8", prompt: "White mates in one.", xp: 10),
    Puzzle(id: "m1-seventh", kind: .mate1, tier: 1, title: "Rooks on rampage", fen: "7k/R7/1R6/8/8/8/8/4K3 w - - 0 1", solution: "b6b8", prompt: "White mates in one.", xp: 10),
    Puzzle(id: "m1-deflect", kind: .mate1, tier: 2, title: "Take with tempo", fen: "3r2k1/5ppp/8/8/8/8/5PPP/3QR1K1 w - - 0 1", solution: "d1d8", prompt: "White mates in one.", xp: 15),
    Puzzle(id: "m2-ladder", kind: .mate2, tier: 2, title: "Ladder finish", fen: "7k/8/8/8/8/8/1R6/R3K3 w - - 0 1", solution: "a1a7", prompt: "White mates in two.", xp: 20),
    Puzzle(id: "m2-boxin", kind: .mate2, tier: 2, title: "Boxed in", fen: "6k1/8/5K2/8/8/8/8/1Q6 w - - 0 1", solution: "b1g6", prompt: "White mates in two.", xp: 20),
    Puzzle(id: "m2-qr", kind: .mate2, tier: 2, title: "Heavy pieces", fen: "3k4/8/8/8/8/8/Q6R/4K3 w - - 0 1", solution: "a2f7", prompt: "White mates in two.", xp: 20),
    Puzzle(id: "m3-squeeze", kind: .mate3, tier: 3, title: "The slow squeeze", fen: "6k1/8/8/5K2/8/8/8/1Q6 w - - 0 1", solution: "b1b7", prompt: "White mates in three.", xp: 35),
    Puzzle(id: "t-freequeen", kind: .tactic, tier: 1, title: "Loose piece", fen: "1q5k/8/8/8/8/8/8/KR6 w - - 0 1", solution: "b1b8", prompt: "White wins material.", xp: 10),
    Puzzle(id: "t-snipe", kind: .tactic, tier: 1, title: "Long diagonal snipe", fen: "r3k3/8/8/8/8/8/5PB1/4K3 w - - 0 1", solution: "g2a8", prompt: "White wins material.", xp: 10),
    Puzzle(id: "t-fork", kind: .tactic, tier: 2, title: "Family fork", fen: "q3k3/8/8/3N4/8/8/6P1/4K3 w - - 0 1", solution: "d5c7", prompt: "White wins the queen.", xp: 20),
    Puzzle(id: "t-pin", kind: .tactic, tier: 2, title: "Pile on the pin", fen: "4k3/4r3/8/8/8/8/4R3/4K1B1 w - - 0 1", solution: "g1e3", prompt: "Exploit the pin to win material.", xp: 20),
    Puzzle(id: "t-promo", kind: .tactic, tier: 2, title: "Touchdown", fen: "4k3/P7/8/8/8/8/6p1/4K3 w - - 0 1", solution: "a7a8q", prompt: "Find the strongest continuation.", xp: 15),
    Puzzle(id: "d-qsave", kind: .defense, tier: 2, title: "Save the queen", fen: "rnb1kbnr/pppp1ppp/8/4p3/4P1q1/5P2/PPPP2PP/RNBQKBNR b KQkq - 0 3", solution: "g4h4", prompt: "Black to move — rescue the attacked queen.", xp: 15),
]

public enum DrillGoal: String, Codable, Hashable, Sendable, CaseIterable {
    case win
    case draw
}

public struct Drill: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var fen: String
    /// side the player takes
    public var playerColor: PieceColor
    public var goal: DrillGoal
    public var description: String
    public var xp: Int

    public init(id: String, title: String, fen: String, playerColor: PieceColor, goal: DrillGoal, description: String, xp: Int) {
        self.id = id
        self.title = title
        self.fen = fen
        self.playerColor = playerColor
        self.goal = goal
        self.description = description
        self.xp = xp
    }
}

extension Drill: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, fen, playerColor, goal, description, xp
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        fen = try c.decode(String.self, forKey: .fen)
        playerColor = try c.decode(PlayerColorCode.self, forKey: .playerColor).color
        goal = try c.decode(DrillGoal.self, forKey: .goal)
        description = try c.decode(String.self, forKey: .description)
        xp = try c.decode(Int.self, forKey: .xp)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(fen, forKey: .fen)
        try c.encode(PlayerColorCode(playerColor), forKey: .playerColor)
        try c.encode(goal, forKey: .goal)
        try c.encode(description, forKey: .description)
        try c.encode(xp, forKey: .xp)
    }
}

/// TS `DRILLS`.
public let drills: [Drill] = [
    Drill(id: "kp-vs-k", title: "King & pawn vs king",
          fen: "8/8/8/4k3/8/8/4P3/4K3 w - - 0 1", playerColor: .white, goal: .win,
          description: "Escort the pawn home. Use the opposition — king in front of the pawn.", xp: 30),
    Drill(id: "opposition", title: "The opposition",
          fen: "8/8/8/3k4/8/3K4/3P4/8 w - - 0 1", playerColor: .white, goal: .win,
          description: "Win the pawn ending by taking the opposition at the right moment.", xp: 30),
    Drill(id: "lucena", title: "Rook ending: build the bridge",
          fen: "1K1k4/1P6/8/8/8/8/r7/2R5 w - - 0 1", playerColor: .white, goal: .win,
          description: "The Lucena position. Shelter your king from checks and promote.", xp: 45),
    Drill(id: "defend-kp", title: "Hold the draw",
          fen: "4k3/8/8/4P3/4K3/8/8/8 b - - 0 1", playerColor: .black, goal: .draw,
          description: "Defend king vs king-and-pawn. Stay in front and keep the opposition.", xp: 30),
]

public enum ConstraintKind: String, Codable, Hashable, Sendable, CaseIterable {
    case silentQueen = "silent-queen"
    case knightMate = "knight-mate"
    case rookOdds = "rook-odds"
}

public struct ConstraintGame: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: ConstraintKind
    public var title: String
    public var description: String
    /// start position (standard unless odds); omitted from JSON when nil like the TS optional
    public var fen: String?
    public var xp: Int

    public init(id: String, kind: ConstraintKind, title: String, description: String, fen: String? = nil, xp: Int) {
        self.id = id
        self.kind = kind
        self.title = title
        self.description = description
        self.fen = fen
        self.xp = xp
    }
}

/// TS `CONSTRAINTS`.
public let constraints: [ConstraintGame] = [
    ConstraintGame(id: "c-silent-queen", kind: .silentQueen, title: "The silent queen",
                   description: "Beat the AI without ever moving your queen.", xp: 60),
    ConstraintGame(id: "c-knight-mate", kind: .knightMate, title: "Knight's honor",
                   description: "Beat the AI — the mating move must be made by a knight.", xp: 80),
    ConstraintGame(id: "c-rook-odds", kind: .rookOdds, title: "Down a rook",
                   description: "You start without your queenside rook. Survive 20 moves without being checkmated.",
                   fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/1NBQKBNR w Kkq - 0 1", xp: 50),
]
