import SwiftUI

/// A run saved as a script you can shape: rename it, reword its goal, drag
/// steps into a new order, swipe one away, or open any step to change what it
/// does, the words behind it, or its code — including which steps fill from
/// your identity details.
struct ScriptEditorView: View {
    @Environment(AgentViewModel.self) private var agent
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Routine
    @State private var editingStep: RecipeMove?
    let isNew: Bool

    init(routine: Routine, isNew: Bool) {
        _draft = State(initialValue: routine)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $draft.title)
                    TextField("Goal", text: $draft.goalTemplate, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Script")
                } footer: {
                    Text("The goal is what the agent keeps working on after the steps have run. ⟨Placeholders⟩ are asked for when you launch the script.")
                }

                Section {
                    ForEach(Array(draft.moves.enumerated()), id: \.element.id) { offset, move in
                        Button {
                            editingStep = move
                        } label: {
                            ScriptStepRow(number: offset + 1, move: move)
                        }
                    }
                    .onMove { source, destination in
                        draft.moves.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        draft.moves.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Hold a step and drag to reorder it. Swipe left to delete. Tap a step to change it.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(isNew ? "Save as Script" : "Edit Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        agent.saveScript(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.cyan)
                    .disabled(draft.moves.isEmpty || draft.title.trimmed.isEmpty)
                }
            }
            .sheet(item: $editingStep) { move in
                ScriptStepEditor(move: move) { edited in
                    if let index = draft.moves.firstIndex(where: { $0.id == edited.id }) {
                        draft.moves[index] = edited
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// One step in the script list: its number, what it does, and what it types.
private struct ScriptStepRow: View {
    let number: Int
    let move: RecipeMove

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.cyan)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(move.plainLine)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(move.kind.label)
                        .techLabel(8)
                        .foregroundStyle(Theme.textSecondary)
                    if move.kind == .typeInto || move.kind == .selectOption {
                        Text((move.valueSource ?? .askAtLaunch).summary)
                            .font(.system(size: 11))
                            .foregroundStyle(isIdentity ? Theme.cyan : Theme.textSecondary)
                    }
                    if move.isCommitting {
                        Text("ASKS FIRST")
                            .techLabel(8)
                            .foregroundStyle(Theme.amber)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private var isIdentity: Bool {
        if case .identity? = move.valueSource { return true }
        return false
    }
}

/// Everything about one step: the words, what it does, where its value comes
/// from, whether it stops to ask, and the code behind it.
struct ScriptStepEditor: View {
    @Environment(\.dismiss) private var dismiss
    let original: RecipeMove
    let onSave: (RecipeMove) -> Void

    @State private var note: String
    @State private var action: AgentActionKind
    @State private var targetName: String
    @State private var valueMode: ValueMode
    @State private var fixedValue: String
    @State private var identityKind: DossierFieldKind
    @State private var submits: Bool
    @State private var urlString: String
    @State private var direction: String
    @State private var amount: Double
    @State private var asksFirst: Bool
    @State private var code: String
    @State private var codeError: String?

    enum ValueMode: String, CaseIterable, Identifiable {
        case ask = "Ask"
        case fixed = "Fixed"
        case identity = "Identity"
        var id: String { rawValue }
    }

    /// The moves a script can perform.
    static let editableKinds: [AgentActionKind] = [.tapElement, .typeInto, .selectOption, .navigate, .scroll, .back, .wait]

    init(move: RecipeMove, onSave: @escaping (RecipeMove) -> Void) {
        original = move
        self.onSave = onSave
        _note = State(initialValue: move.note ?? "")
        _action = State(initialValue: Self.editableKinds.contains(move.kind) ? move.kind : .tapElement)
        _targetName = State(initialValue: move.target?.name ?? "")
        switch move.valueSource {
        case .fixed(let text)?:
            _valueMode = State(initialValue: .fixed)
            _fixedValue = State(initialValue: text)
            _identityKind = State(initialValue: .fullName)
        case .identity(let kind)?:
            _valueMode = State(initialValue: .identity)
            _fixedValue = State(initialValue: "")
            _identityKind = State(initialValue: kind)
        case .askAtLaunch?, nil:
            _valueMode = State(initialValue: .ask)
            _fixedValue = State(initialValue: "")
            _identityKind = State(initialValue: .fullName)
        }
        _submits = State(initialValue: move.submits ?? false)
        _urlString = State(initialValue: move.urlString ?? "")
        _direction = State(initialValue: move.direction ?? "down")
        _amount = State(initialValue: move.amount ?? 600)
        _asksFirst = State(initialValue: move.isCommitting)
        _code = State(initialValue: Self.encode(move))
    }

    private var targetsElement: Bool {
        action == .tapElement || action == .typeInto || action == .selectOption
    }

    private var takesValue: Bool {
        action == .typeInto || action == .selectOption
    }

    /// A control whose name reads as a commitment always asks first.
    private var mustAsk: Bool {
        targetsElement && OnDeviceGate.isIrreversible(targetName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(built.generatedLine, text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("In your words")
                } footer: {
                    Text("Shown in the script, and used as what this step is for when a site has moved the control and the step has to find it again. Leave empty for the app's own wording.")
                }

                Section {
                    Picker("Step", selection: $action) {
                        ForEach(Self.editableKinds, id: \.self) { kind in
                            Text(kind.label.capitalized).tag(kind)
                        }
                    }
                    if targetsElement {
                        TextField("Control name, as shown on the page", text: $targetName)
                    }
                    if action == .navigate {
                        TextField("https://…", text: $urlString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if action == .scroll {
                        Picker("Direction", selection: $direction) {
                            Text("Down").tag("down")
                            Text("Up").tag("up")
                        }
                        Stepper("Distance: \(Int(amount)) px", value: $amount, in: 200...1200, step: 100)
                    }
                    if action == .typeInto {
                        Toggle("Press Enter after typing", isOn: $submits)
                    }
                } header: {
                    Text("What it does")
                }

                if takesValue {
                    Section {
                        Picker("Value", selection: $valueMode) {
                            ForEach(ValueMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        switch valueMode {
                        case .ask:
                            Text("You'll be asked for it each time the script runs.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        case .fixed:
                            TextField("Always type this", text: $fixedValue)
                        case .identity:
                            Picker("Identity detail", selection: $identityKind) {
                                ForEach(DossierFieldKind.allCases) { kind in
                                    Text(kind.label).tag(kind)
                                }
                            }
                        }
                    } header: {
                        Text("Value")
                    } footer: {
                        Text("Identity fills this step from your saved details each time it runs. The script stores which detail to use, never the detail itself.")
                    }
                }

                Section {
                    Toggle("Ask me before this step", isOn: Binding(
                        get: { asksFirst || mustAsk },
                        set: { asksFirst = $0 }
                    ))
                    .disabled(mustAsk)
                } footer: {
                    Text(mustAsk
                         ? "This control reads like it buys, sends, submits or deletes, so the script always stops for your yes here."
                         : "The script stops here and waits for your yes, even in autopilot.")
                }

                Section {
                    TextEditor(text: $code)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 180)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let codeError {
                        Text(codeError)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.red)
                    }
                    HStack {
                        Button("Refresh from fields") {
                            code = Self.encode(built)
                            codeError = nil
                        }
                        Spacer()
                        Button("Apply code") { applyCode() }
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Code")
                } footer: {
                    Text("The step exactly as the replay runs it. Edit it and tap Apply code to load it into the fields above.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Edit Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave(built)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.cyan)
                    .disabled(!isValid)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var isValid: Bool {
        if targetsElement, targetName.trimmed.isEmpty { return false }
        if action == .navigate, URL(string: urlString.trimmed)?.host == nil { return false }
        if takesValue, valueMode == .fixed, fixedValue.trimmed.isEmpty { return false }
        return true
    }

    /// The step as the fields describe it now.
    private var built: RecipeMove {
        var move = original
        let changedWhat = action != original.kind || targetName.trimmed != (original.target?.name ?? "")
        move.action = action.rawValue

        if targetsElement {
            let name = targetName.trimmed
            let kind: ScannedElement.Kind
            switch action {
            case .typeInto: kind = .field
            case .selectOption: kind = .dropdown
            default: kind = original.target?.kind ?? .button
            }
            move.target = ElementFingerprint(
                name: name,
                kind: kind,
                neighbourhood: name == original.target?.name ? (original.target?.neighbourhood ?? []) : [],
                approxX: original.target?.approxX ?? 0.5,
                approxY: original.target?.approxY ?? 0.5
            )
        } else {
            move.target = nil
        }

        if takesValue {
            switch valueMode {
            case .ask: move.valueSource = .askAtLaunch
            case .fixed: move.valueSource = .fixed(fixedValue)
            case .identity: move.valueSource = .identity(identityKind)
            }
            if move.valueKind == nil { move.valueKind = "what goes in “\(targetName.trimmed)”" }
        } else {
            move.valueSource = nil
        }
        move.submits = action == .typeInto ? submits : nil
        move.urlString = action == .navigate ? urlString.trimmed : nil
        move.direction = action == .scroll ? direction : nil
        move.amount = action == .scroll ? amount : nil
        move.isCommitting = asksFirst || mustAsk
        // A step that now does something else cannot be held to how the page
        // reacted to the old one.
        if changedWhat { move.expectedReaction = nil }
        let words = note.trimmed
        move.note = words.isEmpty ? nil : words
        return move
    }

    private func applyCode() {
        guard let data = code.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RecipeMove.self, from: data)
        else {
            codeError = "That isn't a valid step — check the brackets, quotes and commas."
            return
        }
        guard Self.editableKinds.contains(decoded.kind) else {
            codeError = "“\(decoded.action)” isn't a step a script can run. Use one of: \(Self.editableKinds.map(\.rawValue).joined(separator: ", "))."
            return
        }
        codeError = nil
        note = decoded.note ?? ""
        action = decoded.kind
        targetName = decoded.target?.name ?? ""
        switch decoded.valueSource {
        case .fixed(let text)?:
            valueMode = .fixed
            fixedValue = text
        case .identity(let kind)?:
            valueMode = .identity
            identityKind = kind
        case .askAtLaunch?, nil:
            valueMode = .ask
        }
        submits = decoded.submits ?? false
        urlString = decoded.urlString ?? ""
        direction = decoded.direction ?? "down"
        amount = decoded.amount ?? 600
        asksFirst = decoded.isCommitting
        Haptics.light()
    }

    static func encode(_ move: RecipeMove) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(move), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
