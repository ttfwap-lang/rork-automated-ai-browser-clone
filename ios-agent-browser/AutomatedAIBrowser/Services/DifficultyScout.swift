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
        /// Moves in a row that left the page exactly as it was.
        let stagnantSteps: Int

        init(
            isFirstStep: Bool,
            observation: PageObservation?,
            lastResult: String? = nil,
            isRepeating: Bool = false,
            taskStuckCount: Int = 0,
            hasObjection: Bool = false,
            stagnantSteps: Int = 0
        ) {
            self.isFirstStep = isFirstStep
            self.observation = observation
            self.lastResult = lastResult
            self.isRepeating = isRepeating
            self.taskStuckCount = taskStuckCount
            self.hasObjection = hasObjection
            self.stagnantSteps = stagnantSteps
        }
    }

    /// Words that mark a move as one you cannot take back.
    static let irreversibleWords = [
        "buy", "purchase", "pay", "checkout", "place order", "order now",
        "submit", "send", "delete", "remove", "cancel subscription", "confirm",
    ]

    /// Above this many elements a page is busy enough that the fast model starts
    /// mis-aiming. Most real pages list 15-30 controls on one screen, so a lower
    /// bar made nearly every step "busy" and the cheap tiers went unused.
    private static let busyPageElementCount = 40
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

        // Only the app's own verdict wording counts: a result line also echoes
        // element names and typed text, and "Report an error" is not an error.
        let lower = Wording.appAuthored(signals.lastResult ?? "").lowercased()
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
        if signals.stagnantSteps >= 2 {
            score += 2
            reasons.append("the page has not changed in \(signals.stagnantSteps) moves")
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

        let names = observation.visibleElements
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
        // Only what is on screen: listing off-screen controls too must not make
        // every long page read as "busy".
        if observation.visibleElements.count > busyPageElementCount {
            score += 1
            reasons.append("a busy page with \(observation.visibleElements.count) choices")
        }

        // Informational only. A "Buy now" button somewhere on screen says nothing
        // about whether THIS step will press it; the loop checks the move the
        // model actually chose, and escalates that one if it commits.
        let isIrreversible = observation.visibleElements.contains { element in
            guard element.kind == .button || element.kind == .link else { return false }
            return OnDeviceGate.isIrreversible(element.name)
        }
        let irreversibleReason = "an irreversible move is on screen"

        let difficulty: StepDifficulty
        switch score {
        case 0: difficulty = reasons.isEmpty ? .routine : .normal
        case 1...2: difficulty = .normal
        default: difficulty = .hard
        }

        if difficulty == .routine {
            return DifficultyRead(
                difficulty: .routine,
                reasons: ["a simple page with \(observation.visibleElements.count) choices"] + (isIrreversible ? [irreversibleReason] : []),
                isIrreversible: isIrreversible,
                isFlyingBlind: false
            )
        }
        if isIrreversible {
            reasons.append(irreversibleReason)
        }

        return DifficultyRead(
            difficulty: difficulty,
            reasons: reasons,
            isIrreversible: isIrreversible,
            isFlyingBlind: false
        )
    }
}
