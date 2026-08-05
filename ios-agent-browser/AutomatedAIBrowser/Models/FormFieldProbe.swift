import Foundation

/// One fillable field read off the live page, with everything needed to work out
/// what it wants — without asking anyone.
///
/// `id` is the badge number from the page scan, so a probe and the numbered
/// element the agent can see are always the same thing.
nonisolated struct FormFieldProbe: Identifiable, Equatable, Codable {

    /// What kind of control this is. Only `text`, `textarea` and `select` can be
    /// filled today; the rest are catalogued so the report can say honestly what
    /// it left alone.
    nonisolated enum Widget: String, Codable {
        case text
        case textarea
        case select
        case date
        case checkbox
        case radio
        case other

        /// True for the widgets a value can be written into right now.
        var isFillable: Bool {
            switch self {
            case .text, .textarea, .select: true
            case .date, .checkbox, .radio, .other: false
            }
        }

        var plainName: String {
            switch self {
            case .text: "text field"
            case .textarea: "text box"
            case .select: "dropdown"
            case .date: "date picker"
            case .checkbox: "checkbox"
            case .radio: "choice"
            case .other: "control"
            }
        }
    }

    let id: Int
    /// The `autocomplete` token the page declared, already lowercased and
    /// stripped of section/billing/shipping prefixes. Empty when it declared none.
    let declared: String
    /// The field's `name` or `id` attribute — the developer's own word for it.
    let attribute: String
    /// The visible label, or the closest thing to one.
    let label: String
    /// The `type` attribute for inputs, e.g. `email`, `tel`, `date`.
    let type: String
    let widget: Widget
    let isRequired: Bool
    let isEmpty: Bool
    /// True for password, card, security-code and one-time-code fields. These are
    /// never probed for a value, never matched and never typed into.
    let isSensitive: Bool
    /// Visible option texts, for dropdowns only (capped in the page script).
    let options: [String]

    /// `[7] "Email address"` — how a field is named in reports and logs.
    var descriptor: String {
        let name = label.isEmpty ? (attribute.isEmpty ? widget.plainName : attribute) : label
        return "[\(id)] \"\(String(name.prefix(40)))\""
    }

    /// Everything the field says about itself, lowercased, for phrase matching.
    /// The label leads because it is what a person would read.
    var matchText: String {
        [label, attribute, declared]
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// True when this field is worth trying to fill at all.
    var isWorthFilling: Bool {
        !isSensitive && isEmpty && widget.isFillable
    }
}
