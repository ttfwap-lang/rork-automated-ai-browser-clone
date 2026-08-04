import Foundation

/// Forms an honest opinion of how hard the current moment is, from signals the
/// app already has. Costs nothing — no AI call — and is deliberately biased
/// toward spending more when it is unsure rather than less.
nonisolated enum DifficultyScout {

    /// Everything the read looks at. All of it is already on hand.
    nonisolated struct Signals {
        let isFirstStep: Bool
        let observation: PageObservation?
        /// Result line of the previous step, if any.
        let lastResult: String?
        /// True when the last three page moves were the same move.
        let isRepeating: Bool
        /// How many steps the current checklist task has been current.
        let taskStuckCount: Int
        /// True when the independent check just rejected a claim.
        let hasObjection: Bool

        init(
            isFirstStep: Bool,
            observation: PageObservation?,
            lastResult: String? = nil,
            isRepeating: Bool = false,
            taskStuckCount: Int = 0,
            hasObjection: Bool = false
        ) {
            self.isFirstStep = isFirstStep
            self.observation = observation
            self.lastResult = lastResult
            self.isRepeating = isRepeating
            self.taskStuckCount = taskStuckCount
            self.hasObjection = hasObjection
        }
    }

    /// Words that mark a move as one you cannot take back.
    static let irreversibleWords = [
        "buy", "purchase", "pay", "checkout", "place order", "order now",
        "submit", "send", "delete", "remove", "cancel subscription", "confirm",
    ]

    /// Above this many elements a page is busy enough that the fast model starts
    /// mis-aiming.
    private static let busyPageElementCount = 14
    /// This many identically-named targets on screen is a look-alike trap.
    private static let lookAlikeThreshold = 4

    static func read(_ signals: Signals) -> DifficultyRead {
        var score = 0
        var reasons: [String] = []

        guard let observation = signals.observation else {
            return DifficultyRead(
                difficulty: .hard,
                reasons: ["the page scan failed — flying on the screenshot alone"],
                isIrreversible: false,
                isFlyingBlind: true
            )
        }

        let lower = (signals.lastResult ?? "").lowercased()
        if lower.contains("no visible reaction") {
            score += 2
            reasons.append("the last move got no reaction")
        }
        if lower.contains("no longer on the page") || lower.contains("couldn't find") || lower.contains("no action taken") {
            score += 2
            reasons.append("the last move missed its target")
        }
        if signals.isRepeating {
            score += 2
            reasons.append("the same move keeps repeating")
        }
        if signals.hasObjection {
            score += 2
            reasons.append("the independent check just rejected a claim")
        }
        if signals.taskStuckCount >= 3 {
            score += 1
            reasons.append("this task has been stuck for \(signals.taskStuckCount) steps")
        }
        if observation.overlayLikely {
            score += 1
            reasons.append("an overlay is blocking the page")
        }
        if observation.isPartial || observation.blockedPanelCount > 0 {
            score += 1
            reasons.append("part of the page couldn't be scanned")
        }

        let names = observation.elements
            .map { $0.name.trimmed.lowercased() }
            .filter { !$0.isEmpty }
        var counts: [String: Int] = [:]
        for name in names {
            counts[name, default: 0] += 1
        }
        if counts.values.contains(where: { $0 >= lookAlikeThreshold }) {
            score += 1
            reasons.append("several targets on screen look the same")
        }
        if observation.elements.count > busyPageElementCount {
            score += 1
            reasons.append("a busy page with \(observation.elements.count) choices")
        }

        let isIrreversible = observation.elements.contains { element in
            let name = element.name.lowercased()
            guard !name.isEmpty, element.kind == .button || element.kind == .link else { return false }
            return irreversibleWords.contains { name.contains($0) }
        }
        if isIrreversible {
            reasons.append("an irreversible move is on screen")
        }

        let difficulty: StepDifficulty
        switch score {
        case 0: difficulty = reasons.isEmpty ? .routine : .normal
        case 1...2: difficulty = .normal
        default: difficulty = .hard
        }

        if difficulty == .routine {
            return DifficultyRead(
                difficulty: .routine,
                reasons: ["a simple page with \(observation.elements.count) choices"],
                isIrreversible: false,
                isFlyingBlind: false
            )
        }

        return DifficultyRead(
            difficulty: difficulty,
            reasons: reasons,
            isIrreversible: isIrreversible,
            isFlyingBlind: false
        )
    }
}
