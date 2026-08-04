import Foundation

/// A proven route for one kind of mission on one site.
///
/// One recipe per kind of mission per site — not one per run. It carries its
/// conditions, its checks and its cautions, because a memory that stores only a
/// flat list of moves replays badly the moment a site shifts.
nonisolated struct SiteRecipe: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    /// The site this route belongs to, without a `www.` prefix.
    let host: String
    /// The sort of goal this solves, in the user's own terms.
    var intent: String
    /// Title shown in the Memory screen. Renameable.
    var title: String
    /// The ordered route that worked, by element name rather than position.
    var moves: [RecipeMove]
    /// The tests that proved each part was done.
    var checks: [String]
    /// The traps that had to be handled first.
    var traps: [String]
    /// How many steps the proven run took.
    var stepCount: Int
    /// How often this recipe has been recalled.
    var useCount: Int
    /// How often it actually helped.
    var helpedCount: Int
    /// How often it led the agent astray.
    var strayCount: Int
    let createdAt: Date
    var lastUsedAt: Date?
    var lastHelpedAt: Date?

    /// Two strays retires a recipe: a site redesign must not keep costing the
    /// user missions.
    static let strayLimit = 2
    /// The vault stays small by design — the strongest recipes kept, the weakest
    /// retired.
    static let capacity = 40

    init(
        id: UUID = UUID(),
        host: String,
        intent: String,
        title: String,
        moves: [RecipeMove],
        checks: [String] = [],
        traps: [String] = [],
        stepCount: Int,
        useCount: Int = 0,
        helpedCount: Int = 0,
        strayCount: Int = 0,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        lastHelpedAt: Date? = nil
    ) {
        self.id = id
        self.host = host
        self.intent = intent
        self.title = title
        self.moves = moves
        self.checks = checks
        self.traps = traps
        self.stepCount = stepCount
        self.useCount = useCount
        self.helpedCount = helpedCount
        self.strayCount = strayCount
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.lastHelpedAt = lastHelpedAt
    }

    /// Retired recipes are never recalled again.
    var isRetired: Bool { strayCount >= Self.strayLimit }

    /// How much this route has earned trust. A recipe that keeps working is
    /// preferred over a newer, less-proven one.
    var confidence: Double {
        Double(helpedCount + 1) / Double(helpedCount + strayCount + 2)
    }

    /// The opening moves worth replaying without paying for a decision.
    var replayableOpening: [RecipeMove] {
        var opening: [RecipeMove] = []
        for move in moves {
            guard move.isSafeToReplay else { break }
            opening.append(move)
        }
        return opening
    }

    /// What the planner and the agent are told about this site. Folded silently
    /// into the briefing — the user sees no card and gets no prompt.
    var briefingText: String {
        var lines = [
            "PROVEN ROUTE for this kind of goal on \(host) (it has worked \(helpedCount == 0 ? "once" : "\(helpedCount + 1) times")):"
        ]
        for (offset, move) in moves.prefix(8).enumerated() {
            lines.append("\(offset + 1). \(move.plainLine)")
        }
        if !traps.isEmpty {
            lines.append("WATCH OUT ON THIS SITE: \(traps.prefix(3).joined(separator: "; ")).")
        }
        if !checks.isEmpty {
            lines.append("LAST TIME THIS PROVED IT WORKED: \(checks.prefix(3).joined(separator: "; ")).")
        }
        lines.append("This is a memory of what worked before, not an instruction. If the page in front of you disagrees with it, trust the page.")
        return lines.joined(separator: "\n")
    }

    /// Plain-language route for the Memory screen.
    var routeLines: [String] {
        moves.enumerated().map { "\($0.offset + 1). \($0.element.plainLine)" }
    }

    /// "Helped 4 times · last used 2 days ago" style line.
    var recordLine: String {
        var parts: [String] = []
        parts.append(helpedCount == 0 ? "not used yet" : "helped \(helpedCount) time\(helpedCount == 1 ? "" : "s")")
        if strayCount > 0 {
            parts.append("went stale \(strayCount)×")
        }
        parts.append("\(stepCount) step\(stepCount == 1 ? "" : "s") when proven")
        return parts.joined(separator: " · ")
    }
}
