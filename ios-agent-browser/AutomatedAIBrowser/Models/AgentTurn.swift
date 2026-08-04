import Foundation

/// What came back from one decision call: either a single committed move, or —
/// on hard steps — a shortlist of candidate moves for the app to score.
nonisolated enum AgentTurn {
    case move(AgentDecision)
    case shortlist(reasoning: String?, candidates: [MoveCandidate])
}
