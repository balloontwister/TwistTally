//
//  TallyStore.swift
//  TwistTally
//
//  Paranoid upgrades: debounced saves with cancellation checks,
//  persistence actor, schema versioned snapshots.
//

import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Models

struct Entrant: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var name: String
    var score: Int

    init(id: UUID = UUID(), name: String, score: Int = 0) {
        self.id = id
        self.name = name
        self.score = score
    }
}

struct Contest: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    var entrants: [Entrant]

    // NEW: per-contest accent (hex string, e.g. "#8B5CF6")
    var accentHex: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        entrants: [Entrant],
        accentHex: String = "#8B5CF6"
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.entrants = entrants
        self.accentHex = accentHex
    }

    // Backward-compatible decode: if older saved JSON has no accentHex, we default it.
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, entrants, accentHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        entrants = try c.decode([Entrant].self, forKey: .entrants)
        accentHex = (try? c.decode(String.self, forKey: .accentHex)) ?? "#8B5CF6"
    }
}

// Session-only (not persisted)
struct UndoAction: Identifiable {
    let id = UUID()
    let contestID: UUID
    let entrantID: UUID
    let previousScore: Int
    let newScore: Int
}

// MARK: - Store

@MainActor
final class TallyStore: ObservableObject {

    private let accentPalette: [String] = [
        "#8B5CF6", // purple
        "#EC4899", // magenta
        "#F97316", // orange
        "#22C55E", // green
        "#06B6D4", // teal
        "#3B82F6"  // blue
    ]

    private func nextAccentHex() -> String {
        // pick a color not used yet if possible, else cycle
        let used = Set(contests.map { $0.accentHex })
        if let fresh = accentPalette.first(where: { !used.contains($0) }) {
            return fresh
        }
        // deterministic fallback: based on count
        return accentPalette[contests.count % accentPalette.count]
    }

    // Persisted
    @Published var contests: [Contest] = [
        Contest(name: "Contest A", entrants: (1...12).map { Entrant(name: "Entrant \($0)") }, accentHex: "#8B5CF6"),
        Contest(name: "Contest B", entrants: (1...10).map { Entrant(name: "Player \($0)") }, accentHex: "#EC4899")
    ]
    @Published var selectedContestID: UUID?

    // Session-only
    @Published var undoByContest: [UUID: [UndoAction]] = [:]
    @Published var bannerMessage: String? = nil

    // Persistence
    private let persistence = PersistenceStore.shared
    private var saveTask: Task<Void, Never>?

    init() {
        if let loaded = PersistenceStore.loadBlocking() {
            contests = loaded.contests
            selectedContestID = loaded.selectedContestID ?? loaded.contests.first?.id
        } else {
            selectedContestID = contests.first?.id
        }
    }

    deinit {
        // Cancel pending debounced save. Not strictly necessary but tidy.
        saveTask?.cancel()
    }

    // MARK: - Derived

    var currentContestIndex: Int? {
        guard !contests.isEmpty else { return nil }
        guard let id = selectedContestID else { return contests.indices.first }
        return contests.firstIndex(where: { $0.id == id }) ?? contests.indices.first
    }

    var currentContestID: UUID? {
        guard let idx = currentContestIndex else { return nil }
        return contests[idx].id
    }

    var canUndoCurrentContest: Bool {
        guard let cid = currentContestID else { return false }
        return !(undoByContest[cid] ?? []).isEmpty
    }

    // MARK: - Actions

    func increment(entrantID: UUID) {
        guard let cIdx = currentContestIndex else { return }
        let contestID = contests[cIdx].id

        guard let eIdx = contests[cIdx].entrants.firstIndex(where: { $0.id == entrantID }) else { return }

        let previous = contests[cIdx].entrants[eIdx].score
        let next = previous + 1
        contests[cIdx].entrants[eIdx].score = next

        var stack = undoByContest[contestID] ?? []
        stack.append(UndoAction(contestID: contestID, entrantID: entrantID, previousScore: previous, newScore: next))
        if stack.count > 10 { stack.removeFirst() }
        undoByContest[contestID] = stack

        scheduleSave()
    }

    func undoLast() {
        guard let cIdx = currentContestIndex else { return }
        let contestID = contests[cIdx].id

        guard var stack = undoByContest[contestID], let last = stack.popLast() else { return }
        undoByContest[contestID] = stack

        guard let eIdx = contests[cIdx].entrants.firstIndex(where: { $0.id == last.entrantID }) else { return }
        let name = contests[cIdx].entrants[eIdx].name
        contests[cIdx].entrants[eIdx].score = last.previousScore

        showBanner("Undid: \(name) (\(last.newScore) → \(last.previousScore))")
        scheduleSave()
    }

    func addContest(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? defaultNewContestName() : trimmed

        let newContest = Contest(
            name: finalName,
            entrants: (1...12).map { Entrant(name: "Entrant \($0)") },
            accentHex: nextAccentHex()
        )
        contests.insert(newContest, at: 0)
        selectedContestID = newContest.id
        undoByContest[newContest.id] = []

        scheduleSave()
    }

    func defaultNewContestName() -> String {
        let base = "New Contest"
        let existing = Set(contests.map { $0.name })
        if !existing.contains(base) { return base }
        var i = 2
        while existing.contains("\(base) \(i)") { i += 1 }
        return "\(base) \(i)"
    }

    func selectionChanged() {
        // Contest picker changed
        scheduleSave()
    }

    func bindingForSelectedEntrants() -> Binding<[Entrant]> {
        Binding(
            get: {
                guard let idx = self.currentContestIndex else { return [] }
                return self.contests[idx].entrants
            },
            set: { newValue in
                guard let idx = self.currentContestIndex else { return }
                self.contests[idx].entrants = newValue

                // Structural changes invalidate undo history for this contest
                if let cid = self.currentContestID {
                    self.undoByContest[cid] = []
                }

                self.scheduleSave()
            }
        )
    }

    /// Safer contest renaming via binding (no dynamic member weirdness)
    func bindingForCurrentContestName() -> Binding<String> {
        Binding(
            get: {
                guard let idx = self.currentContestIndex else { return "" }
                return self.contests[idx].name
            },
            set: { newValue in
                guard let idx = self.currentContestIndex else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.contests[idx].name = trimmed
                self.scheduleSave()
            }
        )
    }

    // MARK: - Reset / Delete (requested placeholders)

    /// Sets all entrant scores in the current contest to 0 and clears undo history.
    func resetCurrentContest() {
        guard let cIdx = currentContestIndex else { return }
        let contestID = contests[cIdx].id
        for i in contests[cIdx].entrants.indices {
            contests[cIdx].entrants[i].score = 0
        }
        undoByContest[contestID] = []
        showBanner("Contest reset.")
        scheduleSave()
    }

    /// Deletes the currently selected contest.
    func deleteCurrentContest() {
        guard let cIdx = currentContestIndex else { return }
        let contestID = contests[cIdx].id
        contests.remove(at: cIdx)
        undoByContest[contestID] = nil

        // Keep selection valid
        selectedContestID = contests.first?.id

        showBanner("Contest deleted.")
        scheduleSave()
    }

    /// Resets scores for all contests and clears all undo history.
    func resetAllContests() {
        for c in contests.indices {
            for e in contests[c].entrants.indices {
                contests[c].entrants[e].score = 0
            }
        }
        undoByContest = [:]
        showBanner("All contests reset.")
        scheduleSave()
    }

    /// Deletes all contests.
    func deleteAllContests() {
        contests.removeAll()
        selectedContestID = nil
        undoByContest = [:]
        showBanner("All contests deleted.")
        scheduleSave()
    }

    // MARK: - Import / Export (JSON backup)

    /// Replaces all contests with imported data and sets the selected contest.
    func replaceAllContests(contests newContests: [Contest], selectedID: UUID?) {
        contests = newContests
        selectedContestID = selectedID ?? newContests.first?.id
        undoByContest = [:]
        showBanner("Imported contests.")
        scheduleSave()
    }

    // MARK: - Banner

    func showBanner(_ text: String) {
        bannerMessage = text

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            if self.bannerMessage == text {
                self.bannerMessage = nil
            }
        }
    }

    // MARK: - Save (debounced + cancellation-safe)

    private func scheduleSave() {
        saveTask?.cancel()

        // Snapshot state now (on MainActor)
        let snapshot = PersistedState(
            schemaVersion: PersistedState.currentSchemaVersion,
            contests: contests,
            selectedContestID: selectedContestID
        )

        saveTask = Task(priority: .utility) { [persistence] in
            // Debounce delay
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
            guard !Task.isCancelled else { return }

            // Actor owns disk I/O (no MainActor blocking)
            await persistence.save(snapshot)
        }
    }
}
