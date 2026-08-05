import Foundation

/// The set of moves the AI agent can make inside the browser.
nonisolated enum AgentActionKind: String, Codable, CaseIterable {
    case tapElement = "tap_element"
    case typeInto = "type_into"
    case fillForm = "fill_form"
    /// Fill a form from the person's own dossier. The values are resolved on the
    /// device at act time — the model asks for the fill, and never sees a value.
    case fillFromDossier = "fill_from_dossier"
    case selectOption = "select_option"
    case setToggle = "set_toggle"
    case setSlider = "set_slider"
    case drag
    case longPress = "long_press"
    case hover
    case swipe
    case tap
    case typeText = "type_text"
    case scroll
    case navigate
    case back
    case extract
    case pageOverview = "page_overview"
    case wait
    case revisePlan = "revise_plan"
    case rewind
    case done
    case fail
    /// The app's own independent-check entry — never callable by the model.
    case verify = "independent_check"
    /// The app's own head-start entry, summarising moves replayed from memory.
    /// Never callable by the model.
    case headStart = "head_start"
    /// The app's own entry for a saved one-tap replay. Never callable by the model.
    case replay
    /// Your own entry: you told the agent the last move was a mistake. Never
    /// callable by the model — the agent cannot flag its own move as your
    /// objection.
    case mistake = "user_mistake"
    case unknown

    var label: String {
        switch self {
        case .tapElement: "TAP"
        case .typeInto: "TYPE"
        case .fillForm: "FILL"
        case .fillFromDossier: "AUTOFILL"
        case .selectOption: "SELECT"
        case .setToggle: "TOGGLE"
        case .setSlider: "SLIDER"
        case .drag: "DRAG"
        case .longPress: "HOLD"
        case .hover: "HOVER"
        case .swipe: "SWIPE"
        case .tap: "TAP"
        case .typeText: "TYPE"
        case .scroll: "SCROLL"
        case .navigate: "NAVIGATE"
        case .back: "BACK"
        case .extract: "READ"
        case .pageOverview: "PAGE VIEW"
        case .wait: "WAIT"
        case .revisePlan: "PLAN REVISED"
        case .rewind: "REWIND"
        case .done: "DONE"
        case .fail: "FAIL"
        case .verify: "CHECK"
        case .headStart: "HEAD START"
        case .replay: "ONE-TAP REPLAY"
        case .mistake: "YOU FLAGGED A MISTAKE"
        case .unknown: "UNKNOWN"
        }
    }

    var icon: String {
        switch self {
        case .tapElement: "hand.tap.fill"
        case .typeInto: "keyboard.fill"
        case .fillForm: "square.and.pencil"
        case .fillFromDossier: "person.text.rectangle.fill"
        case .selectOption: "chevron.down.circle.fill"
        case .setToggle: "switch.2"
        case .setSlider: "slider.horizontal.3"
        case .drag: "hand.draw.fill"
        case .longPress: "dot.circle.and.hand.point.up.left.fill"
        case .hover: "cursorarrow.rays"
        case .swipe: "arrow.left.and.right"
        case .tap: "scope"
        case .typeText: "keyboard"
        case .scroll: "arrow.up.arrow.down"
        case .navigate: "globe"
        case .back: "arrow.uturn.left"
        case .extract: "doc.text.magnifyingglass"
        case .pageOverview: "rectangle.expand.vertical"
        case .wait: "clock.fill"
        case .revisePlan: "list.bullet.rectangle.portrait.fill"
        case .rewind: "arrow.uturn.backward.circle.fill"
        case .done: "checkmark.seal.fill"
        case .fail: "xmark.octagon.fill"
        case .verify: "checkmark.shield.fill"
        case .headStart: "bolt.horizontal.fill"
        case .replay: "bolt.badge.clock.fill"
        case .mistake: "hand.raised.slash.fill"
        case .unknown: "questionmark.circle"
        }
    }

    /// False for kinds the app creates itself — a hallucinated tool name matching
    /// one of these must never be accepted as a move.
    var isModelCallable: Bool {
        switch self {
        case .verify, .headStart, .replay, .mistake, .unknown: false
        default: true
        }
    }

    /// Moves that change the plan or end the run rather than touching the page.
    var isPageAction: Bool {
        switch self {
        case .revisePlan, .rewind, .done, .fail, .verify, .headStart, .replay, .mistake, .unknown: false
        default: true
        }
    }
}
