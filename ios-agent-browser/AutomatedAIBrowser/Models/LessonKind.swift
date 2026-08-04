import Foundation

/// The KIND of thing that went wrong, rather than the specific instance of it.
///
/// The grouping is the whole point. A notebook with one entry per bad run fills
/// up with noise no later run can use ("the third result was the wrong chair"),
/// and a briefing full of noise makes the agent worse rather than better. A
/// notebook grouped by kind of failure says something a later run can act on:
/// "the cookie wall here has to go first", "the search box here ignores Enter".
nonisolated enum LessonKind: String, Codable, CaseIterable, Sendable {
    /// A wall no amount of cleverness gets past: sign-in, paywall, CAPTCHA, bot check.
    case gate
    /// A control that was pressed and did nothing at all.
    case deadControl = "dead_control"
    /// A banner or dialog that has to be cleared before anything else works.
    case overlay
    /// Something the route expected to find is no longer there.
    case vanished
    /// Text went in but the field did not keep it, or Enter did nothing.
    case typingIgnored = "typing_ignored"
    /// The route ran out of road before the goal.
    case deadEnd = "dead_end"
    /// The agent claimed success here and the independent check refused it.
    case falseClaim = "false_claim"
    /// The page was slower to settle than the run could afford.
    case slow

    var label: String {
        switch self {
        case .gate: "ASKS YOU TO SIGN IN"
        case .deadControl: "CONTROL DOES NOTHING"
        case .overlay: "BANNER IN THE WAY"
        case .vanished: "SOMETHING MOVED"
        case .typingIgnored: "TYPING DOESN'T STICK"
        case .deadEnd: "ROUTE RUNS OUT"
        case .falseClaim: "LOOKS DONE WHEN IT ISN'T"
        case .slow: "SLOW TO SETTLE"
        }
    }

    var icon: String {
        switch self {
        case .gate: "lock.fill"
        case .deadControl: "hand.tap"
        case .overlay: "rectangle.on.rectangle.slash"
        case .vanished: "questionmark.square.dashed"
        case .typingIgnored: "keyboard.badge.ellipsis"
        case .deadEnd: "arrow.triangle.branch"
        case .falseClaim: "exclamationmark.shield"
        case .slow: "clock.badge.exclamationmark"
        }
    }

    /// The caution in plain words, written in code so a lesson exists even on a
    /// phone that cannot run a model and with no paid call ever made.
    func mechanicalCaution(subject: String?) -> String {
        let named = (subject ?? "").trimmed
        switch self {
        case .gate:
            return "this site wanted an account before it would show this"
        case .deadControl:
            return named.isEmpty
                ? "a control here did nothing at all when pressed"
                : "pressing “\(named)” did nothing at all last time"
        case .overlay:
            return named.isEmpty
                ? "a banner covers the page and has to be cleared first"
                : "the “\(named)” banner has to be cleared before anything else works"
        case .vanished:
            return named.isEmpty
                ? "something the route expected was not on the page any more"
                : "“\(named)” was not where it used to be"
        case .typingIgnored:
            return named.isEmpty
                ? "a field here did not keep what was typed into it"
                : "“\(named)” did not keep what was typed into it"
        case .deadEnd:
            return "the obvious route ran out of road here before the goal"
        case .falseClaim:
            return "it is easy to think the job is done here when the page does not show it"
        case .slow:
            return "this site is slow to settle — give it a moment before acting"
        }
    }
}
