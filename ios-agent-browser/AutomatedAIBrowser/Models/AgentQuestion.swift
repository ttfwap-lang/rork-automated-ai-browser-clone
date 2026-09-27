import Foundation

/// A question the agent put to the watching person, with the answers it
/// suggested. Shown as a card; the run waits until it is answered or skipped.
nonisolated struct AgentQuestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let choices: [String]

    init(id: UUID = UUID(), text: String, choices: [String] = []) {
        self.id = id
        self.text = text
        self.choices = choices
    }
}
