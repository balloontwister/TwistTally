//
//  Persistence.swift
//  TwistTally
//
//  Paranoid upgrades: schema versioning, backup, corruption recovery,
//  and atomic replace pattern.
//

import Foundation

struct PersistedState: Codable {
    static let currentSchemaVersion: Int = 1

    var schemaVersion: Int
    var contests: [Contest]
    var selectedContestID: UUID?

    init(schemaVersion: Int = PersistedState.currentSchemaVersion,
         contests: [Contest],
         selectedContestID: UUID?) {
        self.schemaVersion = schemaVersion
        self.contests = contests
        self.selectedContestID = selectedContestID
    }
}

/// Single owner for disk I/O (prevents races, keeps Swift 6 concurrency happy)
actor PersistenceStore {
    static let shared = PersistenceStore()

    private let fileName = "twist_tally_state.json"

    // MARK: - Public API

    /// Fast synchronous load you can safely call during @MainActor init.
    /// If the file doesn't exist, returns nil (normal first run).
    nonisolated static func loadBlocking() -> PersistedState? {
        do {
            let url = try fileURL(fileName: shared.fileName)
            let fm = FileManager.default

            // First run: no file yet
            if !fm.fileExists(atPath: url.path) {
                return nil
            }

            do {
                return try decode(from: url)
            } catch {
                // Try backup
                let bak = backupURL(for: url)
                if fm.fileExists(atPath: bak.path),
                   let recovered = try? decode(from: bak) {
                    // Best effort: restore main file from backup
                    try? encode(recovered, to: url)
                    return recovered
                }
                return nil
            }
        } catch {
            return nil
        }
    }

    func load() -> PersistedState? {
        // Prefer the blocking load logic (same recovery behavior)
        return Self.loadBlocking()
    }

    /// Save with backup + atomic replace pattern.
    /// Never throws to the caller; errors are intentionally swallowed (App Store friendly).
    func save(_ state: PersistedState) {
        do {
            let url = try Self.fileURL(fileName: fileName)
            let tmp = url.appendingPathExtension("tmp")

            // Write new data to tmp first
            try Self.encode(state, to: tmp)

            let fm = FileManager.default

            if fm.fileExists(atPath: url.path) {
                // Replace existing with tmp, creating/overwriting a backup beside it
                // backupItemName must be a *file name* (not full path)
                let backupName = url.lastPathComponent + ".bak"
                _ = try fm.replaceItemAt(
                    url,
                    withItemAt: tmp,
                    backupItemName: backupName,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                // First save: just move tmp into place
                try fm.moveItem(at: tmp, to: url)
            }
        } catch {
            // Intentionally swallow in release; you can add debug logging if you want.
            // print("Save error: \(error)")
        }
    }

    // MARK: - Helpers

    private nonisolated static func fileURL(fileName: String) throws -> URL {
        let folder = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return folder.appendingPathComponent(fileName)
    }

    private nonisolated static func backupURL(for url: URL) -> URL {
        // Must match backupItemName used in replaceItemAt
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".bak")
    }

    private nonisolated static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private nonisolated static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private nonisolated static func decode(from url: URL) throws -> PersistedState {
        let data = try Data(contentsOf: url)
        let state = try decoder().decode(PersistedState.self, from: data)

        // Simple schema guard. If you add migrations later, handle them here.
        // For now, accept any version >= 1.
        if state.schemaVersion < 1 {
            throw NSError(domain: "TwistTally.Persistence", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported schema version \(state.schemaVersion)"
            ])
        }

        return state
    }

    private nonisolated static func encode(_ state: PersistedState, to url: URL) throws {
        let data = try encoder().encode(state)
        try data.write(to: url, options: [.atomic])
    }
}
