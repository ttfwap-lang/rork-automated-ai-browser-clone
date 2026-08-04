import Foundation

/// Turns a finished, verified run into a short recipe for that site.
///
/// The route itself is derived mechanically from what actually happened, in code
/// — not written by a model. That is deliberate on two counts: a model asked to
/// recall a route invents plausible steps, and a model asked to summarise a run
/// would happily copy the search terms the user typed into it. Deriving the route
/// from the executed moves makes it truthful, and makes "typed values are never
/// stored" a property of the code rather than a promise in a prompt.
///
/// A model is used for one thing only: the human-readable intent, title and
/// cautions. That is short input, short output, no live consequences — the
/// natural home for the free on-device tier.
nonisolated enum RecipeDistiller {

    /// One executed move, as the distiller needs to see it.
    nonisolated struct Move: Sendable {
        let kind: AgentActionKind
        let fingerprint: ElementFingerprint?
        let result: String?
        let submitted: Bool
        let direction: String?
        let amount: Double?
        let urlString: String?
        /// What kind of thing was typed, never the text itself.
        let valueKind: String?

        init(
            kind: AgentActionKind,
            fingerprint: ElementFingerprint? = nil,
            result: String? = nil,
            submitted: Bool = false,
            direction: String? = nil,
            amount: Double? = nil,
            urlString: String? = nil,
            valueKind: String? = nil
        ) {
            self.kind = kind
            self.fingerprint = fingerprint
            self.result = result
            self.submitted = submitted
            self.direction = direction
            self.amount = amount
            self.urlString = urlString
            self.valueKind = valueKind
        }
    }

    /// How many moves a recipe keeps. A route longer than this is noise.
    static let maxMoves = 10
    static let maxTraps = 4

    // MARK: - The mechanical part

    /// Which executed moves make it into a route, by position.
    ///
    /// Kept as its own step so anything that needs to line up with the route —
    /// a routine's blanks, for one — uses exactly the same rule rather than a
    /// second copy of it that can drift.
    static func keptIndices(from moves: [Move]) -> [Int] {
        moves
            .enumerated()
            .filter { $0.element.kind.isPageAction }
            .filter { !ReactionWatch.readsAsFailure($0.element.result ?? "") }
            .prefix(maxMoves)
            .map { $0.offset }
    }

    /// Derives the route from the moves that actually ran and worked.
    static func route(from moves: [Move]) -> [RecipeMove] {
        keptIndices(from: moves).map { index in
            let move = moves[index]
            return RecipeMove(
                action: move.kind.rawValue,
                target: move.fingerprint,
                expectedReaction: reaction(from: move.result),
                isCommitting: isCommitting(move),
                valueKind: move.valueKind,
                submits: move.submitted,
                direction: move.direction,
                amount: move.amount,
                urlString: storableAddress(move)
            )
        }
    }

    /// A move that submits, buys, sends or deletes. Never replayed unattended.
    static func isCommitting(_ move: Move) -> Bool {
        if move.kind == .fillForm { return true }
        if let name = move.fingerprint?.name, OnDeviceGate.isIrreversible(name) { return true }
        // Pressing Enter is only a commitment when it commits to something. In a
        // search box it is simply how search works, and treating it as a
        // commitment would make every saved replay of a search ask permission to
        // do the one thing it exists to do.
        if move.submitted { return !isSearchLike(move.fingerprint?.name) }
        return false
    }

    /// True when a field reads like a search box rather than a form field.
    static func isSearchLike(_ name: String?) -> Bool {
        let lower = (name ?? "").trimmed.lowercased()
        guard !lower.isEmpty else { return false }
        return ["search", "find", "query", "look up", "lookup", "keyword"].contains { lower.contains($0) }
    }

    /// A remembered address is kept only when it carries nothing somebody typed.
    static func storableAddress(_ move: Move) -> String? {
        guard move.kind == .navigate, let raw = move.urlString, let url = URL(string: raw) else { return nil }
        guard (url.query ?? "").isEmpty, (url.fragment ?? "").isEmpty else { return nil }
        return raw
    }

    /// The short form of what the page did, so a replay can tell whether it holds.
    static func reaction(from result: String?) -> String? {
        guard let result = result?.trimmed, !result.isEmpty else { return nil }
        if result.contains("landed on") || result.contains("address changed") {
            return "the address changed"
        }
        if result.contains("page reacted") {
            return "the page reacted"
        }
        if result.contains("the page moved") {
            return "the page scrolled"
        }
        return nil
    }

    /// The checks that proved the mission was done, from the plan the run worked to.
    static func checks(from plan: MissionPlan?, verdictEvidence: String?) -> [String] {
        var lines: [String] = []
        if let plan {
            lines.append(contentsOf: plan.tasks.compactMap { task in
                let test = task.doneWhen.trimmed
                return test.isEmpty ? nil : test
            })
        }
        if let evidence = verdictEvidence?.trimmed, !evidence.isEmpty {
            lines.append(evidence)
        }
        return Array(lines.prefix(4))
    }

    /// The traps this run actually hit, read off the moves rather than guessed:
    /// a dismissal that had to happen first, and any move that got nowhere.
    static func mechanicalTraps(from moves: [Move]) -> [String] {
        var traps: [String] = []
        for move in moves {
            if move.kind == .tapElement,
               let name = move.fingerprint?.name,
               OnDeviceGate.isDismissal(name) {
                traps.append("a “\(name)” banner has to be cleared first")
            }
            if ReactionWatch.readsAsFailure(move.result ?? ""),
               let name = move.fingerprint?.name, !name.isEmpty {
                traps.append("“\(name)” did nothing when pressed")
            }
        }
        var seen: Set<String> = []
        return traps.filter { seen.insert($0).inserted }.prefix(maxTraps).map { $0 }
    }

    // MARK: - The written part

    static let instructions = """
    You label a browsing route that has just been proven to work, so it can be recognised next time.

    Answer with exactly these three lines and nothing else:
    INTENT: <the kind of goal this route solves, 3-8 words, general not specific>
    TITLE: <a short name a person would recognise, 2-5 words>
    TRAPS: <up to two things that got in the way, separated by a semicolon, or the word none>

    Rules:
    - INTENT must describe the KIND of goal, never the specific thing looked for. "find a product's price" not "find the price of the red trainers".
    - Never include search terms, names, addresses, numbers or anything the person typed.
    - No preamble, no extra lines.
    """

    /// The briefing for the label. Only the route and the goal's shape go in —
    /// never the values that were typed.
    static func prompt(goal: String, host: String, routeLines: [String]) -> String {
        var lines = ["THE GOAL: \(goal)", "THE SITE: \(host)", "", "WHAT WORKED:"]
        lines.append(contentsOf: routeLines.isEmpty ? ["(no moves recorded)"] : routeLines)
        lines.append("")
        lines.append("Answer with the three lines.")
        return lines.joined(separator: "\n")
    }

    nonisolated struct Label: Equatable {
        let intent: String
        let title: String
        let traps: [String]
    }

    /// Parses the three-line label, strictly. Returns nil for anything else so
    /// the caller falls back rather than storing nonsense.
    static func parseLabel(_ raw: String) -> Label? {
        var intent: String?
        var title: String?
        var traps: [String] = []

        for line in raw.split(separator: "\n") {
            let text = String(line).trimmed
            let lower = text.lowercased()
            if lower.hasPrefix("intent:") {
                intent = String(text.dropFirst("intent:".count)).trimmed
            } else if lower.hasPrefix("title:") {
                title = String(text.dropFirst("title:".count)).trimmed
            } else if lower.hasPrefix("traps:") {
                let value = String(text.dropFirst("traps:".count)).trimmed
                if !value.isEmpty, value.lowercased() != "none" {
                    traps = value
                        .split(separator: ";")
                        .map { String($0).trimmed }
                        .filter { !$0.isEmpty }
                }
            }
        }

        guard let intent, let title, !intent.isEmpty, !title.isEmpty else { return nil }
        guard intent.count <= 90, title.count <= 60 else { return nil }
        return Label(
            intent: intent,
            title: title,
            traps: Array(traps.prefix(2))
        )
    }

    /// The label to use when no model could write one. Mechanical, free, and
    /// always available — memory still works on a phone with no Apple
    /// Intelligence and no spare cloud call.
    static func fallbackLabel(goal: String, host: String) -> Label {
        let words = goal
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let intentWords = words.filter { !RecipeMatcher.stopWords.contains($0.lowercased()) }
        let intent = intentWords.isEmpty
            ? String(goal.trimmed.prefix(60))
            : intentWords.prefix(8).joined(separator: " ").lowercased()
        let title = intentWords.isEmpty
            ? "Route on \(host)"
            : intentWords.prefix(4).joined(separator: " ").capitalizedFirst
        return Label(intent: intent, title: title, traps: [])
    }

    // MARK: - Assembly

    /// Builds the recipe. Returns nil when there is no usable route to remember.
    static func make(
        host: String,
        label: Label,
        moves: [Move],
        plan: MissionPlan?,
        verdictEvidence: String?,
        stepCount: Int
    ) -> SiteRecipe? {
        guard !host.isEmpty else { return nil }
        let route = route(from: moves)
        guard !route.isEmpty else { return nil }

        var traps = label.traps
        traps.append(contentsOf: mechanicalTraps(from: moves))
        var seen: Set<String> = []
        traps = traps.filter { seen.insert($0.lowercased()).inserted }

        return SiteRecipe(
            host: host,
            intent: label.intent,
            title: label.title,
            moves: route,
            checks: checks(from: plan, verdictEvidence: verdictEvidence),
            traps: Array(traps.prefix(maxTraps)),
            stepCount: stepCount
        )
    }
}

extension String {
    /// "find price" → "Find price". Leaves the rest of the casing alone.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
