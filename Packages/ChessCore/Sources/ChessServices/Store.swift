// TS src/app/store.ts: central app state + persistence. Everything the app must remember lives here
// and is autosaved: settings, player model, progression, the in-flight game (crash-safe resume), and
// the finished-games archive (as PGN). `SavedGame` / `ArchivedGame` are in StoreModels.swift (Phase 2).

import Foundation
import Observation
import ChessCore

public enum BoardFlip: String, Codable, Hashable, Sendable, CaseIterable {
    /// flip in pass-and-play
    case auto
    case white
    case black
}

/// TS `Settings`; `Settings()` is `DEFAULT_SETTINGS`.
public struct Settings: Hashable, Sendable {
    public var coordinates = true
    public var autoQueen = false
    /// casual games only; forced off in ranked/challenges
    public var takebacks = true
    public var sounds = true
    public var haptics = true
    public var boardFlip: BoardFlip = .auto
    public var animations = true

    public init() {}

    public init(coordinates: Bool, autoQueen: Bool, takebacks: Bool, sounds: Bool, haptics: Bool, boardFlip: BoardFlip, animations: Bool) {
        self.coordinates = coordinates
        self.autoQueen = autoQueen
        self.takebacks = takebacks
        self.sounds = sounds
        self.haptics = haptics
        self.boardFlip = boardFlip
        self.animations = animations
    }

    /// TS `DEFAULT_SETTINGS`.
    public static let defaults = Settings()
}

extension Settings: Codable {
    private enum CodingKeys: String, CodingKey {
        case coordinates, autoQueen, takebacks, sounds, haptics, boardFlip, animations
    }

    /// store.ts `{ ...DEFAULT_SETTINGS, ...settings }`: missing keys take the defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.defaults
        coordinates = try c.decodeIfPresent(Bool.self, forKey: .coordinates) ?? d.coordinates
        autoQueen = try c.decodeIfPresent(Bool.self, forKey: .autoQueen) ?? d.autoQueen
        takebacks = try c.decodeIfPresent(Bool.self, forKey: .takebacks) ?? d.takebacks
        sounds = try c.decodeIfPresent(Bool.self, forKey: .sounds) ?? d.sounds
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        boardFlip = try c.decodeIfPresent(BoardFlip.self, forKey: .boardFlip) ?? d.boardFlip
        animations = try c.decodeIfPresent(Bool.self, forKey: .animations) ?? d.animations
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(coordinates, forKey: .coordinates)
        try c.encode(autoQueen, forKey: .autoQueen)
        try c.encode(takebacks, forKey: .takebacks)
        try c.encode(sounds, forKey: .sounds)
        try c.encode(haptics, forKey: .haptics)
        try c.encode(boardFlip, forKey: .boardFlip)
        try c.encode(animations, forKey: .animations)
    }
}

/// A recorded player mistake → fuel for personalized challenges.
public struct RecordedMistake: Hashable, Sendable {
    /// position before the mistake
    public var fen: String
    public var playedUci: String
    public var bestUci: String
    public var cpLoss: Int
    /// `Date.now()` — Unix time in milliseconds.
    public var date: Int
    public var playerColor: PieceColor

    public init(fen: String, playedUci: String, bestUci: String, cpLoss: Int, date: Int, playerColor: PieceColor) {
        self.fen = fen
        self.playedUci = playedUci
        self.bestUci = bestUci
        self.cpLoss = cpLoss
        self.date = date
        self.playerColor = playerColor
    }
}

extension RecordedMistake: Codable {
    private enum CodingKeys: String, CodingKey {
        case fen, playedUci, bestUci, cpLoss, date, playerColor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fen = try c.decode(String.self, forKey: .fen)
        playedUci = try c.decode(String.self, forKey: .playedUci)
        bestUci = try c.decode(String.self, forKey: .bestUci)
        cpLoss = try c.decode(Int.self, forKey: .cpLoss)
        date = try c.decode(Int.self, forKey: .date)
        playerColor = try c.decode(PlayerColorCode.self, forKey: .playerColor).color
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fen, forKey: .fen)
        try c.encode(playedUci, forKey: .playedUci)
        try c.encode(bestUci, forKey: .bestUci)
        try c.encode(cpLoss, forKey: .cpLoss)
        try c.encode(date, forKey: .date)
        try c.encode(PlayerColorCode(playerColor), forKey: .playerColor)
    }
}

/// store.ts `KEYS`: the storage key of every persisted field.
public enum StoreKey: String, Hashable, Sendable, CaseIterable {
    case settings = "chess.settings"
    case model = "chess.playerModel"
    case progress = "chess.progress"
    case saved = "chess.savedGame"
    case archive = "chess.archive"
    case mistakes = "chess.mistakes"
    case difficulty = "chess.difficulty"
    case playerName = "chess.playerName"
    case guest = "chess.guest"
}

/// TS `state` + `loadAll` + `persist` + `recordMistakes`. One instance per app, injected where the TS
/// imported the module singleton.
@Observable @MainActor
public final class AppState {
    public var settings = Settings()
    public var model = PlayerModel()
    public var progress = PlayerProgress()
    public var saved: SavedGame? = nil
    public var archive: [ArchivedGame] = []
    public var mistakes: [RecordedMistake] = []
    public var difficulty: DifficultyMode = .match
    public var playerName: String? = nil
    /// true once the login screen was skipped as guest
    public var guest = false

    public let storage: Storage

    /// `persist.archive` writes at most this many games.
    public static let archiveCap = 100
    /// `persist.mistakes` / `recordMistakes` keep at most this many mistakes.
    public static let mistakesCap = 60

    public init(storage: Storage) {
        self.storage = storage
    }

    /// TS `loadAll`: every field from storage, merged over the defaults where the TS spreads them.
    public func loadAll() {
        if let settings = storage.load(Settings.self, forKey: StoreKey.settings.rawValue) { self.settings = settings }
        if let model = storage.load(PlayerModel.self, forKey: StoreKey.model.rawValue) { self.model = model }
        if let progress = storage.load(PlayerProgress.self, forKey: StoreKey.progress.rawValue) { self.progress = progress }
        saved = storage.load(SavedGame.self, forKey: StoreKey.saved.rawValue)
        archive = storage.load([ArchivedGame].self, forKey: StoreKey.archive.rawValue) ?? []
        mistakes = storage.load([RecordedMistake].self, forKey: StoreKey.mistakes.rawValue) ?? []
        if let difficulty = storage.load(DifficultyMode.self, forKey: StoreKey.difficulty.rawValue) { self.difficulty = difficulty }
        playerName = storage.load(String.self, forKey: StoreKey.playerName.rawValue)
        guest = storage.load(Bool.self, forKey: StoreKey.guest.rawValue) ?? false
    }

    /// TS `persist.<field>()`.
    public func persist(_ key: StoreKey) {
        let name = key.rawValue
        switch key {
        case .settings: storage.save(settings, forKey: name)
        case .model: storage.save(model, forKey: name)
        case .progress: storage.save(progress, forKey: name)
        case .saved:
            if let saved { storage.save(saved, forKey: name) } else { storage.remove(forKey: name) }
        case .archive: storage.save(Array(archive.prefix(Self.archiveCap)), forKey: name)
        case .mistakes: storage.save(Array(mistakes.prefix(Self.mistakesCap)), forKey: name)
        case .difficulty: storage.save(difficulty, forKey: name)
        case .playerName:
            // TS `state.playerName ? save : remove` — the empty string is falsy and removes the key too.
            if let playerName, !playerName.isEmpty { storage.save(playerName, forKey: name) } else { storage.remove(forKey: name) }
        case .guest: storage.save(guest, forKey: name)
        }
    }

    /// Prepends `list` (newest first) and keeps the newest 60.
    public func recordMistakes(_ list: [RecordedMistake]) {
        mistakes = Array((list + mistakes).prefix(Self.mistakesCap))
        persist(.mistakes)
    }

    /// One-time import of the data an existing install saved through `@capacitor/preferences`
    /// (see `Storage.migrateCapacitorPreferences`). Call before `loadAll()`.
    @discardableResult
    public func migrateFromCapacitor(legacy: UserDefaults = .standard) -> [String] {
        storage.migrateCapacitorPreferences(from: legacy)
    }
}
