// TS src/app/progression.ts: XP, levels, badges, daily challenge and streaks. `Date.now()` / `new Date()`
// are injected as `now:` / `date` parameters (defaulting to the current time); the day key is the UTC
// calendar day like `toISOString().slice(0, 10)`.

import Foundation
import ChessCore

public struct ProgressCounters: Codable, Hashable, Sendable {
    public var gamesPlayed = 0
    public var gamesWon = 0
    /// consecutive games with castling
    public var castledGames = 0
    public var winsOnTime = 0
    public var puzzlesSolved = 0
    public var checkmates = 0
    public var enPassants = 0
    public var underpromotions = 0
    public var hintsUsed = 0

    public init() {}

    /// store.ts `{ ...newProgress().counters, ...progress.counters }`: missing counters take the defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gamesPlayed = try c.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0
        gamesWon = try c.decodeIfPresent(Int.self, forKey: .gamesWon) ?? 0
        castledGames = try c.decodeIfPresent(Int.self, forKey: .castledGames) ?? 0
        winsOnTime = try c.decodeIfPresent(Int.self, forKey: .winsOnTime) ?? 0
        puzzlesSolved = try c.decodeIfPresent(Int.self, forKey: .puzzlesSolved) ?? 0
        checkmates = try c.decodeIfPresent(Int.self, forKey: .checkmates) ?? 0
        enPassants = try c.decodeIfPresent(Int.self, forKey: .enPassants) ?? 0
        underpromotions = try c.decodeIfPresent(Int.self, forKey: .underpromotions) ?? 0
        hintsUsed = try c.decodeIfPresent(Int.self, forKey: .hintsUsed) ?? 0
    }
}

/// TS `Progress` (renamed: Foundation already exports a `Progress` class); `PlayerProgress()` is `newProgress()`.
public struct PlayerProgress: Hashable, Sendable {
    public var xp = 0
    /// earned badge ids
    public var badges: [String] = []
    /// puzzle ids
    public var solvedPuzzles: [String] = []
    public var completedDrills: [String] = []
    public var completedConstraints: [String] = []
    public var dailyStreak = 0
    /// YYYY-MM-DD of last completed daily
    public var lastDailyDate: String? = nil
    public var counters = ProgressCounters()

    public init() {}
}

extension PlayerProgress: Codable {
    private enum CodingKeys: String, CodingKey {
        case xp, badges, solvedPuzzles, completedDrills, completedConstraints, dailyStreak, lastDailyDate, counters
    }

    /// store.ts `{ ...newProgress(), ...progress, counters: { ...newProgress().counters, ...progress.counters } }`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        badges = try c.decodeIfPresent([String].self, forKey: .badges) ?? []
        solvedPuzzles = try c.decodeIfPresent([String].self, forKey: .solvedPuzzles) ?? []
        completedDrills = try c.decodeIfPresent([String].self, forKey: .completedDrills) ?? []
        completedConstraints = try c.decodeIfPresent([String].self, forKey: .completedConstraints) ?? []
        dailyStreak = try c.decodeIfPresent(Int.self, forKey: .dailyStreak) ?? 0
        lastDailyDate = try c.decodeIfPresent(String.self, forKey: .lastDailyDate)
        counters = try c.decodeIfPresent(ProgressCounters.self, forKey: .counters) ?? ProgressCounters()
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(xp, forKey: .xp)
        try c.encode(badges, forKey: .badges)
        try c.encode(solvedPuzzles, forKey: .solvedPuzzles)
        try c.encode(completedDrills, forKey: .completedDrills)
        try c.encode(completedConstraints, forKey: .completedConstraints)
        try c.encode(dailyStreak, forKey: .dailyStreak)
        try c.encode(lastDailyDate, forKey: .lastDailyDate)    // explicit null (TS `string | null`)
        try c.encode(counters, forKey: .counters)
    }
}

public struct LevelInfo: Hashable, Sendable {
    public var level: Int
    public var into: Int
    public var needed: Int

    public init(level: Int, into: Int, needed: Int) {
        self.level = level
        self.into = into
        self.needed = needed
    }
}

/// level n needs 100 * n XP to advance (100, 200, 300 …)
public func levelForXp(_ xp: Int) -> LevelInfo {
    var level = 1, remaining = xp
    while remaining >= level * 100 {
        remaining -= level * 100
        level += 1
    }
    return LevelInfo(level: level, into: remaining, needed: level * 100)
}

public struct Badge: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let earned: @Sendable (PlayerProgress, PlayerModel) -> Bool

    public init(id: String, title: String, description: String, earned: @escaping @Sendable (PlayerProgress, PlayerModel) -> Bool) {
        self.id = id
        self.title = title
        self.description = description
        self.earned = earned
    }
}

extension Badge: Hashable {
    public static func == (lhs: Badge, rhs: Badge) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// TS `BADGES`.
public let badges: [Badge] = [
    Badge(id: "first-win", title: "First blood", description: "Win your first game") { p, _ in p.counters.gamesWon >= 1 },
    Badge(id: "first-mate", title: "Checkmate!", description: "Deliver your first checkmate") { p, _ in p.counters.checkmates >= 1 },
    Badge(id: "castle-10", title: "Safe as houses", description: "Castle in 10 games in a row") { p, _ in p.counters.castledGames >= 10 },
    Badge(id: "flag-win", title: "Beat the clock", description: "Win a game on time") { p, _ in p.counters.winsOnTime >= 1 },
    Badge(id: "puzzle-10", title: "Sharp eyes", description: "Solve 10 puzzles") { p, _ in p.counters.puzzlesSolved >= 10 },
    Badge(id: "puzzle-50", title: "Tactician", description: "Solve 50 puzzles") { p, _ in p.counters.puzzlesSolved >= 50 },
    Badge(id: "en-passant", title: "In passing", description: "Capture en passant") { p, _ in p.counters.enPassants >= 1 },
    Badge(id: "underpromo", title: "Less is more", description: "Underpromote a pawn") { p, _ in p.counters.underpromotions >= 1 },
    Badge(id: "streak-3", title: "On a roll", description: "Three-day challenge streak") { p, _ in p.dailyStreak >= 3 },
    Badge(id: "streak-7", title: "Habit formed", description: "Seven-day challenge streak") { p, _ in p.dailyStreak >= 7 },
    Badge(id: "rating-1200", title: "Club player", description: "Reach a 1200 rating") { _, m in m.rating >= 1200 },
    Badge(id: "rating-1600", title: "Strong player", description: "Reach a 1600 rating") { _, m in m.rating >= 1600 },
    Badge(id: "giant-slayer", title: "Giant slayer", description: "Beat the AI set 200+ above your rating") { p, _ in p.badges.contains("giant-slayer") },
    Badge(id: "games-25", title: "Regular", description: "Play 25 games") { p, _ in p.counters.gamesPlayed >= 25 },
]

/// Recompute earned badges; returns newly earned ones.
@discardableResult
public func refreshBadges(_ p: inout PlayerProgress, _ m: PlayerModel) -> [Badge] {
    var fresh: [Badge] = []
    for b in badges {
        if !p.badges.contains(b.id) && b.earned(p, m) {
            p.badges.append(b.id)
            fresh.append(b)
        }
    }
    return fresh
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}()

/// TS `d.toISOString().slice(0, 10)`: the UTC calendar day as `YYYY-MM-DD`.
func dateKey(_ d: Date = Date()) -> String {
    let c = utcCalendar.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// The daily seed: `h = (h * 31 + charCode) >>> 0` over the day key's UTF-16 units.
func dailySeed(_ key: String) -> UInt32 {
    var h: UInt32 = 0
    for unit in key.utf16 { h = h &* 31 &+ UInt32(unit) }
    return h
}

/// Deterministic daily puzzle: seeded by the (UTC) calendar day.
public func dailyPuzzle(_ date: Date = Date()) -> Puzzle {
    let h = dailySeed(dateKey(date))
    return puzzles[Int(h % UInt32(puzzles.count))]
}

/// Marks today's daily as done: extends the streak when yesterday's was done, else restarts it at 1.
public func completeDaily(_ p: inout PlayerProgress, now: Date = Date()) {
    let today = dateKey(now)
    if p.lastDailyDate == today { return }
    let yesterday = dateKey(now.addingTimeInterval(-86_400))
    p.dailyStreak = p.lastDailyDate == yesterday ? p.dailyStreak + 1 : 1
    p.lastDailyDate = today
}

public func isDailyDone(_ p: PlayerProgress, now: Date = Date()) -> Bool {
    p.lastDailyDate == dateKey(now)
}

public enum OfferKind: String, Codable, Hashable, Sendable, CaseIterable {
    case puzzleSet = "puzzle-set"
    case rematchBlitz = "rematch-blitz"
    case drill
    case constraint
}

/// TS `OfferedChallenge`; the optional fields are omitted from JSON when nil like the TS `?:` properties.
public struct OfferedChallenge: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: OfferKind
    public var title: String
    public var detail: String
    public var puzzleIds: [String]? = nil
    public var drillId: String? = nil
    public var constraintId: String? = nil
    public var timed: Bool? = nil
    public var xp: Int

    public init(id: String, kind: OfferKind, title: String, detail: String, puzzleIds: [String]? = nil, drillId: String? = nil,
                constraintId: String? = nil, timed: Bool? = nil, xp: Int) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.puzzleIds = puzzleIds
        self.drillId = drillId
        self.constraintId = constraintId
        self.timed = timed
        self.xp = xp
    }
}

/// TS `WEAKNESS_PUZZLES`.
func weaknessPuzzles(_ key: WeaknessKey) -> [String] {
    switch key {
    case .hangingPieces: return ["t-freequeen", "t-snipe", "d-qsave"]
    case .missedTactics: return ["t-fork", "t-pin", "t-promo"]
    case .backRank: return ["m1-backrank", "m1-deflect", "m2-ladder"]
    case .endgame: return []
    case .opening: return []
    case .kingSafety: return ["m1-backrank", "m2-boxin", "m2-qr"]
    }
}

/// TS `WEAKNESS_LABEL`.
func weaknessLabel(_ key: WeaknessKey) -> String {
    switch key {
    case .hangingPieces: return "leaving pieces undefended"
    case .missedTactics: return "missing tactical shots"
    case .backRank: return "back-rank mates"
    case .endgame: return "endgame technique"
    case .opening: return "the opening phase"
    case .kingSafety: return "king safety"
    }
}

/// AI-offered challenges after a game — driven by the player model: targeted puzzle sets for the top
/// weakness, drills for endgame gaps, and a spicy rematch offer. `lastGameWon` is nil when no real
/// game was just played.
public func offerChallenges(_ model: PlayerModel, _ progress: PlayerProgress, lastGameWon: Bool?) -> [OfferedChallenge] {
    var offers: [OfferedChallenge] = []
    let weak = topWeaknesses(model, n: 2)

    for entry in weak {
        let key = entry.key
        if key == .endgame {
            let drill = drills.first { !progress.completedDrills.contains($0.id) } ?? drills[0]
            offers.append(OfferedChallenge(
                id: "offer-drill-" + drill.id, kind: .drill,
                title: "Endgame clinic",
                detail: "Your endgame technique has been costing you — try “\(drill.title)”.",
                drillId: drill.id, xp: drill.xp))
        } else {
            let ids = weaknessPuzzles(key).filter { id in puzzles.contains { $0.id == id } }
            if !ids.isEmpty {
                offers.append(OfferedChallenge(
                    id: "offer-puzzles-" + key.rawValue, kind: .puzzleSet,
                    title: "Targeted training",
                    detail: "You struggle with \(weaknessLabel(key)) — try these \(ids.count) puzzles.",
                    puzzleIds: ids, xp: ids.count * 10))
            }
        }
        if offers.count >= 2 { break }
    }

    if let lastGameWon {
        offers.append(OfferedChallenge(
            id: "offer-rematch", kind: .rematchBlitz,
            title: lastGameWon ? "Prove it" : "Redemption",
            detail: lastGameWon ? "Rematch — but blitz (3+2) this time?" : "Rematch? I'll ease off a notch. Blitz 3+2.",
            timed: true, xp: 25))
    }

    if offers.count < 3 {
        if let c = constraints.first(where: { !progress.completedConstraints.contains($0.id) }) {
            offers.append(OfferedChallenge(
                id: "offer-" + c.id, kind: .constraint, title: c.title,
                detail: c.description, constraintId: c.id, xp: c.xp))
        }
    }
    return Array(offers.prefix(3))
}
