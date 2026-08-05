import Foundation

/// One field on the page, resolved to the fact it is asking for, together with
/// how that was worked out. Every source here is free — none of them costs a
/// paid call.
nonisolated struct FieldMatch: Identifiable, Equatable {

    /// How the match was made, cheapest and most certain first.
    nonisolated enum Source: String, Codable, CaseIterable {
        /// The page declared its own purpose in machine-readable markup.
        case declared
        /// Matched from the field's own words.
        case label
        /// Your iPhone read the label and said what it meant.
        case meaning

        var badge: String {
            switch self {
            case .declared: "DECLARED"
            case .label: "LABEL"
            case .meaning: "IPHONE"
            }
        }

        /// How certain this route is, in plain words.
        var caption: String {
            switch self {
            case .declared: "the page said what it wanted"
            case .label: "matched from its own label"
            case .meaning: "read by your iPhone"
            }
        }

        /// True when the site itself told us — nothing was inferred.
        var isCertain: Bool { self == .declared }
    }

    let probe: FormFieldProbe
    let kind: DossierFieldKind
    let source: Source

    var id: Int { probe.id }

    /// `[7] "Email address" → email (the page said what it wanted)`
    var auditLine: String {
        "\(probe.descriptor) → \(kind.briefingName) (\(source.caption))"
    }
}
