import Foundation

/// Asks this iPhone's own model for a genuinely trivial move, and refuses to
/// interpret anything it says loosely.
///
/// The answer format is one short line. Not a tool call, not JSON: a small model
/// is far more reliable at "SCROLL DOWN" than at nested arguments, and a strict
/// one-line parser doubles as the ramble detector — anything conversational
/// simply fails to parse and the step goes to the cloud.
nonisolated enum OnDeviceDecider {

    /// A parsed free answer: the move, and why it said so.
    nonisolated struct Draft: Equatable {
        let action: AgentAction
        let reasoning: String
    }

    /// More non-empty lines than this reads as rambling rather than answering.
    private static let maxAnswerLines = 3
    private static let maxReasoningLength = 140

    static let instructions = """
    You choose ONE obvious next move for a web browser that is working through a task. You only ever handle easy moments — anything difficult has already been sent elsewhere.

    Answer with exactly ONE line in one of these forms, and nothing else:
    TAP <number> | short reason
    SCROLL DOWN <pixels> | short reason
    SCROLL UP <pixels> | short reason
    BACK | short reason
    WAIT | short reason
    PASS | short reason

    Rules:
    - TAP takes a number from the element list, and only a clearly labelled button or link.
    - Never TAP anything that buys, pays, submits, sends, deletes, confirms or places an order.
    - PASS is the right answer whenever you are unsure, whenever the goal needs typing, or whenever the next move needs judgement. Passing costs nothing and is never wrong.
    - No preamble, no explanation beyond the short reason, no extra lines.
    """

    /// The briefing. Deliberately short: a small model degrades quickly as the
    /// prompt grows, and everything hard has already been routed away.
    static func prompt(
        goal: String,
        currentTask: String?,
        pageMap: String,
        lastResult: String?
    ) -> String {
        var lines = ["THE TASK: \(goal)"]
        if let currentTask, !currentTask.trimmed.isEmpty {
            lines.append("RIGHT NOW: \(currentTask)")
        }
        if let lastResult, !lastResult.trimmed.isEmpty {
            lines.append("LAST MOVE: \(String(lastResult.trimmed.prefix(120)))")
        }
        lines.append("")
        lines.append(pageMap)
        lines.append("")
        lines.append("Answer with one line.")
        return lines.joined(separator: "\n")
    }

    /// Parses a free answer, strictly. Returns nil for a pass, a ramble, or
    /// anything that is not one of the six permitted forms.
    static func parse(_ raw: String) -> Draft? {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty, lines.count <= maxAnswerLines else { return nil }

        var head = lines[0]
        // Tolerate a single leading label, e.g. "MOVE: TAP 4".
        for prefix in ["move:", "answer:", "action:"] where head.lowercased().hasPrefix(prefix) {
            head = String(head.dropFirst(prefix.count)).trimmed
        }

        let pieces = head.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let moveText = String(pieces[0])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t.·-—*`"))
            .uppercased()
        let reasonText = pieces.count > 1 ? String(pieces[1]).trimmed : ""

        guard let action = action(from: moveText) else { return nil }
        let reasoning = reasonText.isEmpty
            ? "a routine move, decided on your iPhone"
            : String(reasonText.prefix(maxReasoningLength))
        return Draft(action: action, reasoning: reasoning)
    }

    /// Matches the six permitted forms and nothing else.
    private static func action(from move: String) -> AgentAction? {
        let tokens = move
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard let verb = tokens.first else { return nil }

        switch verb {
        case "WAIT":
            guard tokens.count == 1 else { return nil }
            return AgentAction(type: AgentActionKind.wait.rawValue)

        case "BACK":
            guard tokens.count == 1 else { return nil }
            return AgentAction(type: AgentActionKind.back.rawValue)

        case "PASS":
            return nil

        case "TAP":
            guard tokens.count == 2, let id = Int(tokens[1]), id >= 0 else { return nil }
            var action = AgentAction(type: AgentActionKind.tapElement.rawValue)
            action.element = id
            return action

        case "SCROLL":
            guard tokens.count == 2 || tokens.count == 3 else { return nil }
            let direction = tokens[1].lowercased()
            guard direction == "down" || direction == "up" else { return nil }
            var action = AgentAction(type: AgentActionKind.scroll.rawValue)
            action.direction = direction
            if tokens.count == 3 {
                guard let amount = Double(tokens[2].replacingOccurrences(of: "PX", with: "")) else { return nil }
                action.amount = amount
            } else {
                action.amount = 600
            }
            return action

        default:
            return nil
        }
    }
}
