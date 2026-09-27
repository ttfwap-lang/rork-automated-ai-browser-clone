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
        // "Keep every specific detail" is a promise in the prompt; this makes it
        // a property of the code. A rewrite that lost a number, a name, a place
        // or a date has changed the request.
        guard GoalDetails.missing(from: mission, details: GoalDetails.extract(original)).isEmpty else { return nil }

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

/// The specific things a goal names — numbers, amounts, quoted phrases,
/// addresses and proper nouns — pulled out mechanically, for free.
///
/// They are what distinguishes "book a table for 4 at Nopa on Friday" from
/// "book a table", so they are carried through every step that could lose
/// them: the refiner may not drop one, the planner must keep them, the agent
/// is reminded of them each turn, and the independent check rejects a result
/// that contradicts them.
nonisolated enum GoalDetails {

    static let maxDetails = 10

    /// Words that start with a capital for grammatical reasons, not because
    /// they name something.
    private static let commonCapitals: Set<String> = [
        "i", "a", "an", "the", "and", "or", "but", "please", "find", "show", "get", "go",
        "open", "search", "look", "tell", "what", "which", "who", "when", "where", "how",
        "is", "are", "can", "could", "would", "then", "also", "my", "me", "it", "this",
    ]

    static func extract(_ goal: String) -> [String] {
        var found: [String] = []

        func add(_ value: String) {
            let clean = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            guard !clean.isEmpty else { return }
            let lower = clean.lowercased()
            // Keep the most specific form: "$300" swallows "300".
            if found.contains(where: { $0.lowercased() == lower || $0.lowercased().contains(lower) }) { return }
            found.removeAll { lower.contains($0.lowercased()) }
            found.append(clean)
        }

        for pattern in [#""([^"]+)""#, "\u{201C}([^\u{201D}]+)\u{201D}"] {
            for match in matches(of: pattern, in: goal, group: 1) { add(match) }
        }
        for match in matches(of: #"(?i)\b[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|org|net|io|co|uk|de|fr|es|it|nl|ca|au|app|dev|ai|gov|edu)\b(/\S*)?"#, in: goal, group: 0) {
            add(match)
        }
        for match in matches(of: #"[$€£¥]\s?\d[\d,]*(\.\d+)?"#, in: goal, group: 0) { add(match) }
        for match in matches(of: #"(?i)\b\d[\d,.:/-]*\s?(am|pm|%|kg|lbs?|gb|tb|mb|km|mi|miles|people|persons|guests|adults|children|kids|nights|days|weeks|months|hours|minutes|stars?|usd|eur|gbp|dollars|euros)?\b"#, in: goal, group: 0) {
            add(match)
        }
        for name in properNouns(in: goal) { add(name) }
        return Array(found.prefix(maxDetails))
    }

    /// Details that do not appear, as whole words, in `text`.
    static func missing(from text: String, details: [String]) -> [String] {
        details.filter { !Wording.containsPhrase(text, $0) }
    }

    /// The line the agent reads each turn, or nil when the goal names nothing
    /// specific.
    static func briefingLine(_ details: [String]) -> String? {
        guard !details.isEmpty else { return nil }
        return "SPECIFICS YOU MUST HONOUR: \(details.joined(separator: "; ")) — the result is wrong if it contradicts any of them."
    }

    /// Runs of capitalised words that do not start a sentence: "Lisbon",
    /// "New York", "Golden Gate Park".
    static func properNouns(in text: String) -> [String] {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        var runs: [String] = []
        var current: [String] = []
        var sentenceStart = true

        func flush() {
            if !current.isEmpty { runs.append(current.joined(separator: " ")) }
            current = []
        }

        for token in tokens {
            let word = token.trimmingCharacters(in: .punctuationCharacters)
            let isCapital = word.first?.isUppercase == true && word.count >= 2
                && !commonCapitals.contains(word.lowercased())
            if isCapital && !sentenceStart {
                current.append(word)
            } else {
                flush()
            }
            sentenceStart = token.hasSuffix(".") || token.hasSuffix("!") || token.hasSuffix("?")
            // A run cannot carry across punctuation: "Paris, London" is two names.
            if token.last.map({ $0.isPunctuation }) == true { flush() }
        }
        flush()
        return runs
    }

    private static func matches(of pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let swiftRange = Range(match.range(at: group), in: text)
            else { return nil }
            return String(text[swiftRange])
        }
    }
}
