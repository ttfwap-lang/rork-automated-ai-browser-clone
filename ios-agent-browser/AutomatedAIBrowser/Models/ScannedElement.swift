import Foundation

/// One interactive element catalogued by the page scanner: its badge number,
/// kind, visible name, states, and exact viewport rect (CSS pixels).
nonisolated struct ScannedElement: Identifiable, Codable, Equatable {
    nonisolated enum Kind: String, Codable {
        case button
        case link
        case field
        case toggle
        case dropdown
        case other
    }

    let id: Int
    let kind: Kind
    let name: String
    let states: [String]
    /// Preview of a field's current value (never captured for password fields).
    let valuePreview: String?
    let isEditable: Bool
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    /// Host of the embedded panel this element lives in; nil for the main page.
    var panelLabel: String? = nil

    /// Compact descriptor for feedback lines and step cards, e.g. `button "Add to cart"`.
    var shortDescriptor: String {
        name.isEmpty ? "\(kind.rawValue) (unlabeled)" : "\(kind.rawValue) \"\(name)\""
    }

    /// One line of the page map, e.g. `[7] field "Email" (empty, required)`.
    var mapLine: String {
        var line = "[\(id)] \(kind.rawValue)"
        line += name.isEmpty ? " (unlabeled)" : " \"\(name)\""

        var stateParts = states.filter { $0 != "filled" }
        if states.contains("filled") {
            if let preview = valuePreview, !preview.isEmpty {
                stateParts.insert("filled: \"\(preview)\"", at: 0)
            } else {
                stateParts.insert("filled", at: 0)
            }
        }
        if !stateParts.isEmpty {
            line += " (\(stateParts.joined(separator: ", ")))"
        }
        if let panelLabel, !panelLabel.isEmpty {
            line += " (in embedded panel: \(panelLabel))"
        }
        return line
    }
}
