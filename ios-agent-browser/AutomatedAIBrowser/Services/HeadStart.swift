import Foundation

/// Replays the opening moves of a proven route without asking the AI to decide
/// each one. This is where the saving is largest, because the first steps of a
/// mission are the most expensive ones.
///
/// Every replayed move still has to earn its place: the element has to be found
/// on the live page by name, kind, neighbourhood and rough position — never by
/// position alone — and the page has to react the way the recipe says it did. Any
/// mismatch ends the head start on the spot and the normal look-decide loop takes
/// over from exactly there.
nonisolated enum HeadStart {

    /// Never more than the opening of a route, and only at the very start of a run.
    static let maxMoves = 3

    nonisolated struct Plan: Equatable {
        let recipeID: UUID
        let recipeTitle: String
        let moves: [RecipeMove]

        /// The single line the user approves in Supervised mode.
        var proposalText: String {
            let count = moves.count
            return "replay \(count) known opening move\(count == 1 ? "" : "s") from “\(recipeTitle)”"
        }

        /// What the log entry says was replayed.
        var summaryText: String {
            moves.map { $0.plainLine }.joined(separator: " → ")
        }
    }

    nonisolated enum Match: Equatable {
        /// The remembered move was found on the live page and is ready to run.
        case matched(AgentAction)
        /// Reality stopped matching the memory. The reason is shown in the log.
        case mismatch(String)

        var action: AgentAction? {
            if case .matched(let action) = self { return action }
            return nil
        }
    }

    /// The opening worth replaying, or nil when there is nothing safe to replay.
    static func plan(from recipe: SiteRecipe) -> Plan? {
        guard !recipe.isRetired else { return nil }
        let opening = Array(recipe.replayableOpening.prefix(maxMoves))
        guard !opening.isEmpty else { return nil }
        return Plan(recipeID: recipe.id, recipeTitle: recipe.title, moves: opening)
    }

    /// Finds a remembered move on the live page.
    static func resolve(_ move: RecipeMove, in observation: PageObservation?) -> Match {
        guard move.isSafeToReplay else {
            return .mismatch("that move is not one a memory may replay")
        }

        switch move.kind {
        case .wait:
            return .matched(AgentAction(type: AgentActionKind.wait.rawValue))

        case .back:
            return .matched(AgentAction(type: AgentActionKind.back.rawValue))

        case .scroll:
            var action = AgentAction(type: AgentActionKind.scroll.rawValue)
            action.direction = move.direction ?? "down"
            action.amount = move.amount ?? 600
            return .matched(action)

        case .navigate:
            guard let urlString = move.urlString, !urlString.isEmpty else {
                return .mismatch("the remembered address is missing")
            }
            var action = AgentAction(type: AgentActionKind.navigate.rawValue)
            action.url = urlString
            return .matched(action)

        case .tapElement:
            guard let observation else {
                return .mismatch("the page scan is unavailable, so the remembered target cannot be confirmed")
            }
            guard let target = move.target else {
                return .mismatch("the remembered move has no target to find")
            }
            let scored = observation.elements
                .map { (element: $0, score: target.score(against: $0, in: observation)) }
                .filter { $0.score > 0 }
                .sorted { $0.score > $1.score }

            guard let best = scored.first else {
                return .mismatch("the \(target.kind.rawValue) “\(target.name)” is not on this page any more")
            }
            guard !OnDeviceGate.isIrreversible(best.element.name) else {
                return .mismatch("“\(best.element.name)” looks irreversible — a memory never makes the commitment")
            }

            var action = AgentAction(type: AgentActionKind.tapElement.rawValue)
            action.element = best.element.id
            action.elementName = best.element.shortDescriptor
            return .matched(action)

        default:
            return .mismatch("that move is not one a memory may replay")
        }
    }

    /// Whether the page reacted the way the recipe says it did. Returns the
    /// mismatch reason, or nil when the replay held.
    static func heldUp(expected: String?, actual: String) -> String? {
        if ReactionWatch.readsAsFailure(actual) {
            return "the page did not respond the way it did last time"
        }
        guard let expected, !expected.isEmpty else { return nil }
        if expected == "the address changed",
           !actual.contains("landed on"),
           !actual.contains("address changed") {
            return "the address was supposed to change here and did not"
        }
        return nil
    }

    /// The honest line written into the log when a replay stops early.
    static func handoverLine(atMove index: Int, reason: String) -> String {
        "the remembered route stopped matching at move \(index) — \(reason); carrying on by looking"
    }
}
