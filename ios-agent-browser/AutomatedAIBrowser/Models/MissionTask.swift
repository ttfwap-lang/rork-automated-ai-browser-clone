import Foundation

/// One task of the mission checklist, carrying the plain observable test that
/// proves it is finished. Numbers are stable for the whole run so the model can
/// refer to them across steps and across plan revisions.
nonisolated struct MissionTask: Codable, Hashable, Identifiable {
    let id: UUID
    /// 1-based number shown to the user and to the model.
    let number: Int
    let title: String
    /// Observable finish test, e.g. "a results list with prices is on screen".
    let doneWhen: String
    /// Optional route hint from the planner, e.g. "go straight to the search URL".
    let hint: String?
    var state: MissionTaskState
    /// Why the task was skipped, when it was.
    var skipReason: String?

    init(
        id: UUID = UUID(),
        number: Int,
        title: String,
        doneWhen: String,
        hint: String? = nil,
        state: MissionTaskState = .pending,
        skipReason: String? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.doneWhen = doneWhen
        self.hint = hint
        self.state = state
        self.skipReason = skipReason
    }
}
