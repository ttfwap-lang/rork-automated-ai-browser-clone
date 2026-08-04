import Foundation

/// Which model writes the mission plan — or whether planning runs at all.
nonisolated enum PlanningPreference: String, Codable, CaseIterable, Identifiable {
    /// Always plan with the strong model, even when steps run on the fast one.
    case strong
    /// Plan with whichever model the steps use.
    case same
    /// No planning — exactly the pre-plan behavior.
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strong: "Strong model"
        case .same: "Same as steps"
        case .off: "Off"
        }
    }

    var isEnabled: Bool { self != .off }
}
