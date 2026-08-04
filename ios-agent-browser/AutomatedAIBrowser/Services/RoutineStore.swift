import Foundation
import Observation

/// The saved one-tap replays, written to this device.
///
/// Repairs are written back here. That is what makes a routine get more reliable
/// with use rather than less: the first run after a site redesign pays to work
/// out where the button went, and every run after it is clean again.
@Observable
final class RoutineStore {
    private(set) var routines: [Routine] = []

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("routines.json")
        load()
    }

    var isEmpty: Bool { routines.isEmpty }

    /// Newest activity first — what you ran last is what you reach for next.
    var ordered: [Routine] {
        routines.sorted { left, right in
            (left.lastRunAt ?? left.createdAt) > (right.lastRunAt ?? right.createdAt)
        }
    }

    func routine(_ id: UUID) -> Routine? {
        routines.first { $0.id == id }
    }

    func add(_ routine: Routine) {
        routines.append(routine)
        if routines.count > Routine.capacity {
            let keep = Set(ordered.prefix(Routine.capacity).map { $0.id })
            routines.removeAll { !keep.contains($0.id) }
        }
        save()
    }

    /// True when this run is already saved — the same site and the same route.
    func contains(host: String, moves: [RecipeMove]) -> Bool {
        let signature = Self.signature(moves)
        return routines.contains { $0.host == host && Self.signature($0.moves) == signature }
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        let clean = title.trimmed
        guard !clean.isEmpty else { return }
        routines[index].title = String(clean.prefix(60))
        save()
    }

    /// Records an attempt and how it ended.
    func recordRun(_ id: UUID, outcome: RunOutcome, healed: Int) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].runCount += 1
        routines[index].healCount += max(healed, 0)
        routines[index].lastRunAt = Date()
        routines[index].lastOutcomeRaw = outcome.rawValue
        save()
    }

    /// Writes a repair back into the route, so the next run starts from what is
    /// true today rather than repairing the same step forever.
    func replaceTarget(_ id: UUID, moveIndex: Int, with target: ElementFingerprint) {
        guard let index = routines.firstIndex(where: { $0.id == id }),
              routines[index].moves.indices.contains(moveIndex)
        else { return }
        let old = routines[index].moves[moveIndex]
        routines[index].moves[moveIndex] = RecipeMove(
            id: old.id,
            action: old.action,
            target: target,
            expectedReaction: old.expectedReaction,
            isCommitting: old.isCommitting,
            valueKind: old.valueKind,
            direction: old.direction,
            amount: old.amount,
            urlString: old.urlString
        )
        save()
    }

    func delete(_ id: UUID) {
        routines.removeAll { $0.id == id }
        save()
    }

    func wipe() {
        routines = []
        save()
    }

    /// Site plus the shape of the route — enough to spot the same routine twice.
    private static func signature(_ moves: [RecipeMove]) -> String {
        moves
            .map { "\($0.action)|\($0.target?.name.lowercased() ?? "")" }
            .joined(separator: ">")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        routines = (try? JSONDecoder().decode([Routine].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(routines) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
