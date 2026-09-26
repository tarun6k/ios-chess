// TS `TimeControl` from src/app/clock.ts. The presets, `customTimeControl` and the `ChessClock`
// class follow in Phase 5 (ChessClock.swift); the model lives here already because `SavedGame`
// persists it. The optional per-side overrides are omitted from JSON when nil, as JSON.stringify
// omits `undefined` properties.

public struct TimeControl: Codable, Hashable, Sendable {
    public var name: String
    /// base time in ms per player; asymmetric handicaps use baseMs overrides
    public var baseMs: Int
    public var incrementMs: Int
    /// optional per-side override (AI handicap challenges)
    public var whiteBaseMs: Int?
    public var blackBaseMs: Int?

    public init(name: String, baseMs: Int, incrementMs: Int, whiteBaseMs: Int? = nil, blackBaseMs: Int? = nil) {
        self.name = name
        self.baseMs = baseMs
        self.incrementMs = incrementMs
        self.whiteBaseMs = whiteBaseMs
        self.blackBaseMs = blackBaseMs
    }
}
