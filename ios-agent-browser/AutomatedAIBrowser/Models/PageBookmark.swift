import UIKit

/// A checkpoint the app takes before a branching or risky move: the page, its
/// scroll position, a thumbnail, and a growing list of what has already been
/// tried from here — the cure for returning to a page and repeating a mistake.
///
/// Honest limit: this restores the page, not text already typed into a form, and
/// a site that has moved your session on may come back different.
nonisolated struct PageBookmark: Identifiable, Equatable {
    let id: UUID
    /// 1-based number, stable for the whole run so the model can name it.
    let number: Int
    /// Plain label, e.g. "search results for cheap flights".
    let label: String
    let urlString: String
    let scrollY: Double
    let thumbnail: UIImage?
    /// What has already been tried from this point, and how it went.
    var tried: [String]
    /// The checklist task that was current when this was captured.
    let taskNumber: Int?
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        number: Int,
        label: String,
        urlString: String,
        scrollY: Double,
        thumbnail: UIImage?,
        tried: [String] = [],
        taskNumber: Int? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.number = number
        self.label = label
        self.urlString = urlString
        self.scrollY = scrollY
        self.thumbnail = thumbnail
        self.tried = tried
        self.taskNumber = taskNumber
        self.capturedAt = capturedAt
    }

    /// How many bookmarks are kept — oldest dropped.
    static let capacity = 5
    /// A point counts as worth going back to until this many routes have failed there.
    static let exhaustedAfter = 3

    /// True when this point still has something left to try.
    var hasUntriedRoute: Bool {
        tried.count < Self.exhaustedAfter
    }

    var triedLine: String {
        tried.isEmpty ? "nothing tried from here yet" : tried.joined(separator: "; ")
    }
}
