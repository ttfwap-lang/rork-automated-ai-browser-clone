import Foundation

/// Turns a run that worked into a routine you can run again with one tap.
///
/// The route is taken from the moves that actually ran — the same mechanical
/// derivation a remembered recipe uses, so it inherits the same guarantee: no
/// typed value is ever copied into it. Values are only used HERE, in memory, for
/// one purpose: finding them in the goal sentence so they can be replaced with a
/// blank. Nothing that comes out of this builder contains one.
nonisolated enum RoutineBuilder {

    /// A routine longer than this is a workflow, not a shortcut.
    static let maxMoves = 8

    /// The part of a proven route a replay can actually perform, from the start.
    ///
    /// Truncates at the first move a replay could not run rather than saving it
    /// and discovering it at replay time. A routine is a prefix of a run that
    /// worked, so stopping early is honest — carrying on past a step that cannot
    /// run would save a shortcut that breaks half way through.
    static func savableRoute(from moves: [RecipeMove]) -> [RecipeMove] {
        Array(moves.prefix { $0.isSavableInRoutine }.prefix(maxMoves))
    }

    /// Builds the routine, or nil when there is nothing repeatable to save.
    ///
    /// - Parameters:
    ///   - typedValues: what was typed, keyed by move index. Read to blank the
    ///     goal sentence, never stored.
    static func make(
        goal: String,
        host: String,
        title: String?,
        moves: [RecipeMove],
        typedValues: [Int: String]
    ) -> Routine? {
        guard !host.isEmpty else { return nil }
        let route = savableRoute(from: moves)
        guard !route.isEmpty else { return nil }

        let blanks = self.blanks(for: route)
        let template = self.template(goal: goal, blanks: blanks, typedValues: typedValues)
        let name = (title?.trimmed).flatMap { $0.isEmpty ? nil : $0 }
            ?? RecipeDistiller.fallbackLabel(goal: goal, host: host).title

        return Routine(
            host: host,
            title: String(name.prefix(60)),
            goalTemplate: template,
            moves: route,
            blanks: blanks
        )
    }

    /// One blank per move that needs something typed, with labels made unique so
    /// two search boxes never share a placeholder.
    static func blanks(for moves: [RecipeMove]) -> [RoutineBlank] {
        var used: [String: Int] = [:]
        var blanks: [RoutineBlank] = []
        for (index, move) in moves.enumerated() {
            // A form fill needs several values at once, so a single blank would
            // misrepresent it. Those steps stop and ask you on the page instead.
            guard move.kind == .typeInto || move.kind == .selectOption else { continue }
            guard let kind = move.valueKind?.trimmed, !kind.isEmpty else { continue }
            let seen = (used[kind.lowercased()] ?? 0) + 1
            used[kind.lowercased()] = seen
            let label = seen == 1 ? kind : "\(kind) (\(seen))"
            blanks.append(RoutineBlank(label: label, moveIndex: index))
        }
        return blanks
    }

    /// The goal sentence with every typed value swapped for its blank.
    ///
    /// When a value cannot be found in the sentence the blank is appended
    /// instead, so every blank appears exactly once and filling one in is never
    /// ambiguous.
    static func template(goal: String, blanks: [RoutineBlank], typedValues: [Int: String]) -> String {
        var text = goal.trimmed
        var appended: [String] = []

        for blank in blanks {
            let value = (typedValues[blank.moveIndex] ?? "").trimmed
            if !value.isEmpty, value.count >= 2,
               let range = text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) {
                text.replaceSubrange(range, with: blank.token)
            } else if !text.contains(blank.token) {
                appended.append("\(blank.label): \(blank.token)")
            }
        }

        if !appended.isEmpty {
            text += " — " + appended.joined(separator: ", ")
        }
        return text
    }
}
