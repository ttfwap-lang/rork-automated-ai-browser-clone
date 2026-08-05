import SwiftUI

/// Where the agent currently is inside its plan-see-decide-act-verify loop.
enum AgentPhase: Equatable {
    case idle
    case planning
    case observing
    case thinking
    case awaitingApproval
    case acting
    case verifying
    /// Distilling a confirmed success into a route worth keeping.
    case remembering
    /// Running a saved one-tap replay, repairing steps the site has moved.
    case replaying
    /// Working out what a form is asking for, on the device, for nothing.
    case matching

    var label: String {
        switch self {
        case .idle: "IDLE"
        case .planning: "PLANNING"
        case .observing: "OBSERVING"
        case .thinking: "THINKING"
        case .awaitingApproval: "AWAITING APPROVAL"
        case .acting: "ACTING"
        case .verifying: "VERIFYING"
        case .remembering: "REMEMBERING"
        case .replaying: "REPLAYING"
        case .matching: "MATCHING"
        }
    }

    var color: Color {
        switch self {
        case .idle: Theme.textSecondary
        case .planning: Theme.violet
        case .observing, .thinking: Theme.cyan
        case .awaitingApproval: Theme.amber
        case .acting: Theme.green
        case .verifying: Theme.violet
        case .remembering: Theme.cyan
        case .replaying: Theme.amber
        case .matching: Theme.cyan
        }
    }

    /// Line shown in the mission log while the agent is busy but has nothing to show yet.
    var activityLine: String {
        switch self {
        case .planning: "WRITING THE MISSION PLAN…"
        case .observing: "CAPTURING PAGE…"
        case .thinking: "ANALYZING SNAPSHOT…"
        case .verifying: "INDEPENDENT CHECK — LOOKING AT THE PAGE WITH FRESH EYES…"
        case .remembering: "WRITING DOWN THE ROUTE THAT WORKED…"
        case .replaying: "REPLAYING YOUR SAVED ROUTE…"
        case .matching: "READING THIS FORM AGAINST YOUR DOSSIER — FREE, ON YOUR IPHONE…"
        default: "WORKING…"
        }
    }

    /// True while the agent is looking or reasoning — drives the scanning border.
    var isBusyThinking: Bool {
        switch self {
        case .planning, .observing, .thinking, .verifying, .remembering, .replaying, .matching: true
        case .idle, .awaitingApproval, .acting: false
        }
    }
}
