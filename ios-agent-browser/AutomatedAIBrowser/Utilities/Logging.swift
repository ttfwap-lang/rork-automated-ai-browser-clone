import Foundation
import OSLog

/// Central structured logging and signpost instrumentation for the browser agent.
///
/// An autonomous browser agent lives at the intersection of a live rendering
/// engine, local heuristic checks, on-device small models, and remote frontier
/// models. When a multi-step run goes off the rails, post-mortem diagnosis cannot
/// rely on synchronous breakpoints or interactive debuggers without distorting
/// real-world page timing and event sequencing.
///
/// This namespace gathers unified logging categories and performance signposts
/// into one place. Every category maps to a distinct subsystem boundary:
///
/// - `loop`: The outer plan-see-decide-act-verify cycle, run boundaries, and phase signposts.
/// - `ai`: Routing decisions, tier selection, gate approvals or rejections, and raw network telemetry.
/// - `webview`: Navigation lifecycle changes and DOM inspection diagnostics.
/// - `persistence`: History store disk writes and thumbnail saves.
/// - `ledger`: Site fault tracking and error pattern accounting.
///   (Stage 1b.5 introduces the FailureLedger; this category is established now
///   so subsequent stages do not need to alter core logging infrastructure.)
///
/// Structural and telemetry values (durations, counts, HTTP status codes, enum
/// raw values) are kept public for debugging. Any data originating from the user
/// or scraped from the live web page (goal text, typed inputs, element titles,
/// and URL queries) is strictly marked private to honor the application's
/// zero-leakage privacy guarantee.
nonisolated enum AppLog {

    /// Subsystem identifier derived from the bundle identifier, with a fallback
    /// matching the convention in Dossier.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.rork.ok9ihehfmbqfp1mm5kd0h"

    /// The agent's core planning and execution loop: step progress, action kinds,
    /// rewinds, plan revisions, and end-of-run accounting.
    static let loop = Logger(subsystem: subsystem, category: "loop")

    /// Intelligence routing and network calls: model selection, on-device gate
    /// evaluations, cloud handoffs, and payload transfer sizes.
    static let ai = Logger(subsystem: subsystem, category: "ai")

    /// WebKit bridge observations: provisional navigations, frame redirects,
    /// and page scanner script availability.
    static let webview = Logger(subsystem: subsystem, category: "webview")

    /// Local disk persistence: history record serialization and thumbnail writes.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")

    /// Site failure accounting and fault classification.
    ///
    /// Stage 1b.5 introduces the FailureLedger; this category is established now
    /// so subsequent stages do not need to reopen logging definitions.
    static let ledger = Logger(subsystem: subsystem, category: "ledger")

    /// Optional BrowserAct and Crawl4AI adapters. Only structural transport facts
    /// are public; targets, payloads, responses, and credentials stay private.
    static let plugin = Logger(subsystem: subsystem, category: "plugin")

    /// Shared signposter for measuring wall-clock phase intervals in Instruments.
    /// Emits signposts under the `loop` category to profile step bottlenecks.
    static let loopSignposter = OSSignposter(subsystem: subsystem, category: "loop")

    /// Sanitizes a URL so that only its scheme, host, and path are retained.
    ///
    /// Query strings and fragments frequently carry session tokens, auth keys,
    /// or sensitive search queries. Stripping them ensures URLs can be inspected
    /// in diagnostic traces without violating user privacy.
    static func sanitize(url: URL?) -> String {
        guard let url else { return "none" }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.host ?? "unknown"
        }
        let host = components.host ?? ""
        let path = components.path
        if host.isEmpty && path.isEmpty {
            return "none"
        }
        return "\(host)\(path)"
    }
}
