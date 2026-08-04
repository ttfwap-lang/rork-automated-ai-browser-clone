import Foundation

/// A task draft as written by the model — either in the opening mission plan or
/// in a `revise_plan` rewrite. Turned into a numbered `MissionTask` by the app.
nonisolated struct PlannedTask: Codable, Equatable, Hashable {
    let title: String
    let doneWhen: String?
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case title, hint
        case doneWhen = "done_when"
    }

    init(title: String, doneWhen: String? = nil, hint: String? = nil) {
        self.title = title
        self.doneWhen = doneWhen
        self.hint = hint
    }
}
