import Foundation

/// One move the agent drafted on a hard step, with its own confidence and the
/// score the app gave it after checking it against the page.
nonisolated struct MoveCandidate: Identifiable, Equatable {
    let id: UUID
    let action: AgentAction
    /// The model's one-line reason for this option.
    let rationale: String
    /// The model's own confidence, 0…1.
    let confidence: Double
    /// The app's score after scoring against page evidence, 0…1.
    var score: Double
    /// Why it scored the way it did — the road-not-taken explanation.
    var note: String

    init(
        id: UUID = UUID(),
        action: AgentAction,
        rationale: String,
        confidence: Double,
        score: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.action = action
        self.rationale = rationale
        self.confidence = confidence
        self.score = score
        self.note = note
    }

    /// `TAP [14] button "Filters"` — the move as the log shows it.
    var moveText: String {
        let detail = action.detailText
        return detail.isEmpty ? action.kind.label : "\(action.kind.label) \(detail)"
    }

    var scorePercent: Int {
        Int((max(0, min(1, score)) * 100).rounded())
    }
}
