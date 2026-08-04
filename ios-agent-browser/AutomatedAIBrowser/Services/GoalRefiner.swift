import Foundation

/// Tidies up what the user typed before the paid planning call is made.
///
/// Free work with no live consequences: a crisper mission line makes the planner
/// sharper, and if this iPhone cannot run it, planning simply receives the goal
/// exactly as typed. The refinement is never allowed to *replace* the goal —
/// it rides alongside it, so a bad rewrite cannot quietly change what the user
/// asked for.
nonisolated enum GoalRefiner {

    nonisolated struct Refinement: Equatable {
        /// One crisp mission line.
        let missionLine: String
        /// The shape of the answer the user wants, when the goal is a question.
        let answerShape: String?

        /// The briefing line handed to the planner.
        var briefingLine: String {
            var line = "READ AS: \(missionLine)"
            if let answerShape, !answerShape.isEmpty {
                line += " (the user wants back: \(answerShape))"
            }
            return line
        }
    }

    static let instructions = """
    You restate a person's browsing request as one crisp line, and say what kind of answer they want back.

    Answer with exactly these two lines and nothing else:
    MISSION: <one clear sentence, under 20 words, keeping every specific detail they gave>
    WANTS: <the kind of answer expected — a price, a date, a name, a list, or the word action if they want something done rather than answered>

    Rules:
    - Keep every specific thing they named: the item, the number, the place, the date.
    - Never invent a detail they did not give, and never remove one.
    - No preamble, no extra lines.
    """

    static func prompt(goal: String) -> String {
        "THE REQUEST: \(goal)\n\nAnswer with the two lines."
    }

    /// Parses the two-line answer, and refuses a rewrite that has drifted away
    /// from what the user actually typed.
    static func parse(_ raw: String, original: String) -> Refinement? {
        var mission: String?
        var wants: String?

        for line in raw.split(separator: "\n") {
            let text = String(line).trimmed
            let lower = text.lowercased()
            if lower.hasPrefix("mission:") {
                mission = String(text.dropFirst("mission:".count)).trimmed
            } else if lower.hasPrefix("wants:") {
                wants = String(text.dropFirst("wants:".count)).trimmed
            }
        }

        guard let mission, !mission.isEmpty, mission.count <= 200 else { return nil }
        guard sharesSubstanceWith(mission, original: original) else { return nil }

        let shape = (wants ?? "").trimmed
        let usableShape = shape.isEmpty || shape.lowercased() == "action" ? nil : String(shape.prefix(60))
        return Refinement(missionLine: mission, answerShape: usableShape)
    }

    /// A rewrite has to still be about the same thing. A refinement that shares
    /// none of the request's meaningful words has misunderstood it, and passing
    /// that to the planner would be worse than passing nothing.
    static func sharesSubstanceWith(_ refined: String, original: String) -> Bool {
        let originalWords = RecipeMatcher.significantWords(original)
        guard !originalWords.isEmpty else { return true }
        let refinedWords = RecipeMatcher.significantWords(refined)
        return !originalWords.intersection(refinedWords).isEmpty
    }
}
