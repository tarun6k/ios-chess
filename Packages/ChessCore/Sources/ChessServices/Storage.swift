// TS src/app/storage.ts: crash-safe key-value persistence of JSON values. The TS writes every value to
// BOTH Capacitor Preferences (native) and localStorage so a mid-write crash still leaves one good copy,
// and reads the native copy first. Here the two copies are an atomically written `<key>.json` file in
// Application Support (primary) and `UserDefaults` (secondary, under the very same `chess.*` key), with
// in-memory backends for tests. Corrupt or unparsable values read as absent, like the TS `try/catch`.

import Foundation
import os

/// One raw-string backend: `localStorage` / Capacitor `Preferences` in the TS.
public protocol KeyValueStore: AnyObject, Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeValue(forKey key: String)
}

/// `UserDefaults` backend. Values are stored as strings; anything else under the key reads as absent.
/// `UserDefaults` is documented thread-safe but the SDK does not mark it `Sendable`, hence `@unchecked`.
public final class UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? {
        // Not `string(forKey:)`, which would stringify numbers stored under the key.
        defaults.object(forKey: key) as? String
    }

    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

/// A directory of `<key>.json` files, each written atomically (a crash leaves the old file or the new
/// one, never a torn one). Write and delete errors are swallowed like the TS `catch { /* ignore */ }`.
public final class FileStore: KeyValueStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Library/Application Support/<bundle id>/` in the app sandbox (created on demand).
    public static func applicationSupport(subdirectory: String = Bundle.main.bundleIdentifier ?? "AdaptiveChess") throws -> FileStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return FileStore(directory: base.appending(path: subdirectory, directoryHint: .isDirectory))
    }

    public func url(forKey key: String) -> URL {
        directory.appending(path: key + ".json", directoryHint: .notDirectory)
    }

    public func string(forKey key: String) -> String? {
        guard let data = try? Data(contentsOf: url(forKey: key)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String, forKey key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(value.utf8).write(to: url(forKey: key), options: [.atomic])
    }

    public func removeValue(forKey key: String) {
        try? FileManager.default.removeItem(at: url(forKey: key))
    }
}

/// In-memory backend (the TS test's `MemoryStorage`).
public final class MemoryStore: KeyValueStore {
    private let values = OSAllocatedUnfairLock(initialState: [String: String]())

    public init() {}

    public var keys: [String] { values.withLock { Array($0.keys).sorted() } }

    public func string(forKey key: String) -> String? {
        values.withLock { $0[key] }
    }

    public func set(_ value: String, forKey key: String) {
        values.withLock { $0[key] = value }
    }

    public func removeValue(forKey key: String) {
        values.withLock { _ = $0.removeValue(forKey: key) }
    }
}

/// storage.ts `loadKey` / `saveKey` / `removeKey`: JSON values written to both backends and read from
/// the primary one first, falling back to the secondary only when the primary has no value.
public struct Storage: Sendable {
    /// The JSON files (the TS Capacitor Preferences copy).
    public let primary: any KeyValueStore
    /// `UserDefaults` (the TS localStorage copy).
    public let secondary: any KeyValueStore

    public init(primary: any KeyValueStore, secondary: any KeyValueStore) {
        self.primary = primary
        self.secondary = secondary
    }

    /// The app's storage: Application Support files plus `UserDefaults`.
    public static func live(defaults: UserDefaults = .standard) throws -> Storage {
        Storage(primary: try FileStore.applicationSupport(), secondary: UserDefaultsStore(defaults: defaults))
    }

    /// Two in-memory backends (tests, previews).
    public static func inMemory() -> Storage {
        Storage(primary: MemoryStore(), secondary: MemoryStore())
    }

    /// The stored JSON text, primary first (what `loadKey` parses).
    public func rawValue(forKey key: String) -> String? {
        primary.string(forKey: key) ?? secondary.string(forKey: key)
    }

    /// TS `loadKey`: nil when the key is absent or the value does not decode as `T`.
    public func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let raw = rawValue(forKey: key) else { return nil }
        return try? Self.decoder.decode(T.self, from: Data(raw.utf8))
    }

    /// TS `saveKey`: `JSON.stringify(value)` into both backends.
    public func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? Self.encoder.encode(value) else { return }
        setRawValue(String(decoding: data, as: UTF8.self), forKey: key)
    }

    /// Stores an already-serialised JSON text under `key` in both backends.
    public func setRawValue(_ raw: String, forKey key: String) {
        secondary.set(raw, forKey: key)
        primary.set(raw, forKey: key)
    }

    /// TS `removeKey`.
    public func remove(forKey key: String) {
        secondary.removeValue(forKey: key)
        primary.removeValue(forKey: key)
    }

    static let decoder = JSONDecoder()

    /// `JSON.stringify` shape: compact, `/` unescaped. Keys are sorted because JSONEncoder's default order
    /// varies per process (Swift's per-launch dictionary seed); the TS order was declaration order.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return encoder
    }()
}

// MARK: - Capacitor migration

extension Storage {
    /// `@capacitor/preferences` (node_modules/@capacitor/preferences/ios/Sources/PreferencesPlugin/Preferences.swift)
    /// keeps every value as a string in `UserDefaults.standard` under `"CapacitorStorage." + key` — the
    /// default group `"CapacitorStorage"` plus a dot, since the app never calls `configure`.
    public static let capacitorKeyPrefix = "CapacitorStorage."

    /// Set to `true` once the import ran, so later launches never import again.
    public static let capacitorMigrationKey = "chess.capacitorMigrated"

    /// First launch after the Capacitor app: copies each `CapacitorStorage.<key>` value the old app saved
    /// into this storage, skipping keys that already have a native value (native data is never
    /// overwritten), then records the migration. The legacy values are left in place. Returns the
    /// imported keys; empty when the migration already ran.
    @discardableResult
    public func migrateCapacitorPreferences(from legacy: UserDefaults = .standard,
                                            keys: [String] = StoreKey.allCases.map(\.rawValue)) -> [String] {
        if load(Bool.self, forKey: Self.capacitorMigrationKey) == true { return [] }
        var imported: [String] = []
        for key in keys {
            guard rawValue(forKey: key) == nil, let raw = legacy.string(forKey: Self.capacitorKeyPrefix + key) else { continue }
            setRawValue(raw, forKey: key)
            imported.append(key)
        }
        save(true, forKey: Self.capacitorMigrationKey)
        return imported
    }
}
