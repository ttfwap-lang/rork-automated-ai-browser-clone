import Foundation

/// Whether the agent acts on its own or waits for user approval before each move.
nonisolated enum AgentMode: String, Codable, CaseIterable, Identifiable {
    case autopilot
    case supervised

    var id: String { rawValue }

    var label: String {
        switch self {
        case .autopilot: "AUTO"
        case .supervised: "SUPERVISED"
        }
    }

    var fullName: String {
        switch self {
        case .autopilot: "Autopilot"
        case .supervised: "Supervised"
        }
    }

    var icon: String {
        switch self {
        case .autopilot: "bolt.fill"
        case .supervised: "hand.raised.fill"
        }
    }
}
