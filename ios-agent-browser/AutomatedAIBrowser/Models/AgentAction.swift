import Foundation

/// One action decided by the model. All fields are optional except `type`;
/// which fields matter depends on the action kind.
nonisolated struct AgentAction: Codable, Equatable {
    /// One element-and-text pair of a one-shot form fill.
    nonisolated struct FormField: Codable, Equatable {
        let element: Int
        let text: String
    }

    var type: String
    /// Badge number of the targeted element (element-targeted moves).
    var element: Int?
    /// Resolved descriptor of the targeted element, e.g. `button "Add to cart"`.
    /// Filled in by the app from the page observation — not by the model.
    var elementName: String?
    var x: Double?
    var y: Double?
    var text: String?
    var submit: Bool?
    var direction: String?
    var amount: Double?
    var url: String?
    var summary: String?
    var reason: String?
    /// Dropdown option text (select_option).
    var option: String?
    /// Desired toggle state (set_toggle).
    var on: Bool?
    /// Slider target as percent 0–100 (set_slider).
    var value: Double?
    /// Field/text pairs for the one-shot form fill (fill_form).
    var fields: [FormField]?
    /// Drag source element number (drag).
    var from: Int?
    /// Drag target element number (drag).
    var to: Int?
    /// Drag coordinate fallbacks, normalized 0–1000 (drag).
    var fromX: Double?
    var fromY: Double?
    var toX: Double?
    var toY: Double?
    /// Mission-plan task number this move serves, as reported by the model.
    var task: Int?
    /// Task numbers the model can SEE are finished on the current screen.
    var completedTasks: [Int]?
    /// Replacement tasks for the remainder of the plan (revise_plan).
    var tasks: [PlannedTask]?
    /// Checkpoint number to go back to (rewind).
    var bookmark: Int?

    var kind: AgentActionKind {
        AgentActionKind(rawValue: type.lowercased()) ?? .unknown
    }

    /// Short human-readable parameter string for step cards and logs.
    var detailText: String {
        switch kind {
        case .tapElement, .longPress, .hover:
            return targetDescriptor
        case .typeInto:
            let quoted = "\"\(String((text ?? "").prefix(40)))\""
            let suffix = submit == true ? " + enter" : ""
            return "\(quoted) → \(targetDescriptor)\(suffix)"
        case .fillForm:
            let count = fields?.count ?? 0
            return "\(count) field\(count == 1 ? "" : "s")\(submit == true ? " + submit" : "")"
        case .fillFromDossier:
            return "from your dossier\(submit == true ? " + submit" : "")"
        case .selectOption:
            return "\"\(String((option ?? "?").prefix(32)))\" → \(targetDescriptor)"
        case .setToggle:
            return "\(targetDescriptor) → \(on == false ? "OFF" : "ON")"
        case .setSlider:
            return "\(targetDescriptor) → \(Int(value ?? 50))%"
        case .drag:
            let source = from.map { "[\($0)]" } ?? "(\(Int(fromX ?? 0)), \(Int(fromY ?? 0)))"
            let target = to.map { "[\($0)]" } ?? "(\(Int(toX ?? 0)), \(Int(toY ?? 0)))"
            return "\(source) → \(target)"
        case .swipe:
            let dir = direction ?? "left"
            return element.map { "\(dir) [\($0)]" } ?? dir
        case .tap:
            return "(\(Int(x ?? 0)), \(Int(y ?? 0)))"
        case .typeText:
            let quoted = "\"\(String((text ?? "").prefix(48)))\""
            return submit == true ? quoted + " + enter" : quoted
        case .scroll:
            return "\(direction ?? "down") \(Int(amount ?? 600))px"
        case .navigate:
            return url ?? ""
        case .extract:
            return "whole page"
        case .pageOverview:
            return "up to 6 screens"
        case .wait:
            return "2s"
        case .back:
            return ""
        case .revisePlan:
            let count = tasks?.count ?? 0
            let plural = count == 1 ? "" : "s"
            return "\(count) task\(plural) ahead — \(reason ?? "the plan no longer fits")"
        case .done:
            return summary ?? ""
        case .fail:
            return reason ?? ""
        case .rewind:
            return "to checkpoint \(bookmark ?? 0) — \(reason ?? "this route is dead")"
        case .verify:
            return summary ?? ""
        case .headStart:
            return summary ?? ""
        case .replay:
            return summary ?? ""
        case .mistake:
            return summary ?? ""
        case .unknown:
            return type
        }
    }

    /// The move in plain words, with no element numbers — for the live panel,
    /// where the point is to read what the agent is doing at a glance rather than
    /// to audit it.
    var plainSentence: String {
        let target = (elementName ?? "").trimmed
        let named = target.isEmpty ? nil : target
        switch kind {
        case .tapElement:
            return named.map { "tap the \($0)" } ?? "tap a control"
        case .longPress:
            return named.map { "press and hold the \($0)" } ?? "press and hold"
        case .hover:
            return named.map { "hover over the \($0)" } ?? "hover"
        case .typeInto, .typeText:
            let where_ = named.map { " into the \($0)" } ?? ""
            let quoted = (text ?? "").isEmpty ? "" : " “\(String((text ?? "").prefix(28)))”"
            return "type\(quoted)\(where_)\(submit == true ? " and press enter" : "")"
        case .fillForm:
            let count = fields?.count ?? 0
            return "fill in \(count) field\(count == 1 ? "" : "s")\(submit == true ? " and submit" : "")"
        case .fillFromDossier:
            return "fill this form in from your dossier\(submit == true ? " and submit" : "")"
        case .selectOption:
            let option = (option ?? "").isEmpty ? "an option" : "“\(String((option ?? "").prefix(24)))”"
            return named.map { "choose \(option) from the \($0)" } ?? "choose \(option)"
        case .setToggle:
            return "turn the \(named ?? "switch") \(on == false ? "off" : "on")"
        case .setSlider:
            return "set the \(named ?? "slider") to \(Int(value ?? 50))%"
        case .drag:
            return "drag one thing onto another"
        case .swipe:
            return "swipe \(direction ?? "left")"
        case .tap:
            return "tap a spot on the page"
        case .scroll:
            return "scroll \(direction ?? "down")"
        case .navigate:
            return "open \(RecipeMove.shortAddress(url ?? ""))"
        case .back:
            return "go back"
        case .extract:
            return "read the whole page"
        case .pageOverview:
            return "look at the whole page at once"
        case .wait:
            return "wait for the page"
        case .revisePlan:
            let count = tasks?.count ?? 0
            return "rewrite the plan — \(count) task\(count == 1 ? "" : "s") ahead"
        case .rewind:
            return "go back to checkpoint \(bookmark ?? 0)"
        case .done:
            return "call it done"
        case .fail:
            return "report that this cannot be done"
        case .verify, .headStart, .replay, .mistake, .unknown:
            return kind.label.lowercased()
        }
    }

    /// `[14] button "Add to cart"` when resolved, `[14]` otherwise.
    private var targetDescriptor: String {
        let number = "[\(element ?? 0)]"
        guard let elementName, !elementName.isEmpty else { return number }
        return "\(number) \(elementName)"
    }

    /// Compact signature used to detect action repetition loops.
    var repetitionSignature: String {
        let parts: [String] = [
            kind.rawValue,
            "\(element ?? -1)",
            "\(Int(x ?? -1))",
            "\(Int(y ?? -1))",
            text ?? "",
            direction ?? "",
            url ?? "",
            option ?? "",
            on.map(String.init) ?? "",
            "\(Int(value ?? -1))",
            "\(from ?? -1)",
            "\(to ?? -1)",
            "\(fields?.count ?? 0)",
            "\(bookmark ?? -1)",
        ]
        return parts.joined(separator: "|")
    }
}
