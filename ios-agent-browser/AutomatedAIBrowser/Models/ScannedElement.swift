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
    /// Nearest heading or labelled container, e.g. the product card an "Add to
    /// cart" button sits in. Only scanned for look-alikes and unlabeled controls.
    var context: String? = nil
    /// Where a link goes, e.g. `/product/123`. Same condition as `context`.
    var linkHint: String? = nil
    /// Input type of a non-text field, e.g. `email`, `tel`, `date`.
    var inputType: String? = nil

    /// Compact descriptor for feedback lines and step cards, e.g. `button "Add to cart"`.
    var shortDescriptor: String {
        name.isEmpty ? "\(kind.rawValue) (unlabeled)" : "\(kind.rawValue) \"\(name)\""
    }

    /// One line of the page map, e.g. `[7] field "Email" (empty, required)`, or
    /// `[12] button "Add to cart" (in: "Sony WH-1000XM5")` for a look-alike.
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
        if let inputType, !inputType.isEmpty {
            stateParts.append("type: \(inputType)")
        }
        if !stateParts.isEmpty {
            line += " (\(stateParts.joined(separator: ", ")))"
        }
        if let context, !context.isEmpty {
            line += " (in: \"\(context)\")"
        }
        if let linkHint, !linkHint.isEmpty {
            line += " \u{2192} \(linkHint)"
        }
        if let panelLabel, !panelLabel.isEmpty {
            line += " (in embedded panel: \(panelLabel))"
        }
        return line
    }

    /// What this element IS, stable across rescans: page, kind, name, and — for
    /// look-alikes — the container it sits in. Badge numbers are reassigned on
    /// every look, so remembering "tap [14] failed" would bar whatever happens
    /// to be number 14 next time; this remembers the control itself.
    func targetKey(in observation: PageObservation, urlString: String) -> String {
        let page = Self.pageKey(urlString)
        let label = name.trimmed.lowercased()
        guard !label.isEmpty else {
            // Nothing to recognise it by: scope the number to this page at least.
            return "\(page)|\(kind.rawValue)|#\(id)"
        }
        let place = (context ?? "").trimmed.lowercased()
        var key = "\(page)|\(kind.rawValue)|\(label)"
        if !place.isEmpty { key += "|in:\(place)" }
        let twins = observation.elements.filter {
            $0.kind == kind
                && $0.name.trimmed.lowercased() == label
                && ($0.context ?? "").trimmed.lowercased() == place
                && $0.panelLabel == panelLabel
        }
        if twins.count > 1, let ordinal = twins.firstIndex(where: { $0.id == id }) {
            key += "|nth:\(ordinal)"
        }
        if let panelLabel, !panelLabel.isEmpty { key += "|panel:\(panelLabel)" }
        return key
    }

    /// `shop.test/search` — host and path, without the query, so the same
    /// control on page 2 of the same results is still the same control.
    static func pageKey(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return "" }
        return host + url.path
    }
}
