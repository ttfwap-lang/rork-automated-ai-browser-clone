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

        init(observation: PageObservation?, failedSignatures: Set<String> = [], currentTask: MissionTask? = nil) {
            self.observation = observation
            self.failedSignatures = failedSignatures
            self.currentTask = currentTask
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
            let text = "\(task.title) \(task.doneWhen)".lowercased()
            return DifficultyScout.irreversibleWords.contains { text.contains($0) }
        } ?? false

        let scored: [(offset: Int, candidate: MoveCandidate)] = candidates.enumerated().map { offset, candidate in
            var value = max(0, min(1, candidate.confidence))
            var notes: [String] = []
            let action = candidate.action

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

            let targetText = [
                action.elementName ?? "",
                action.option ?? "",
                action.text ?? "",
            ].joined(separator: " ").lowercased()
            let isRisky = action.submit == true || DifficultyScout.irreversibleWords.contains { targetText.contains($0) }
            if isRisky {
                if taskWantsRisk {
                    value += 0.05
                    notes.append("irreversible, but this task calls for it")
                } else {
                    value -= 0.25
                    notes.append("irreversible and the task doesn't ask for it")
                }
            }

            var result = candidate
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
