import Foundation

/// Scores the moves the agent drafted on a hard step against evidence the model
/// cannot fake: does the target still exist, is it disabled, has this exact move
/// already failed in this run, does it serve the current task, and how risky is it.
nonisolated enum CandidateScorer {

    nonisolated struct Context {
        let observation: PageObservation?
        /// Signatures of moves already tried in this run that did not work.
        let failedSignatures: Set<String>
        let currentTask: MissionTask?
        /// The page the candidates are for; scopes each target's identity.
        let urlString: String
        /// The specific things the goal names (`GoalDetails`).
        let goalDetails: [String]

        init(
            observation: PageObservation?,
            failedSignatures: Set<String> = [],
            currentTask: MissionTask? = nil,
            urlString: String = "",
            goalDetails: [String] = []
        ) {
            self.observation = observation
            self.failedSignatures = failedSignatures
            self.currentTask = currentTask
            self.urlString = urlString
            self.goalDetails = goalDetails
        }
    }

    private static let stopWords: Set<String> = [
        "the", "and", "with", "that", "this", "from", "into", "your", "then",
        "when", "page", "screen", "click", "tap", "onto", "some", "have", "show",
        "shows", "showing", "list", "using", "there",
    ]

    /// Returns every candidate scored and sorted best-first. Ties keep the order
    /// the model proposed them in.
    static func score(_ candidates: [MoveCandidate], in context: Context) -> [MoveCandidate] {
        let taskWords = keywords(from: context.currentTask.map { "\($0.title) \($0.doneWhen)" } ?? "")
        let taskWantsRisk = context.currentTask.map { task in
            OnDeviceGate.isIrreversible("\(task.title) \(task.doneWhen)")
        } ?? false

        let scored: [(offset: Int, candidate: MoveCandidate)] = candidates.enumerated().map { offset, candidate in
            var value = max(0, min(1, candidate.confidence))
            var notes: [String] = []
            var action = candidate.action

            // Resolve the target now, before anything is judged: the risk check
            // reads its name and the failure memory keys on its identity. Left
            // until after scoring, a "Place order" candidate looked harmless.
            if let elementID = action.element,
               let observation = context.observation,
               let element = observation.element(withID: elementID) {
                if action.elementName == nil { action.elementName = element.shortDescriptor }
                action.targetKey = element.targetKey(in: observation, urlString: context.urlString)
            }

            if let elementID = action.element {
                if let observation = context.observation {
                    if let element = observation.element(withID: elementID) {
                        value += 0.15
                        if element.states.contains(where: { $0.lowercased() == "disabled" }) {
                            value -= 0.5
                            notes.append("[\(elementID)] is disabled")
                        }
                    } else {
                        value -= 0.6
                        notes.append("[\(elementID)] is not on this screen")
                    }
                }
            }

            if context.failedSignatures.contains(action.repetitionSignature) {
                value -= 0.7
                notes.append("this exact move already failed in this run")
            }

            if !taskWords.isEmpty {
                let haystack = [
                    candidate.rationale,
                    action.detailText,
                    action.text ?? "",
                    action.url ?? "",
                    action.option ?? "",
                ].joined(separator: " ").lowercased()
                if taskWords.contains(where: { haystack.contains($0) }) {
                    value += 0.12
                    notes.append("fits the current task")
                }
            }

            if !context.goalDetails.isEmpty {
                let said = [candidate.rationale, action.elementName ?? "", action.text ?? "", action.url ?? "", action.option ?? ""]
                    .joined(separator: " ")
                if context.goalDetails.contains(where: { Wording.containsPhrase(said, $0) }) {
                    value += 0.08
                    notes.append("uses a specific from the goal")
                }
            }

            let targetText = [
                action.elementName ?? "",
                action.option ?? "",
                action.text ?? "",
            ].joined(separator: " ").lowercased()
            let isRisky = action.submit == true || OnDeviceGate.isIrreversible(targetText)
            if isRisky {
                if taskWantsRisk {
                    value += 0.05
                    notes.append("irreversible, but this task calls for it")
                } else {
                    value -= 0.25
                    notes.append("irreversible and the task doesn't ask for it")
                }
            }

            var result = MoveCandidate(
                id: candidate.id,
                action: action,
                rationale: candidate.rationale,
                confidence: candidate.confidence
            )
            result.score = max(0, min(1, value))
            result.note = notes.isEmpty ? "nothing against it on this page" : notes.joined(separator: " · ")
            return (offset, result)
        }

        return scored
            .sorted { left, right in
                if left.candidate.score == right.candidate.score {
                    return left.offset < right.offset
                }
                return left.candidate.score > right.candidate.score
            }
            .map(\.candidate)
    }

    /// Meaningful words from a task, used to spot candidates that serve it.
    private static func keywords(from text: String) -> Set<String> {
        let pieces = text.lowercased().split { !$0.isLetter }
        return Set(pieces.map(String.init).filter { $0.count >= 4 && !stopWords.contains($0) }.prefix(8))
    }
}
