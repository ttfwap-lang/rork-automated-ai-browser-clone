import Foundation

/// A mission you can run again with one tap.
///
/// A routine is a proven run turned into something repeatable: the moves that
/// worked, in order, with a blank wherever something had to be typed. It is not
/// a macro — a macro replays coordinates and breaks the first time a site shifts
/// a button. Each move here is found again by what it IS, and when it cannot be
/// found the step is repaired rather than the whole routine failing.
nonisolated struct Routine: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let host: String
    var title: String
    /// The goal in the user's own words, with ⟨blanks⟩ where values go.
    var goalTemplate: String
    /// The route, value-free exactly like a remembered recipe's route.
    var moves: [RecipeMove]
    var blanks: [RoutineBlank]
    var runCount: Int
    /// How many steps this routine has had to repair to keep working.
    var healCount: Int
    var lastRunAt: Date?
    var lastOutcomeRaw: String?
    let createdAt: Date

    /// The home screen stays a home screen, not a launcher.
    static let capacity = 12

    init(
        id: UUID = UUID(),
        host: String,
        title: String,
        goalTemplate: String,
        moves: [RecipeMove],
        blanks: [RoutineBlank] = [],
        runCount: Int = 0,
        healCount: Int = 0,
        lastRunAt: Date? = nil,
        lastOutcomeRaw: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.host = host
        self.title = title
        self.goalTemplate = goalTemplate
        self.moves = moves
        self.blanks = blanks
        self.runCount = runCount
        self.healCount = healCount
        self.lastRunAt = lastRunAt
        self.lastOutcomeRaw = lastOutcomeRaw
        self.createdAt = createdAt
    }

    /// True when launching has to ask for something first.
    var needsInput: Bool { !blanks.isEmpty }

    var lastOutcome: RunOutcome? {
        lastOutcomeRaw.flatMap { RunOutcome(rawValue: $0) }
    }

    /// True when the last attempt did not end confirmed — shown honestly on the
    /// chip rather than hidden behind a cheerful icon.
    var isShaky: Bool {
        guard let lastOutcome else { return false }
        return lastOutcome != .completed
    }

    /// Any move that submits, buys, sends or deletes. These are never run
    /// unattended, whatever the mode says.
    var hasCommittingMove: Bool {
        moves.contains { $0.isCommitting }
    }

    /// "4 moves · asks for 1 thing" for the routine list.
    var subtitle: String {
        var parts = ["\(moves.count) move\(moves.count == 1 ? "" : "s")"]
        if !blanks.isEmpty {
            parts.append("asks for \(blanks.count) thing\(blanks.count == 1 ? "" : "s")")
        }
        if healCount > 0 {
            parts.append("repaired itself \(healCount)×")
        }
        return parts.joined(separator: " · ")
    }

    /// "Run 6 times · last run 2 days ago" for the detail screen.
    var recordLine: String {
        var parts = [runCount == 0 ? "never run yet" : "run \(runCount) time\(runCount == 1 ? "" : "s")"]
        if let outcome = lastOutcome {
            parts.append("last ended \(outcome.label.lowercased())")
        }
        return parts.joined(separator: " · ")
    }

    /// The route in plain language, blanks shown as blanks.
    var routeLines: [String] {
        moves.enumerated().map { offset, move in
            let blank = blanks.first { $0.moveIndex == offset }
            let line = blank.map { move.plainLine.replacingOccurrences(of: $0.label, with: $0.token) } ?? move.plainLine
            return "\(offset + 1). \(line)"
        }
    }

    /// The goal this routine runs, with the blanks filled in.
    func goal(filling values: [UUID: String]) -> String {
        var text = goalTemplate
        for blank in blanks {
            let value = (values[blank.id] ?? "").trimmed
            guard !value.isEmpty else { continue }
            text = text.replacingOccurrences(of: blank.token, with: value)
        }
        return text.trimmed
    }

    /// What to type for the move at this index, when it is one of the blanks.
    func value(forMoveAt index: Int, from values: [UUID: String]) -> String? {
        guard let blank = blanks.first(where: { $0.moveIndex == index }) else { return nil }
        let value = (values[blank.id] ?? "").trimmed
        return value.isEmpty ? nil : value
    }

    /// True when every blank has something in it.
    func isReadyToRun(with values: [UUID: String]) -> Bool {
        blanks.allSatisfy { !((values[$0.id] ?? "").trimmed.isEmpty) }
    }
}
