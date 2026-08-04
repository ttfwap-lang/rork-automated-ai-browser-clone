import Foundation
import Observation

/// The notebook of what has gone wrong on each site, written to this device.
///
/// The hard part of learning from failure is not writing it down — it is knowing
/// when to stop believing it. A caution that outlives the problem quietly
/// sabotages every later run: the agent avoids a button that works, or waits for
/// a banner that is gone. So a lesson here is doubted every time the agent works
/// the site and finds no sign of it, retired after two of those, and never used
/// at all when a route that is still proven to work would contradict it.
@Observable
final class LessonBook {
    private(set) var lessons: [SiteLesson] = []

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("site_lessons.json")
        load()
    }

    var isEmpty: Bool { lessons.isEmpty }

    /// Everything learned about one site, most-trusted first.
    func lessons(for host: String) -> [SiteLesson] {
        lessons
            .filter { $0.host == host }
            .sorted { left, right in
                if left.isRetired != right.isRetired { return !left.isRetired }
                if abs(left.weight - right.weight) > 0.001 { return left.weight > right.weight }
                return left.lastSeen > right.lastSeen
            }
    }

    /// Sites with something written about them, most recent first.
    var sites: [(host: String, lessons: [SiteLesson])] {
        Dictionary(grouping: lessons, by: { $0.host })
            .map { (host: $0.key, lessons: $0.value.sorted { $0.lastSeen > $1.lastSeen }) }
            .sorted { left, right in
                let leftDate = left.lessons.first?.lastSeen ?? .distantPast
                let rightDate = right.lessons.first?.lastSeen ?? .distantPast
                return leftDate > rightDate
            }
    }

    /// The cautions worth handing to the agent for this site: live, still recent,
    /// and not contradicted by a route that keeps working.
    func cautions(for host: String, avoiding recipes: [SiteRecipe], now: Date = Date()) -> [SiteLesson] {
        let proven = recipes.filter { $0.host == host && !$0.isRetired }
        return lessons(for: host)
            .filter { !$0.isRetired }
            .filter { !$0.isStale(now: now) }
            .filter { !Self.isContradicted($0, by: proven) }
            .prefix(SiteLesson.briefingLimit)
            .map { $0 }
    }

    /// What the agent and the planner read. Folded in silently — the user is not
    /// asked to approve a memory of a bad day.
    func briefing(for host: String, avoiding recipes: [SiteRecipe], now: Date = Date()) -> String? {
        let usable = cautions(for: host, avoiding: recipes, now: now)
        guard !usable.isEmpty else { return nil }
        var lines = ["WHAT HAS GONE WRONG ON \(host) BEFORE (learned from earlier runs on this site):"]
        lines.append(contentsOf: usable.map { "- \($0.briefingLine)" })
        lines.append("These are cautions, not instructions, and they are about the site rather than about this goal. If the page in front of you disagrees with one, trust the page.")
        return lines.joined(separator: "\n")
    }

    /// A caution is dropped when a route that still works would walk straight
    /// through it: pressing the very control the lesson warns about, or getting
    /// past the wall the lesson says is there.
    static func isContradicted(_ lesson: SiteLesson, by provenRecipes: [SiteRecipe]) -> Bool {
        let helpful = provenRecipes.filter { $0.helpedCount > 0 }
        guard !helpful.isEmpty else { return false }

        switch lesson.kind {
        case .gate, .deadEnd:
            // Something got through, so "you cannot get through" is out of date.
            return true
        case .deadControl, .vanished, .typingIgnored:
            guard let subject = lesson.subject?.trimmed, !subject.isEmpty else { return false }
            return helpful.contains { recipe in
                recipe.moves.contains { move in
                    guard let name = move.target?.name.trimmed, !name.isEmpty else { return false }
                    return name.compare(subject, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
            }
        case .overlay, .falseClaim, .slow:
            return false
        }
    }

    // MARK: - Writing

    /// Records what a run learned. A repeat sharpens the existing entry rather
    /// than adding a new one, and a fresh sighting clears the doubt against it.
    func record(_ drafts: [LessonDistiller.Draft], host: String, now: Date = Date()) {
        guard !host.isEmpty, !drafts.isEmpty else { return }
        for draft in drafts {
            let candidate = SiteLesson(
                host: host,
                kind: draft.kind,
                caution: draft.caution,
                subject: draft.subject,
                firstSeen: now,
                lastSeen: now
            )
            if let index = lessons.firstIndex(where: { $0.isSameLesson(as: candidate) }) {
                lessons[index].sightings += 1
                lessons[index].misses = 0
                lessons[index].lastSeen = now
                lessons[index].caution = draft.caution
            } else {
                lessons.append(candidate)
            }
        }
        enforceCapacity(host: host)
        save()
    }

    /// Replaces one caution's wording, when the free model wrote a better line.
    func reword(_ id: UUID, to caution: String) {
        guard let index = lessons.firstIndex(where: { $0.id == id }) else { return }
        let clean = caution.trimmed
        guard !clean.isEmpty else { return }
        lessons[index].caution = String(clean.prefix(120))
        save()
    }

    /// Doubts the cautions this run handed over and then saw no sign of. This is
    /// how a lesson stops being believed: not because a run went well, but
    /// because the specific thing it warns about was not there.
    func noteAbsent(host: String, handedOver: Set<UUID>, observed: Set<LessonKind>) {
        guard !handedOver.isEmpty else { return }
        var changed = false
        for index in lessons.indices where handedOver.contains(lessons[index].id) {
            guard lessons[index].host == host else { continue }
            guard !observed.contains(lessons[index].kind) else { continue }
            lessons[index].misses += 1
            changed = true
        }
        if changed { save() }
    }

    func delete(_ id: UUID) {
        lessons.removeAll { $0.id == id }
        save()
    }

    func forget(host: String) {
        lessons.removeAll { $0.host == host }
        save()
    }

    func wipe() {
        lessons = []
        save()
    }

    /// Keeps the notebook small: the weakest and oldest cautions go first, per
    /// site and overall.
    private func enforceCapacity(host: String) {
        let forHost = lessons.filter { $0.host == host }
        if forHost.count > SiteLesson.perHostCapacity {
            let keep = Set(rank(forHost).prefix(SiteLesson.perHostCapacity).map { $0.id })
            lessons.removeAll { $0.host == host && !keep.contains($0.id) }
        }
        if lessons.count > SiteLesson.capacity {
            lessons = Array(rank(lessons).prefix(SiteLesson.capacity))
        }
    }

    private func rank(_ items: [SiteLesson]) -> [SiteLesson] {
        items.sorted { left, right in
            if left.isRetired != right.isRetired { return !left.isRetired }
            if abs(left.weight - right.weight) > 0.001 { return left.weight > right.weight }
            return left.lastSeen > right.lastSeen
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        lessons = (try? JSONDecoder().decode([SiteLesson].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(lessons) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
