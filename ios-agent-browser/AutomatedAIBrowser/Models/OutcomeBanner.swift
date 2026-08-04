import Foundation

/// Banner shown in the bottom dock after a run ends.
struct OutcomeBanner: Equatable {
    let outcome: RunOutcome
    let message: String
}
