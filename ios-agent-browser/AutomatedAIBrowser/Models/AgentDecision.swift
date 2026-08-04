import Foundation

/// The model's reply for one step: a short reasoning plus the chosen action.
nonisolated struct AgentDecision: Codable {
    let reasoning: String?
    let action: AgentAction
}
