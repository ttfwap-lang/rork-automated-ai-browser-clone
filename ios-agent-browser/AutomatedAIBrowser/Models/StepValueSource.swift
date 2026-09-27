import Foundation

/// Where a saved script's typing step gets its value from when it runs.
nonisolated enum StepValueSource: Codable, Hashable, Sendable {
    /// Ask when the script is launched — the default, and how a run is saved.
    case askAtLaunch
    /// Always type exactly this. Written by you in the script editor.
    case fixed(String)
    /// Fill it from your identity details (the dossier) at run time. The value
    /// itself is never stored in the script — only which detail to use.
    case identity(DossierFieldKind)

    /// Short label for the step list.
    var summary: String {
        switch self {
        case .askAtLaunch: "asked when you run it"
        case .fixed(let text): "always “\(String(text.prefix(24)))”"
        case .identity(let kind): "from your identity: \(kind.label)"
        }
    }
}
