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
    /// App-resolved identity of the targeted element that survives a rescan
    /// (`ScannedElement.targetKey`). Used in place of the badge number when
    /// remembering which moves failed or were barred. Never set by the model.
    var targetKey: String?
    /// Facts the agent noted from the page alongside this move.
    var notedFacts: [NotedFact]?
    /// The question put to the person (ask_user).
    var question: String?
    /// Suggested answers the person can pick from (ask_user).
    var choices: [String]?
    /// The model's own read of its previous move: worked, failed, unclear, or
    /// first_move. Makes it judge the last result before choosing the next.
    var previousMove: String?
    /// The immediate objective this move serves, in the model's words.
    var nextGoal: String?
    /// What to look for when reading the page (extract), so the most relevant
    /// sections come back rather than the first few thousand characters.
    var query: String?
    /// Where to continue a long reading from (extract), in characters.
    var startFrom: Int?
    /// What the person is asked to do themselves (hand_over).
    var instruction: String?
    /// The moves of a do_sequence, in order; only the last may change the page.
    var moves: [AgentAction]?
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
            if let query, !query.isEmpty { return "for \"\(String(query.prefix(40)))\"" }
            if let startFrom, startFrom > 0 { return "from character \(startFrom)" }
            return "whole page"
        case .listOptions:
            return targetDescriptor
        case .findText:
            return "\"\(String((text ?? "").prefix(40)))\""
        case .sequence:
            let parts = (moves ?? []).map { "\($0.kind.label) \($0.detailText)" }
            return parts.joined(separator: " → ")
        case .handOver:
            return instruction ?? reason ?? ""
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
        case .askUser:
            return "\"\(String((question ?? "").prefix(80)))\""
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
            if let query, !query.isEmpty { return "read the page for “\(String(query.prefix(30)))”" }
            return "read the whole page"
        case .listOptions:
            return named.map { "look at the choices in the \($0)" } ?? "look at a dropdown's choices"
        case .findText:
            return "find “\(String((text ?? "").prefix(28)))” on the page"
        case .sequence:
            let count = moves?.count ?? 0
            return "make \(count) move\(count == 1 ? "" : "s") in a row"
        case .handOver:
            return "hand the browser to you: \(String((instruction ?? "a step only you can do").prefix(60)))"
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
        case .askUser:
            return "ask you: \(String((question ?? "a question").prefix(60)))"
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
            // The control itself when known — a badge number means something
            // else on every rescan.
            targetKey ?? "\(element ?? -1)",
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
            query ?? "",
            "\(startFrom ?? 0)",
            (moves ?? []).map(\.repetitionSignature).joined(separator: ";"),
        ]
        return parts.joined(separator: "|")
    }
}
