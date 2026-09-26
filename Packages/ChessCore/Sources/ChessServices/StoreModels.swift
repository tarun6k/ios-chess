// The persisted game records of src/app/store.ts: `GameMode`, `SavedGame`, `ArchivedGame`, plus
// the `[number, number]` clock tuple. Their JSON is exactly what the TS app writes with
// JSON.stringify: same keys, `null` where the TS type says `| null`, and "w"/"b" for the player
// colour. The remaining store types (Settings, PlayerModel, Progress, RecordedMistake) arrive
// with Store.swift in Phase 5.

import ChessCore

public enum GameMode: String, Codable, Hashable, Sendable, CaseIterable {
    case pvp
    case ai
    case puzzle
    case drill
    case constraint
}

/// TS `[number, number]`: milliseconds remaining for white and black, encoded as a 2-element array.
public struct ClockRemaining: Hashable, Sendable {
    public var white: Int
    public var black: Int

    public init(white: Int, black: Int) {
        self.white = white
        self.black = black
    }

    public subscript(color: PieceColor) -> Int {
        get { color == .white ? white : black }
        set { if color == .white { white = newValue } else { black = newValue } }
    }
}

extension ClockRemaining: Codable {
    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        white = try c.decode(Int.self)
        black = try c.decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(white)
        try c.encode(black)
    }
}

/// Serialized in-flight game — enough to resume exactly.
public struct SavedGame: Hashable, Sendable {
    public var mode: GameMode
    public var startFen: String
    public var uciMoves: [String]
    public var thinkMs: [Int]
    public var playerColor: PieceColor
    public var difficulty: DifficultyMode
    public var timeControl: TimeControl?
    public var clockRemaining: ClockRemaining?
    public var timerOn: Bool
    public var hintsLeft: Int
    /// puzzle/drill/constraint id when applicable
    public var challengeId: String?
    public var adaptationNotes: [String]
    /// Fractional: `eloToSkill` divides by 80.
    public var aiSkill: Double
    public var aiElo: Int
    /// `Date.now()` — Unix time in milliseconds.
    public var savedAt: Int

    public init(mode: GameMode, startFen: String, uciMoves: [String], thinkMs: [Int], playerColor: PieceColor,
                difficulty: DifficultyMode, timeControl: TimeControl?, clockRemaining: ClockRemaining?,
                timerOn: Bool, hintsLeft: Int, challengeId: String?, adaptationNotes: [String],
                aiSkill: Double, aiElo: Int, savedAt: Int) {
        self.mode = mode
        self.startFen = startFen
        self.uciMoves = uciMoves
        self.thinkMs = thinkMs
        self.playerColor = playerColor
        self.difficulty = difficulty
        self.timeControl = timeControl
        self.clockRemaining = clockRemaining
        self.timerOn = timerOn
        self.hintsLeft = hintsLeft
        self.challengeId = challengeId
        self.adaptationNotes = adaptationNotes
        self.aiSkill = aiSkill
        self.aiElo = aiElo
        self.savedAt = savedAt
    }
}

extension SavedGame: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode, startFen, uciMoves, thinkMs, playerColor, difficulty, timeControl, clockRemaining
        case timerOn, hintsLeft, challengeId, adaptationNotes, aiSkill, aiElo, savedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(GameMode.self, forKey: .mode)
        startFen = try c.decode(String.self, forKey: .startFen)
        uciMoves = try c.decode([String].self, forKey: .uciMoves)
        thinkMs = try c.decode([Int].self, forKey: .thinkMs)
        playerColor = try c.decode(PlayerColorCode.self, forKey: .playerColor).color
        difficulty = try c.decode(DifficultyMode.self, forKey: .difficulty)
        timeControl = try c.decodeIfPresent(TimeControl.self, forKey: .timeControl)
        clockRemaining = try c.decodeIfPresent(ClockRemaining.self, forKey: .clockRemaining)
        timerOn = try c.decode(Bool.self, forKey: .timerOn)
        hintsLeft = try c.decode(Int.self, forKey: .hintsLeft)
        challengeId = try c.decodeIfPresent(String.self, forKey: .challengeId)
        adaptationNotes = try c.decode([String].self, forKey: .adaptationNotes)
        aiSkill = try c.decode(Double.self, forKey: .aiSkill)
        aiElo = try c.decode(Int.self, forKey: .aiElo)
        savedAt = try c.decode(Int.self, forKey: .savedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(startFen, forKey: .startFen)
        try c.encode(uciMoves, forKey: .uciMoves)
        try c.encode(thinkMs, forKey: .thinkMs)
        try c.encode(PlayerColorCode(playerColor), forKey: .playerColor)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(timeControl, forKey: .timeControl)          // explicit null
        try c.encode(clockRemaining, forKey: .clockRemaining)    // explicit null
        try c.encode(timerOn, forKey: .timerOn)
        try c.encode(hintsLeft, forKey: .hintsLeft)
        try c.encode(challengeId, forKey: .challengeId)          // explicit null
        try c.encode(adaptationNotes, forKey: .adaptationNotes)
        try c.encode(aiSkill, forKey: .aiSkill)
        try c.encode(aiElo, forKey: .aiElo)
        try c.encode(savedAt, forKey: .savedAt)
    }
}

/// A finished game in the archive (as PGN plus enough to replay and analyse it).
public struct ArchivedGame: Hashable, Sendable {
    public var pgn: String
    public var mode: GameMode
    public var playerColor: PieceColor
    /// result message
    public var result: String
    /// 1-0 etc.
    public var score: String
    public var aiElo: Int?
    /// `Date.now()` — Unix time in milliseconds.
    public var date: Int
    public var analysis: [AnalyzedMove]?
    public var adaptationNotes: [String]
    public var startFen: String
    public var uciMoves: [String]

    public init(pgn: String, mode: GameMode, playerColor: PieceColor, result: String, score: String, aiElo: Int?,
                date: Int, analysis: [AnalyzedMove]?, adaptationNotes: [String], startFen: String, uciMoves: [String]) {
        self.pgn = pgn
        self.mode = mode
        self.playerColor = playerColor
        self.result = result
        self.score = score
        self.aiElo = aiElo
        self.date = date
        self.analysis = analysis
        self.adaptationNotes = adaptationNotes
        self.startFen = startFen
        self.uciMoves = uciMoves
    }
}

extension ArchivedGame: Codable {
    private enum CodingKeys: String, CodingKey {
        case pgn, mode, playerColor, result, score, aiElo, date, analysis, adaptationNotes, startFen, uciMoves
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pgn = try c.decode(String.self, forKey: .pgn)
        mode = try c.decode(GameMode.self, forKey: .mode)
        playerColor = try c.decode(PlayerColorCode.self, forKey: .playerColor).color
        result = try c.decode(String.self, forKey: .result)
        score = try c.decode(String.self, forKey: .score)
        aiElo = try c.decodeIfPresent(Int.self, forKey: .aiElo)
        date = try c.decode(Int.self, forKey: .date)
        analysis = try c.decodeIfPresent([AnalyzedMove].self, forKey: .analysis)
        adaptationNotes = try c.decode([String].self, forKey: .adaptationNotes)
        startFen = try c.decode(String.self, forKey: .startFen)
        uciMoves = try c.decode([String].self, forKey: .uciMoves)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pgn, forKey: .pgn)
        try c.encode(mode, forKey: .mode)
        try c.encode(PlayerColorCode(playerColor), forKey: .playerColor)
        try c.encode(result, forKey: .result)
        try c.encode(score, forKey: .score)
        try c.encode(aiElo, forKey: .aiElo)          // explicit null
        try c.encode(date, forKey: .date)
        try c.encode(analysis, forKey: .analysis)    // explicit null
        try c.encode(adaptationNotes, forKey: .adaptationNotes)
        try c.encode(startFen, forKey: .startFen)
        try c.encode(uciMoves, forKey: .uciMoves)
    }
}

/// The TS `'w' | 'b'` player-colour code used by the store records
/// (`playerColor === WHITE ? 'w' : 'b'` / `saved.playerColor === 'w' ? WHITE : BLACK`).
public enum PlayerColorCode: String, Codable, Hashable, Sendable {
    case w
    case b

    public init(_ color: PieceColor) { self = color == .white ? .w : .b }
    public var color: PieceColor { self == .w ? .white : .black }
}
