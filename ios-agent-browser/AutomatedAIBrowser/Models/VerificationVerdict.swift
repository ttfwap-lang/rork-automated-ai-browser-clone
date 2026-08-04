import Foundation

/// What the independent check concluded about a claimed success.
nonisolated enum VerificationVerdict: String, Codable, Hashable {
    /// The screen visibly proves the mission's success statement.
    case confirmed
    /// The evidence contradicts the claim, or its key detail is nowhere on the page.
    case rejected
    /// The evidence is genuinely insufficient to judge either way.
    case unclear

    var label: String {
        switch self {
        case .confirmed: "CONFIRMED"
        case .rejected: "REJECTED"
        case .unclear: "UNCLEAR"
        }
    }

    var icon: String {
        switch self {
        case .confirmed: "checkmark.seal.fill"
        case .rejected: "xmark.seal.fill"
        case .unclear: "questionmark.diamond.fill"
        }
    }
}
