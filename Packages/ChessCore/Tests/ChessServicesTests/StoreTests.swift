import Foundation
import Testing
import ChessCore
@testable import ChessServices

// tests/store.test.ts. The TS runs with an in-memory localStorage and no native Preferences; here both
// backends of `Storage` are `MemoryStore`s. Where the TS reads `localStorage.getItem(key)` the Swift
// reads `storage.rawValue(forKey:)`, which is the same JSON text.

private func savedGame() -> SavedGame {
    SavedGame(mode: .ai, startFen: Position.startFEN, uciMoves: ["e2e4"], thinkMs: [1200], playerColor: .white,
              difficulty: .match, timeControl: nil, clockRemaining: nil, timerOn: false, hintsLeft: 3,
              challengeId: nil, adaptationNotes: [], aiSkill: 8, aiElo: 1000, savedAt: 1)
}

private func archived(_ i: Int) -> ArchivedGame {
    ArchivedGame(pgn: "", mode: .ai, playerColor: .white, result: "", score: "*", aiElo: nil, date: i,
                 analysis: nil, adaptationNotes: [], startFen: Position.startFEN, uciMoves: [])
}

private func mistake(_ i: Int) -> RecordedMistake {
    RecordedMistake(fen: Position.startFEN, playedUci: "a2a3", bestUci: "e2e4", cpLoss: 300, date: i, playerColor: .white)
}

/// A scratch `UserDefaults` suite plus a temp directory, torn down with the test.
private final class Scratch: Sendable {
    let suiteName: String
    let directory: URL

    init() {
        suiteName = "ChessServicesTests.\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appending(path: "ChessServicesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    func storage() -> Storage {
        Storage(primary: FileStore(directory: directory), secondary: UserDefaultsStore(defaults: defaults))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite("storage")
struct StorageTests {
    struct Blob: Codable, Equatable {
        var a: Int
        var b: [Bool]
    }

    @Test("round-trips JSON values and removes keys")
    func roundTrip() {
        let storage = Storage.inMemory()
        storage.save(Blob(a: 1, b: [true]), forKey: "k")
        #expect(storage.load(Blob.self, forKey: "k") == Blob(a: 1, b: [true]))
        #expect(storage.rawValue(forKey: "k") == #"{"a":1,"b":[true]}"#)
        storage.remove(forKey: "k")
        #expect(storage.load(Blob.self, forKey: "k") == nil)
        #expect(storage.rawValue(forKey: "k") == nil)
    }

    @Test("treats missing and corrupt values as absent")
    func missingAndCorrupt() {
        let storage = Storage.inMemory()
        #expect(storage.load(Blob.self, forKey: "nothing") == nil)
        storage.secondary.set("{not json", forKey: "bad")
        #expect(storage.load(Blob.self, forKey: "bad") == nil)
        storage.setRawValue(#"{"a":"one"}"#, forKey: "wrong-shape")
        #expect(storage.load(Blob.self, forKey: "wrong-shape") == nil)
    }

    @Test("writes both copies and reads the primary one first")
    func dualWrite() {
        let storage = Storage.inMemory()
        storage.save(7, forKey: "n")
        #expect(storage.primary.string(forKey: "n") == "7" && storage.secondary.string(forKey: "n") == "7")

        storage.primary.set("1", forKey: "n")
        storage.secondary.set("2", forKey: "n")
        #expect(storage.load(Int.self, forKey: "n") == 1)

        storage.primary.removeValue(forKey: "n")
        #expect(storage.load(Int.self, forKey: "n") == 2, "falls back to the second copy when the first is gone")

        // Faithfully ported: a corrupt first copy is "absent", the second copy is not consulted (TS loadKey).
        storage.primary.set("{", forKey: "n")
        #expect(storage.load(Int.self, forKey: "n") == nil)

        storage.remove(forKey: "n")
        #expect(storage.primary.string(forKey: "n") == nil && storage.secondary.string(forKey: "n") == nil)
    }

    @Test("encodes like JSON.stringify: no escaped slashes, strings and booleans as fragments")
    func encoding() {
        let storage = Storage.inMemory()
        storage.save("Ada", forKey: "s")
        storage.save(true, forKey: "b")
        storage.save(Position.startFEN, forKey: "fen")
        #expect(storage.rawValue(forKey: "s") == "\"Ada\"")
        #expect(storage.rawValue(forKey: "b") == "true")
        #expect(storage.rawValue(forKey: "fen") == "\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\"")
        #expect(storage.load(String.self, forKey: "fen") == Position.startFEN)
    }

    @Test("MemoryStore lists its keys")
    func memoryStore() {
        let store = MemoryStore()
        store.set("1", forKey: "b")
        store.set("2", forKey: "a")
        store.set("3", forKey: "b")
        #expect(store.keys == ["a", "b"] && store.string(forKey: "b") == "3")
        store.removeValue(forKey: "a")
        store.removeValue(forKey: "missing")
        #expect(store.keys == ["b"] && store.string(forKey: "a") == nil)
    }

    @Test("FileStore keeps one <key>.json per key, created on demand")
    func fileStore() throws {
        let scratch = Scratch()
        let store = FileStore(directory: scratch.directory)
        #expect(store.string(forKey: "chess.guest") == nil)
        store.removeValue(forKey: "chess.guest") // nothing to remove: no error, no crash
        store.set("true", forKey: "chess.guest")
        let url = store.url(forKey: "chess.guest")
        #expect(url.lastPathComponent == "chess.guest.json" && url.deletingLastPathComponent() == scratch.directory)
        #expect(try String(contentsOf: url, encoding: .utf8) == "true")
        #expect(store.string(forKey: "chess.guest") == "true")
        store.set("false", forKey: "chess.guest")
        #expect(store.string(forKey: "chess.guest") == "false")
        store.removeValue(forKey: "chess.guest")
        #expect(!FileManager.default.fileExists(atPath: url.path()))
        #expect(store.string(forKey: "chess.guest") == nil)
    }

    @Test("the app's file store lives under Application Support")
    func applicationSupport() throws {
        let store = try FileStore.applicationSupport(subdirectory: "ChessServicesTests")
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        #expect(store.directory.lastPathComponent == "ChessServicesTests")
        #expect(store.directory.deletingLastPathComponent().standardizedFileURL == base.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: store.directory.path()), "nothing is created until a value is written")
    }

    @Test("UserDefaultsStore stores strings and reads anything else as absent")
    func userDefaultsStore() {
        let scratch = Scratch()
        let store = UserDefaultsStore(defaults: scratch.defaults)
        #expect(store.string(forKey: "chess.guest") == nil)
        store.set("true", forKey: "chess.guest")
        #expect(store.string(forKey: "chess.guest") == "true")
        #expect(scratch.defaults.string(forKey: "chess.guest") == "true")
        scratch.defaults.set(42, forKey: "chess.progress")
        #expect(store.string(forKey: "chess.progress") == nil)
        store.removeValue(forKey: "chess.guest")
        #expect(store.string(forKey: "chess.guest") == nil)
    }

    @Test("the live storage prefers the file and falls back to UserDefaults")
    func liveShape() {
        let scratch = Scratch()
        let storage = scratch.storage()
        storage.save(["x"], forKey: "chess.archive")
        #expect(FileManager.default.fileExists(atPath: scratch.directory.appending(path: "chess.archive.json").path()))
        #expect(scratch.defaults.string(forKey: "chess.archive") == #"["x"]"#)

        scratch.defaults.set(#"["only-defaults"]"#, forKey: "chess.mistakes")
        #expect(storage.load([String].self, forKey: "chess.mistakes") == ["only-defaults"])

        scratch.defaults.set(#"["stale"]"#, forKey: "chess.archive")
        #expect(storage.load([String].self, forKey: "chess.archive") == ["x"])

        storage.remove(forKey: "chess.archive")
        #expect(storage.rawValue(forKey: "chess.archive") == nil && scratch.defaults.object(forKey: "chess.archive") == nil)
    }
}

@MainActor
@Suite("store")
struct StoreTests {
    @Test("loads defaults from empty storage")
    func defaults() {
        let state = AppState(storage: .inMemory())
        state.loadAll()
        #expect(state.settings == Settings.defaults)
        #expect(state.model.rating == 800)
        #expect(state.progress.xp == 0)
        #expect(state.saved == nil)
        #expect(state.archive.isEmpty)
        #expect(state.mistakes.isEmpty)
        #expect(state.difficulty == .match)
        #expect(state.playerName == nil)
        #expect(state.guest == false)
    }

    @Test("merges partial persisted settings over the defaults")
    func partialSettings() throws {
        let storage = Storage.inMemory()
        storage.setRawValue(#"{"sounds":false}"#, forKey: "chess.settings")
        let state = AppState(storage: storage)
        state.loadAll()
        #expect(state.settings.sounds == false)
        #expect(state.settings.coordinates == true)

        storage.setRawValue(try ServicesFixtures.shared.blob("chess.settings.partial"), forKey: "chess.settings")
        state.loadAll()
        var expected = Settings.defaults
        expected.sounds = false
        expected.boardFlip = .black
        #expect(state.settings == expected)
    }

    @Test("fills in fields missing from an older progress record")
    func oldProgress() {
        let storage = Storage.inMemory()
        storage.setRawValue(#"{"xp":120,"badges":["first-win"],"counters":{"gamesPlayed":3}}"#, forKey: "chess.progress")
        let state = AppState(storage: storage)
        state.loadAll()
        #expect(state.progress.xp == 120)
        #expect(state.progress.badges == ["first-win"])
        #expect(state.progress.counters.gamesPlayed == 3)
        #expect(state.progress.counters.hintsUsed == 0)
        #expect(state.progress.completedDrills.isEmpty)
    }

    @Test("fills in fields missing from an older player model")
    func oldPlayerModel() {
        let storage = Storage.inMemory()
        storage.setRawValue(#"{"version":1,"rating":1234}"#, forKey: "chess.playerModel")
        let state = AppState(storage: storage)
        state.loadAll()
        #expect(state.model.rating == 1234)
        #expect(state.model.weaknesses[.backRank] == 0)
        #expect(state.model.openings.isEmpty)
    }

    @Test("persists and reloads the player name, guest choice and difficulty")
    func nameGuestDifficulty() {
        let storage = Storage.inMemory()
        let state = AppState(storage: storage)
        state.playerName = "Ada"
        state.guest = true
        state.difficulty = .challenge
        state.persist(.playerName)
        state.persist(.guest)
        state.persist(.difficulty)
        #expect(storage.rawValue(forKey: "chess.playerName") == "\"Ada\"")
        #expect(storage.rawValue(forKey: "chess.guest") == "true")
        #expect(storage.rawValue(forKey: "chess.difficulty") == "\"challenge\"")

        let reloaded = AppState(storage: storage)
        reloaded.loadAll()
        #expect(reloaded.playerName == "Ada")
        #expect(reloaded.guest == true)
        #expect(reloaded.difficulty == .challenge)
    }

    @Test("removes the player name key when it is cleared")
    func clearsPlayerName() {
        let storage = Storage.inMemory()
        let state = AppState(storage: storage)
        state.playerName = "Ada"
        state.persist(.playerName)
        #expect(storage.rawValue(forKey: "chess.playerName") != nil)
        state.playerName = nil
        state.persist(.playerName)
        #expect(storage.rawValue(forKey: "chess.playerName") == nil)
        #expect(storage.primary.string(forKey: "chess.playerName") == nil && storage.secondary.string(forKey: "chess.playerName") == nil)

        // TS `state.playerName ? save : remove`: the empty string is falsy and removes the key too.
        state.playerName = "Ada"
        state.persist(.playerName)
        state.playerName = ""
        state.persist(.playerName)
        #expect(storage.rawValue(forKey: "chess.playerName") == nil)
    }

    @Test("stores the in-flight game and clears the key when there is nothing to resume")
    func savedGameKey() {
        let storage = Storage.inMemory()
        let state = AppState(storage: storage)
        state.saved = savedGame()
        state.persist(.saved)
        let reloaded = AppState(storage: storage)
        reloaded.loadAll()
        #expect(reloaded.saved?.uciMoves == ["e2e4"])
        #expect(reloaded.saved == savedGame())
        reloaded.saved = nil
        reloaded.persist(.saved)
        #expect(storage.rawValue(forKey: "chess.savedGame") == nil)
    }

    @Test("caps the archive at 100 games on disk")
    func archiveCap() throws {
        let storage = Storage.inMemory()
        let state = AppState(storage: storage)
        state.archive = (0..<130).map(archived)
        state.persist(.archive)
        let raw = try #require(storage.rawValue(forKey: "chess.archive"))
        let onDisk = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [Any])
        #expect(onDisk.count == 100)
        #expect(storage.load([ArchivedGame].self, forKey: "chess.archive")?.map(\.date) == Array(0..<100))
        #expect(state.archive.count == 130, "the in-memory list is not truncated (TS persist.archive)")
    }

    @Test("keeps the newest 60 recorded mistakes, newest first")
    func mistakesCap() {
        let storage = Storage.inMemory()
        let state = AppState(storage: storage)
        state.recordMistakes((0..<50).map(mistake))
        state.recordMistakes((0..<20).map { mistake(100 + $0) })
        #expect(state.mistakes.count == 60)
        #expect(state.mistakes[0].date == 100)
        #expect(state.mistakes[19].date == 119)
        #expect(state.mistakes[20].date == 0)
        #expect(storage.load([RecordedMistake].self, forKey: "chess.mistakes")?.count == 60)
    }

    @Test("persist(.mistakes) writes at most 60 and every other key writes as-is")
    func persistEverything() {
        let storage = Storage.inMemory()
        let state = AppState(storage: storage)
        state.mistakes = (0..<70).map(mistake)
        for key in StoreKey.allCases { state.persist(key) }
        #expect(storage.load([RecordedMistake].self, forKey: "chess.mistakes")?.count == 60)
        #expect(state.mistakes.count == 70)
        #expect(storage.rawValue(forKey: "chess.savedGame") == nil && storage.rawValue(forKey: "chess.playerName") == nil)
        for key in [StoreKey.settings, .model, .progress, .archive, .difficulty, .guest] {
            #expect(storage.rawValue(forKey: key.rawValue) != nil, "\(key.rawValue)")
        }
        #expect((storage.primary as? MemoryStore)?.keys == [
            "chess.archive", "chess.difficulty", "chess.guest", "chess.mistakes", "chess.playerModel", "chess.progress", "chess.settings",
        ])
        #expect(StoreKey.allCases.map(\.rawValue) == [
            "chess.settings", "chess.playerModel", "chess.progress", "chess.savedGame", "chess.archive",
            "chess.mistakes", "chess.difficulty", "chess.playerName", "chess.guest",
        ])
    }

    @Test("reads the TS blobs and writes them back byte-identical")
    func tsBlobs() throws {
        let f = ServicesFixtures.shared
        let keys: [StoreKey] = [.settings, .model, .progress, .saved, .archive, .mistakes, .difficulty, .playerName, .guest]
        let source = Storage.inMemory()
        for key in keys { source.setRawValue(try f.blob(key.rawValue), forKey: key.rawValue) }

        let state = AppState(storage: source)
        state.loadAll()
        #expect(state.settings == Settings(coordinates: true, autoQueen: false, takebacks: true, sounds: true, haptics: true, boardFlip: .auto, animations: true))
        #expect(state.model.rating == 800)
        #expect(state.progress.xp == 250 && state.progress.dailyStreak == 2 && state.progress.lastDailyDate == "2026-09-25")
        #expect(state.saved?.uciMoves == ["e2e4"] && state.saved?.timeControl == nil && state.saved?.aiElo == 1000)
        #expect(state.archive.count == 3 && state.archive.allSatisfy { $0.analysis == nil && $0.aiElo == nil })
        #expect(state.mistakes.count == 2 && state.mistakes[1].playerColor == .black && state.mistakes[1].cpLoss == 812)
        #expect(state.difficulty == .challenge && state.playerName == "Ada" && state.guest == true)

        // Re-persisting into a fresh storage reproduces JSON.stringify's output for every key.
        let target = Storage.inMemory()
        let copy = AppState(storage: target)
        copy.settings = state.settings
        copy.model = state.model
        copy.progress = state.progress
        copy.saved = state.saved
        copy.archive = state.archive
        copy.mistakes = state.mistakes
        copy.difficulty = state.difficulty
        copy.playerName = state.playerName
        copy.guest = state.guest
        for key in keys { copy.persist(key) }
        for key in keys {
            let written = try #require(target.rawValue(forKey: key.rawValue), "\(key.rawValue)")
            #expect(try canonicalJSON(written) == canonicalJSON(f.blob(key.rawValue)), "\(key.rawValue)")
        }
    }

    @Test("the controller's saved games survive the store unchanged")
    func savedGameFixtures() throws {
        let raw = try StoreModelsTests.rawObjects()
        for key in ["saved", "savedMinimal", "savedPuzzle"] {
            let object = try #require(raw[key])
            let storage = Storage.inMemory()
            storage.setRawValue(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self), forKey: "chess.savedGame")
            let state = AppState(storage: storage)
            state.loadAll()
            #expect(state.saved != nil, "\(key)")
            let target = Storage.inMemory()
            let copy = AppState(storage: target)
            copy.saved = state.saved
            copy.persist(.saved)
            #expect(try canonicalJSON(#require(target.rawValue(forKey: "chess.savedGame"))) == canonicalJSON(object), "\(key)")
        }
        let archive = try #require(raw["archive"])
        let storage = Storage.inMemory()
        storage.setRawValue(String(decoding: try JSONSerialization.data(withJSONObject: archive), as: UTF8.self), forKey: "chess.archive")
        let state = AppState(storage: storage)
        state.loadAll()
        #expect(state.archive.count == 3)
        state.persist(.archive)
        #expect(try canonicalJSON(#require(storage.rawValue(forKey: "chess.archive"))) == canonicalJSON(archive))
    }
}

@MainActor
@Suite("Capacitor migration")
struct CapacitorMigrationTests {
    static let importedKeys: [StoreKey] = [.settings, .model, .progress, .saved, .archive, .mistakes, .difficulty, .guest]

    /// Seeds the scratch defaults with what @capacitor/preferences wrote: `CapacitorStorage.<key>` strings.
    func seedLegacy(_ defaults: UserDefaults, keys: [StoreKey]) throws {
        let f = ServicesFixtures.shared
        for key in keys { defaults.set(try f.blob(key.rawValue), forKey: Storage.capacitorKeyPrefix + key.rawValue) }
    }

    @Test("the plugin's key format is CapacitorStorage.<key>")
    func keyFormat() {
        #expect(Storage.capacitorKeyPrefix == "CapacitorStorage.")
        #expect(Storage.capacitorMigrationKey == "chess.capacitorMigrated")
    }

    @Test("imports the old app's values on first launch, sets the flag and leaves the legacy values alone")
    func firstLaunch() throws {
        let scratch = Scratch()
        let legacy = scratch.defaults
        try seedLegacy(legacy, keys: StoreKey.allCases)
        let storage = scratch.storage()

        // A value the native app already saved must win over the legacy one.
        storage.save("Grace", forKey: StoreKey.playerName.rawValue)

        let state = AppState(storage: storage)
        let imported = state.migrateFromCapacitor(legacy: legacy)
        #expect(imported == Self.importedKeys.map(\.rawValue))
        state.loadAll()

        let f = ServicesFixtures.shared
        #expect(state.playerName == "Grace")
        #expect(state.progress.xp == 250 && state.guest == true && state.difficulty == .challenge)
        #expect(state.saved?.uciMoves == ["e2e4"] && state.archive.count == 3 && state.mistakes.count == 2)
        #expect(state.settings == Settings.defaults && state.model.rating == 800)
        for key in Self.importedKeys {
            #expect(try storage.rawValue(forKey: key.rawValue) == f.blob(key.rawValue), "\(key.rawValue)")
            #expect(try legacy.string(forKey: key.rawValue) == f.blob(key.rawValue), "written to UserDefaults under the plain key")
            #expect(FileManager.default.fileExists(atPath: scratch.directory.appending(path: key.rawValue + ".json").path()), "written to the JSON file")
            #expect(try legacy.string(forKey: Storage.capacitorKeyPrefix + key.rawValue) == f.blob(key.rawValue), "legacy value untouched")
        }
        #expect(legacy.string(forKey: Storage.capacitorKeyPrefix + StoreKey.playerName.rawValue) == "\"Ada\"")
        #expect(storage.load(Bool.self, forKey: Storage.capacitorMigrationKey) == true)
        #expect(legacy.string(forKey: Storage.capacitorMigrationKey) == "true")
    }

    @Test("runs once: later launches import nothing even when legacy values change")
    func runsOnce() throws {
        let scratch = Scratch()
        let legacy = scratch.defaults
        try seedLegacy(legacy, keys: [.guest])
        let storage = scratch.storage()

        #expect(storage.migrateCapacitorPreferences(from: legacy) == ["chess.guest"])
        #expect(storage.load(Bool.self, forKey: "chess.guest") == true)

        legacy.set("false", forKey: Storage.capacitorKeyPrefix + "chess.guest")
        legacy.set("\"Late\"", forKey: Storage.capacitorKeyPrefix + "chess.playerName")
        #expect(storage.migrateCapacitorPreferences(from: legacy) == [])
        #expect(storage.load(Bool.self, forKey: "chess.guest") == true)
        #expect(storage.rawValue(forKey: "chess.playerName") == nil)

        let state = AppState(storage: storage)
        #expect(state.migrateFromCapacitor(legacy: legacy) == [])
    }

    @Test("a fresh install has nothing to import but still records the migration")
    func freshInstall() {
        let scratch = Scratch()
        let storage = scratch.storage()
        #expect(storage.migrateCapacitorPreferences(from: scratch.defaults) == [])
        #expect(storage.load(Bool.self, forKey: Storage.capacitorMigrationKey) == true)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: scratch.directory.path())) == ["chess.capacitorMigrated.json"])
    }

    @Test("never overwrites newer native data, key by key")
    func neverOverwrites() throws {
        let scratch = Scratch()
        let legacy = scratch.defaults
        try seedLegacy(legacy, keys: [.progress, .settings])
        let storage = scratch.storage()
        var native = PlayerProgress()
        native.xp = 9999
        storage.save(native, forKey: StoreKey.progress.rawValue)

        #expect(storage.migrateCapacitorPreferences(from: legacy) == ["chess.settings"])
        #expect(storage.load(PlayerProgress.self, forKey: StoreKey.progress.rawValue) == native)
        #expect(try storage.rawValue(forKey: StoreKey.settings.rawValue) == ServicesFixtures.shared.blob("chess.settings"))
    }

    @Test("a native copy in only one backend still counts as native data")
    func partialNative() throws {
        let scratch = Scratch()
        let legacy = scratch.defaults
        try seedLegacy(legacy, keys: [.guest, .difficulty])
        let storage = scratch.storage()
        storage.primary.set("false", forKey: "chess.guest")            // file only
        storage.secondary.set("\"learn\"", forKey: "chess.difficulty")  // UserDefaults only

        #expect(storage.migrateCapacitorPreferences(from: legacy) == [])
        #expect(storage.load(Bool.self, forKey: "chess.guest") == false)
        #expect(storage.load(DifficultyMode.self, forKey: "chess.difficulty") == .learn)
    }
}
