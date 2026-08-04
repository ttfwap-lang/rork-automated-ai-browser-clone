import Foundation

/// One thing this site has taught the agent by going wrong.
///
/// A lesson has to keep earning its place. Every time the same kind of failure
/// happens again it gains a sighting; every time the agent works the site and
/// the failure is nowhere to be found it gains a miss. Two misses retire it —
/// because a caution that no longer matches reality is worse than no caution at
/// all: it steers the agent away from a route that now works perfectly.
nonisolated struct SiteLesson: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let host: String
    let kindRaw: String
    /// The caution in the user's own language.
    var caution: String
    /// The control this is about, when it is about one. Never anything typed.
    var subject: String?
    /// How many runs have hit this.
    var sightings: Int
    /// How many runs handed this caution over and found no sign of the problem.
    var misses: Int
    let firstSeen: Date
    var lastSeen: Date

    /// Two misses retires a lesson. Symmetrical with a recipe going stale.
    static let missLimit = 2
    /// A lesson nothing has confirmed in this long has stopped being true.
    static let staleAfter: TimeInterval = 60 * 60 * 24 * 30
    /// How many cautions one site may hold, and how many the whole book keeps.
    static let perHostCapacity = 5
    static let capacity = 60
    /// How many cautions are ever folded into one briefing. A wall of warnings
    /// is a wall the agent stops reading.
    static let briefingLimit = 3

    init(
        id: UUID = UUID(),
        host: String,
        kind: LessonKind,
        caution: String,
        subject: String? = nil,
        sightings: Int = 1,
        misses: Int = 0,
        firstSeen: Date = Date(),
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.host = host
        self.kindRaw = kind.rawValue
        self.caution = caution
        self.subject = subject
        self.sightings = sightings
        self.misses = misses
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    var kind: LessonKind {
        LessonKind(rawValue: kindRaw) ?? .deadEnd
    }

    /// Retired lessons are never handed to the agent again.
    var isRetired: Bool { misses >= Self.missLimit }

    /// True when nothing has confirmed this lesson for a long time.
    func isStale(now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastSeen) > Self.staleAfter
    }

    /// How much this lesson has earned trust, on the same shape of curve a
    /// recipe's confidence uses.
    var weight: Double {
        Double(sightings + 1) / Double(sightings + misses + 2)
    }

    /// The line the agent reads. It says how often this has happened, because
    /// "seen once" and "seen four times" deserve different weight.
    var briefingLine: String {
        let seen = sightings <= 1 ? "seen once" : "seen \(sightings) times"
        return "\(caution) (\(seen))"
    }

    /// "Seen 3 times · nothing like it in the last 2 runs" for the Memory screen.
    var recordLine: String {
        var parts = [sightings == 1 ? "seen once" : "seen \(sightings) times"]
        if misses > 0 {
            parts.append("no sign of it \(misses)×")
        }
        return parts.joined(separator: " · ")
    }

    /// Same lesson, same site: matched on the KIND and the control it names, so
    /// repeats sharpen one entry instead of piling up new ones.
    func isSameLesson(as other: SiteLesson) -> Bool {
        guard host == other.host, kindRaw == other.kindRaw else { return false }
        let mine = (subject ?? "").trimmed.lowercased()
        let theirs = (other.subject ?? "").trimmed.lowercased()
        return mine == theirs
    }
}
