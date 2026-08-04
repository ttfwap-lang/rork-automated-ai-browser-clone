import SwiftUI

/// Central palette for the mission-control aesthetic: deep charcoal surfaces with an electric cyan accent.
enum Theme {
    static let bg = Color(red: 0.043, green: 0.055, blue: 0.075)
    static let surface = Color(red: 0.071, green: 0.094, blue: 0.125)
    static let elevated = Color(red: 0.102, green: 0.133, blue: 0.173)
    static let line = Color.white.opacity(0.08)
    static let cyan = Color(red: 0.0, green: 0.898, blue: 1.0)
    static let textPrimary = Color(red: 0.902, green: 0.929, blue: 0.953)
    static let textSecondary = Color(red: 0.49, green: 0.545, blue: 0.60)
    static let green = Color(red: 0.24, green: 0.863, blue: 0.592)
    static let red = Color(red: 1.0, green: 0.302, blue: 0.427)
    static let amber = Color(red: 1.0, green: 0.706, blue: 0.329)
    /// Reserved for mission-level thinking: planning and the independent check.
    static let violet = Color(red: 0.639, green: 0.545, blue: 1.0)
}

extension View {
    /// Small monospaced, letter-spaced caps label used across the cockpit UI.
    func techLabel(_ size: CGFloat = 11) -> some View {
        self
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .tracking(1.1)
    }
}

extension RunOutcome {
    var color: Color {
        switch self {
        case .completed: Theme.green
        case .unconfirmed: Theme.amber
        case .failed: Theme.red
        case .stopped: Theme.textSecondary
        }
    }
}

extension VerificationVerdict {
    var color: Color {
        switch self {
        case .confirmed: Theme.green
        case .rejected: Theme.red
        case .unclear: Theme.amber
        }
    }
}

extension ModelChoice {
    /// Free work is coloured with the app's own accent — it is the tier that runs
    /// on the device rather than on anyone's servers.
    var color: Color {
        switch self {
        case .onDevice: Theme.cyan
        case .fast: Theme.green
        case .precise: Theme.violet
        }
    }
}

extension MissionTaskState {
    var color: Color {
        switch self {
        case .pending: Theme.textSecondary
        case .current: Theme.cyan
        case .done: Theme.green
        case .skipped: Theme.textSecondary.opacity(0.7)
        }
    }
}
