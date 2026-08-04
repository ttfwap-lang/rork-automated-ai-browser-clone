import Foundation

/// Whether this iPhone's own free, private AI can answer right now — and, when
/// it cannot, which honest reason applies.
///
/// Device reality is stated up front rather than buried: on a phone that cannot
/// run the model, or with Apple Intelligence switched off, or while the model is
/// still downloading, the free tier simply never appears and every step is
/// decided in the cloud exactly as before.
nonisolated enum OnDeviceState: String, Codable, Equatable, Sendable, CaseIterable {
    /// Ready to answer, on device, for free.
    case ready
    /// This iPhone will never run it — the chip or the iOS version is too old.
    case notEligible
    /// Apple Intelligence is switched off in iOS Settings.
    case notEnabled
    /// Switched on, but the model is still downloading.
    case downloading
    /// Present, but iOS declined for a reason it did not name.
    case unavailable

    var isReady: Bool { self == .ready }

    var label: String {
        switch self {
        case .ready: "Ready"
        case .notEligible: "Not available on this iPhone"
        case .notEnabled: "Apple Intelligence is off"
        case .downloading: "Still downloading"
        case .unavailable: "Not answering"
        }
    }

    /// Plain words: what this state means for the user's runs.
    var caption: String {
        switch self {
        case .ready:
            "Routine steps are decided on your iPhone for free. Nothing leaves the device, and it works offline."
        case .notEligible:
            "This iPhone can't run Apple's on-device model, so every step uses the cloud exactly as before. Nothing else changes."
        case .notEnabled:
            "Turn on Apple Intelligence in iOS Settings and routine steps will be decided free, on your iPhone."
        case .downloading:
            "Apple Intelligence is still downloading its model. The cloud handles every step until that finishes."
        case .unavailable:
            "Your iPhone's model isn't answering right now, so the cloud is handling every step."
        }
    }

    /// Shown next to the state in Settings.
    var symbol: String {
        switch self {
        case .ready: "checkmark.seal.fill"
        case .notEligible: "iphone.slash"
        case .notEnabled: "power"
        case .downloading: "arrow.down.circle"
        case .unavailable: "exclamationmark.triangle"
        }
    }
}
