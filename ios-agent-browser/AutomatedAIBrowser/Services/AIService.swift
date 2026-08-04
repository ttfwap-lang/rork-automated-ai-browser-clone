import Foundation

/// Talks to the Rork AI proxy (Vercel AI Gateway, OpenAI-compatible chat completions)
/// and turns a page snapshot + goal into the agent's next action.
///
/// The agent's moves are exposed to the model as native custom tools (function
/// calling): the model must call exactly one tool per turn, and the gateway
/// returns structured `tool_calls` instead of free-form text. A legacy JSON-in-text
/// parser is kept as a fallback for models that reply with plain content.
nonisolated struct AIService {

    nonisolated struct DecisionRequest: Sendable {
        let goal: String
        let urlString: String
        let pageTitle: String
        let stepIndex: Int
        let maxSteps: Int
        let historyLines: [String]
        let extractedText: String?
        /// Written element map from the page scanner; nil when the scan failed.
        let pageMap: String?
        let imageBase64: String
        /// Stitched whole-page overview captured last step, if the AI asked for one.
        let overviewImageBase64: String?
        /// Coverage note for the overview, e.g. "covers the whole page (~4 screens)".
        let overviewNote: String?
        /// The mission checklist briefing; nil when planning is off.
        let planBriefing: String?
        /// The independent check's objection to the agent's last "done" claim.
        let objection: String?
        /// Free nudge when the same task has been current for several steps.
        let nudge: String?
        /// What the app thinks of this moment; only set on hard steps.
        let difficultyNote: String?
        /// The checkpoint strip, when checkpoints are on.
        let bookmarksNote: String?
        /// The runner-up move from the last hard step, when the winner flopped.
        let runnerUpNote: String?
        /// What has already been tried from the point just rewound to.
        let deadEndNote: String?
        /// The one push-back after a premature give-up.
        let rescueNote: String?
        /// A proven route recalled from this site's memory, folded in silently.
        let memoryNote: String?
        /// What has gone wrong on this site before, folded in silently.
        let cautionNote: String?
        /// True when the agent may answer with a shortlist instead of one move.
        let allowShortlist: Bool
        /// True when there is at least one checkpoint to rewind to.
        let hasBookmarks: Bool
        let modelID: String

        var hasPlan: Bool { !(planBriefing ?? "").isEmpty }
    }

    nonisolated enum AIError: LocalizedError {
        case notConfigured
        case auth
        case balance
        case rateLimited
        case server(Int)
        case emptyResponse
        case unparseable

        var errorDescription: String? {
            switch self {
            case .notConfigured: "AI isn't configured for this build yet. Please reopen the app from Rork."
            case .auth: "AI access was rejected. Please restart the app."
            case .balance: "AI credits are unavailable right now. Please try again later."
            case .rateLimited: "Too many requests — give it a few seconds and run again."
            case .server(let code): "The AI service had a problem (\(code)). Please try again."
            case .emptyResponse: "The AI returned an empty reply. Please try again."
            case .unparseable: "The AI reply couldn't be understood. Please try again."
            }
        }
    }

    // MARK: - Request DTOs

    nonisolated struct ChatContentPart: Encodable {
        struct ImageURL: Encodable {
            let url: String
        }

        let type: String
        let text: String?
        let imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }

        static func text(_ value: String) -> ChatContentPart {
            ChatContentPart(type: "text", text: value, imageURL: nil)
        }

        static func imageJPEG(base64: String) -> ChatContentPart {
            ChatContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: "data:image/jpeg;base64,\(base64)"))
        }
    }

    nonisolated enum ChatMessageContent: Encodable {
        case string(String)
        case parts([ChatContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .parts(let value): try container.encode(value)
            }
        }
    }

    nonisolated struct ChatMessage: Encodable {
        let role: String
        let content: ChatMessageContent
    }

    nonisolated struct ChatRequestBody: Encodable {
        let model: String
        let messages: [ChatMessage]
        let maxTokens: Int
        let temperature: Double
        let tools: [ToolDefinition]
        let toolChoice: String

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature, tools
            case maxTokens = "max_tokens"
            case toolChoice = "tool_choice"
        }
    }

    // MARK: - Custom tool schema DTOs

    nonisolated struct ItemsSchema: Encodable {
        let type: String
        let properties: [String: SchemaProperty]?
        let required: [String]?
    }

    nonisolated struct SchemaProperty: Encodable {
        let type: String
        let description: String?
        let enumValues: [String]?
        let minimum: Int?
        let maximum: Int?
        let items: ItemsSchema?

        enum CodingKeys: String, CodingKey {
            case type, description, minimum, maximum, items
            case enumValues = "enum"
        }

        static func string(_ description: String) -> SchemaProperty {
            SchemaProperty(type: "string", description: description, enumValues: nil, minimum: nil, maximum: nil, items: nil)
        }

        static func integer(_ description: String, min: Int? = nil, max: Int? = nil) -> SchemaProperty {
            SchemaProperty(type: "integer", description: description, enumValues: nil, minimum: min, maximum: max, items: nil)
        }

        static func boolean(_ description: String) -> SchemaProperty {
            SchemaProperty(type: "boolean", description: description, enumValues: nil, minimum: nil, maximum: nil, items: nil)
        }

        static func stringEnum(_ description: String, values: [String]) -> SchemaProperty {
            SchemaProperty(type: "string", description: description, enumValues: values, minimum: nil, maximum: nil, items: nil)
        }

        static func objectArray(_ description: String, itemProperties: [String: SchemaProperty], required: [String]) -> SchemaProperty {
            SchemaProperty(
                type: "array",
                description: description,
                enumValues: nil,
                minimum: nil,
                maximum: nil,
                items: ItemsSchema(type: "object", properties: itemProperties, required: required)
            )
        }

        static func integerArray(_ description: String) -> SchemaProperty {
            SchemaProperty(
                type: "array",
                description: description,
                enumValues: nil,
                minimum: nil,
                maximum: nil,
                items: ItemsSchema(type: "integer", properties: nil, required: nil)
            )
        }

        static func stringArray(_ description: String) -> SchemaProperty {
            SchemaProperty(
                type: "array",
                description: description,
                enumValues: nil,
                minimum: nil,
                maximum: nil,
                items: ItemsSchema(type: "string", properties: nil, required: nil)
            )
        }
    }

    nonisolated struct ToolParameters: Encodable {
        let type: String
        let properties: [String: SchemaProperty]
        let required: [String]
    }

    nonisolated struct ToolFunction: Encodable {
        let name: String
        let description: String
        let parameters: ToolParameters
    }

    nonisolated struct ToolDefinition: Encodable {
        let type: String
        let function: ToolFunction
    }

    // MARK: - The agent's custom tools

    nonisolated static func tool(
        _ name: String,
        _ description: String,
        properties: [String: SchemaProperty] = [:],
        required: [String] = []
    ) -> ToolDefinition {
        var props = properties
        props["reasoning"] = .string("One or two short sentences explaining why this is the right next move.")
        props["task"] = .integer("When a MISSION PLAN is present: the plan task number this move serves.", min: 1, max: 99)
        props["completed_tasks"] = .integerArray("When a MISSION PLAN is present: task numbers you can SEE are finished on this screen. Evidence only \u{2014} never intent.")
        return ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: name,
                description: description,
                parameters: ToolParameters(type: "object", properties: props, required: ["reasoning"] + required)
            )
        )
    }

    /// One custom tool per browser move. The model must call exactly one per turn.
    nonisolated private static let agentTools: [ToolDefinition] = [
        tool(
            "tap_element",
            "Tap a numbered element from the ELEMENTS list. The number matches the badge drawn on the screenshot. This is the preferred, most reliable way to press anything.",
            properties: [
                "element": .integer("The element number from the ELEMENTS list / screenshot badge.", min: 1, max: 999),
            ],
            required: ["element"]
        ),
        tool(
            "type_into",
            "Type into a numbered field in ONE move — it focuses the field itself, no separate tap needed. Replaces the field's current text.",
            properties: [
                "element": .integer("The field's element number from the ELEMENTS list / screenshot badge.", min: 1, max: 999),
                "text": .string("The text to enter."),
                "submit": .boolean("Press Enter afterwards (submits searches and forms)."),
            ],
            required: ["element", "text"]
        ),
        tool(
            "fill_form",
            "Fill SEVERAL fields in one move: a list of {element, text} pairs typed in order with the same reliable typing as type_into, optionally submitting at the end. Always prefer this over multiple type_into steps when a form has 2+ fields.",
            properties: [
                "fields": .objectArray(
                    "The fields to fill, in order.",
                    itemProperties: [
                        "element": .integer("The field's element number from the ELEMENTS list.", min: 1, max: 999),
                        "text": .string("The text to enter into that field."),
                    ],
                    required: ["element", "text"]
                ),
                "submit": .boolean("Press Enter on the last field afterwards (submits the form)."),
            ],
            required: ["fields"]
        ),
        tool(
            "select_option",
            "Choose an option from a dropdown (kind: dropdown). Real menus are set directly with the option's visible text; custom dropdowns are opened so their options appear as numbered elements on the next look.",
            properties: [
                "element": .integer("The dropdown's element number.", min: 1, max: 999),
                "option": .string("The visible text of the option to choose."),
            ],
            required: ["element", "option"]
        ),
        tool(
            "set_toggle",
            "Turn a toggle/checkbox (kind: toggle) ON or OFF. It checks the current state first and only presses when needed — it can never accidentally un-tick something.",
            properties: [
                "element": .integer("The toggle's element number.", min: 1, max: 999),
                "on": .boolean("true = ON/checked, false = OFF/unchecked."),
            ],
            required: ["element", "on"]
        ),
        tool(
            "set_slider",
            "Set a slider to a position given as percent 0-100 of its range. Standard sliders are set directly; custom ones are nudged step by step toward the target.",
            properties: [
                "element": .integer("The slider's element number.", min: 1, max: 999),
                "value": .integer("Target position as percent of the slider's range, 0-100.", min: 0, max: 100),
            ],
            required: ["element", "value"]
        ),
        tool(
            "drag",
            "Drag from one numbered element to another (reorder lists, move cards, drag handles). Give from/to element numbers, or from_x/from_y/to_x/to_y coordinates (0-1000) as a fallback. The result ends with a reaction verdict — read it.",
            properties: [
                "from": .integer("Source element number.", min: 1, max: 999),
                "to": .integer("Target element number.", min: 1, max: 999),
                "from_x": .integer("Fallback source x, 0-1000.", min: 0, max: 1000),
                "from_y": .integer("Fallback source y, 0-1000.", min: 0, max: 1000),
                "to_x": .integer("Fallback target x, 0-1000.", min: 0, max: 1000),
                "to_y": .integer("Fallback target y, 0-1000.", min: 0, max: 1000),
            ]
        ),
        tool(
            "long_press",
            "Press and hold a numbered element (~0.65s) to trigger hold-actions the site itself defines. It cannot open the phone's own system menus.",
            properties: [
                "element": .integer("The element number to hold.", min: 1, max: 999),
            ],
            required: ["element"]
        ),
        tool(
            "hover",
            "Hover the pointer over a numbered element to wake hover menus on desktop-style sites. New elements that appear will be numbered on the next look.",
            properties: [
                "element": .integer("The element number to hover over.", min: 1, max: 999),
            ],
            required: ["element"]
        ),
        tool(
            "swipe",
            "Swipe a carousel or swipeable strip left or right. Prefers sliding the strip itself (reliable, movement is measured); falls back to a synthetic finger swipe.",
            properties: [
                "direction": .stringEnum("Swipe direction: 'left' reveals content on the right.", values: ["left", "right"]),
                "element": .integer("An element number inside the carousel/strip (optional — defaults to the screen center).", min: 1, max: 999),
            ],
            required: ["direction"]
        ),
        tool(
            "tap",
            "LAST RESORT: tap at raw screenshot coordinates (integers 0-1000, (0,0) top-left). Use ONLY when the target has no numbered badge — maps, canvases, unscannable embedded panels.",
            properties: [
                "x": .integer("Horizontal position, 0-1000.", min: 0, max: 1000),
                "y": .integer("Vertical position, 0-1000.", min: 0, max: 1000),
            ],
            required: ["x", "y"]
        ),
        tool(
            "type_text",
            "Type text into the currently focused input field. Prefer type_into with an element number instead.",
            properties: [
                "text": .string("The text to type."),
                "submit": .boolean("Press Enter after typing (submits searches and forms)."),
            ],
            required: ["text"]
        ),
        tool(
            "scroll",
            "Scroll the page vertically to reveal more content.",
            properties: [
                "direction": .stringEnum("Which way to scroll.", values: ["up", "down"]),
                "amount": .integer("Distance in pixels, 200-1200. Defaults to 600.", min: 200, max: 1200),
            ],
            required: ["direction"]
        ),
        tool(
            "navigate",
            "Go directly to a URL. Prefer this when you know the destination — e.g. https://duckduckgo.com/?q=your+query for searches.",
            properties: [
                "url": .string("Full URL including https://."),
            ],
            required: ["url"]
        ),
        tool("back", "Go back to the previous page in browser history."),
        tool("extract", "Read a CLEANED copy of the ENTIRE page (menus stripped, headings marked with #, lists as bullets) — provided to you on the next turn. Prefer this over scroll-hunting for informational goals."),
        tool("page_overview", "See the WHOLE page at once: captures up to 6 screens and attaches one tall stitched picture to your NEXT decision. Orientation only — it has NO badges; keep acting via the numbered elements. Use sparingly: when lost, or when the goal spans the full page."),
        tool("wait", "Wait 2 seconds for the page to finish loading. Use when the screenshot looks blank or mid-load."),
        tool(
            "done",
            "Finish the run: the goal is achieved. The summary states the outcome or the answer found on the page.",
            properties: [
                "summary": .string("What was accomplished, or the answer to the user's question."),
            ],
            required: ["summary"]
        ),
        tool(
            "fail",
            "Give up: the goal is impossible (bot walls, CAPTCHAs, login required, missing content).",
            properties: [
                "reason": .string("Why the goal can't be completed."),
            ],
            required: ["reason"]
        ),
    ]

    /// The plan-rewrite move — offered only when a mission plan exists.
    nonisolated private static let revisePlanTool = tool(
        "revise_plan",
        "Rewrite the REMAINING tasks of the mission plan when reality disagrees with it: a task turned out impossible, the site is built differently than the plan assumed, or you found a faster route. Finished tasks stay finished. This consumes your turn instead of a page action, and is capped at 2 rewrites per mission.",
        properties: [
            "tasks": .objectArray(
                "The new remaining tasks, in the order you will do them.",
                itemProperties: [
                    "title": .string("Short imperative task title, e.g. 'Filter results to May dates'."),
                    "done_when": .string("A plain, observable test that proves this task is finished, e.g. 'only May dates appear in the list'."),
                    "hint": .string("Optional route hint, e.g. 'use the site's own filter panel'."),
                ],
                required: ["title", "done_when"]
            ),
            "reason": .string("Why the old plan no longer fits — what you learned from the page."),
        ],
        required: ["tasks", "reason"]
    )

    /// Go back to a captured checkpoint — offered only when one exists.
    nonisolated private static let rewindTool = tool(
        "rewind",
        "Go back to a numbered CHECKPOINT from earlier in the mission and take a different branch. Use it when a route is exhausted: the promising link led nowhere, the filter didn't exist, the panel resisted every gesture. It consumes your turn instead of a page action, is capped at 3 per mission, and restores the PAGE only — not text you already typed into a form, so it is the wrong tool for a half-filled form.",
        properties: [
            "bookmark": .integer("The checkpoint number from the CHECKPOINTS list.", min: 1, max: 99),
            "reason": .string("Why this route is dead and what you will try instead from there."),
        ],
        required: ["bookmark", "reason"]
    )

    /// Draft several moves at once — offered only on hard steps.
    nonisolated private static let weighOptionsTool = ToolDefinition(
        type: "function",
        function: ToolFunction(
            name: "weigh_options",
            description: "THIS MOMENT IS HARD: instead of committing to one move, draft 2 to 4 possible moves with your own confidence in each. The app scores them against the live page (does the element still exist, is it disabled, has this exact move already failed, does it serve the current task) and plays the best one, keeping the runner-up for the next step. Each option is a single-target move — for multi-field form fills call fill_form directly instead.",
            parameters: ToolParameters(
                type: "object",
                properties: [
                    "reasoning": .string("One or two sentences on what makes this step uncertain."),
                    "task": .integer("When a MISSION PLAN is present: the plan task number these options serve.", min: 1, max: 99),
                    "completed_tasks": .integerArray("When a MISSION PLAN is present: task numbers you can SEE are finished on this screen."),
                    "candidates": .objectArray(
                        "The moves you are weighing, best first. 2 to 4 of them.",
                        itemProperties: [
                            "move": .stringEnum(
                                "Which move this option is.",
                                values: ["tap_element", "type_into", "select_option", "set_toggle", "set_slider", "long_press", "hover", "swipe", "scroll", "navigate", "back", "extract", "page_overview", "tap", "wait"]
                            ),
                            "element": .integer("Target element number, for element-targeted moves.", min: 1, max: 999),
                            "text": .string("Text to type, for type_into."),
                            "submit": .boolean("Press Enter afterwards, for type_into."),
                            "option": .string("Option text, for select_option."),
                            "on": .boolean("Desired state, for set_toggle."),
                            "value": .integer("Target percent 0-100, for set_slider.", min: 0, max: 100),
                            "direction": .stringEnum("Direction, for scroll and swipe.", values: ["up", "down", "left", "right"]),
                            "amount": .integer("Scroll distance in pixels.", min: 200, max: 1200),
                            "url": .string("Full URL, for navigate."),
                            "x": .integer("Coordinate x 0-1000, for the last-resort tap.", min: 0, max: 1000),
                            "y": .integer("Coordinate y 0-1000, for the last-resort tap.", min: 0, max: 1000),
                            "rationale": .string("One line: why this option might be the right move."),
                            "confidence": .integer("How confident you are in this option, 0-100.", min: 0, max: 100),
                        ],
                        required: ["move", "rationale", "confidence"]
                    ),
                ],
                required: ["candidates", "reasoning"]
            )
        )
    )

    /// The tool set for one decision turn.
    nonisolated static func tools(hasPlan: Bool, hasBookmarks: Bool = false, allowShortlist: Bool = false) -> [ToolDefinition] {
        var set = agentTools
        if hasPlan { set.append(revisePlanTool) }
        if hasBookmarks { set.append(rewindTool) }
        if allowShortlist { set.append(weighOptionsTool) }
        return set
    }

    // MARK: - Response DTOs

    nonisolated struct ChatResponse: Decodable {
        struct ToolCallFunction: Decodable {
            let name: String
            let arguments: String?
        }

        struct ToolCall: Decodable {
            let function: ToolCallFunction?
        }

        struct Message: Decodable {
            let content: String?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                content = try? container.decodeIfPresent(String.self, forKey: .content)
                toolCalls = try? container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
            }
        }

        struct Choice: Decodable {
            let message: Message
        }

        let choices: [Choice]
    }

    /// Arguments payload of a tool call — mirrors `AgentAction`'s optional fields.
    nonisolated private struct ToolArguments: Decodable {
        struct Field: Decodable {
            let element: Int?
            let text: String?
        }

        let reasoning: String?
        let element: Int?
        let x: Double?
        let y: Double?
        let text: String?
        let submit: Bool?
        let direction: String?
        let amount: Double?
        let url: String?
        let summary: String?
        let reason: String?
        let option: String?
        let on: Bool?
        let value: Double?
        let fields: [Field]?
        let from: Int?
        let to: Int?
        let fromX: Double?
        let fromY: Double?
        let toX: Double?
        let toY: Double?
        let task: Int?
        let completedTasks: [Int]?
        let tasks: [PlannedTask]?
        let bookmark: Int?

        enum CodingKeys: String, CodingKey {
            case reasoning, element, x, y, text, submit, direction, amount, url, summary, reason, option, on, value, fields, from, to, task, tasks, bookmark
            case fromX = "from_x"
            case fromY = "from_y"
            case toX = "to_x"
            case toY = "to_y"
            case completedTasks = "completed_tasks"
        }
    }

    // MARK: - Public API

    /// Asks the model for the next turn via native tool calling; retries once
    /// if the reply contains neither a valid tool call nor parseable JSON.
    func decide(_ request: DecisionRequest) async throws -> AgentTurn {
        for attempt in 1...2 {
            let message = try await complete(request, strict: attempt > 1)
            if let call = message.toolCalls?.first,
               let function = call.function,
               let turn = Self.turn(fromToolNamed: function.name, argumentsJSON: function.arguments ?? "") {
                return turn
            }
            if let content = message.content,
               let decision = Self.parseDecision(from: content) {
                return .move(decision)
            }
            try Task.checkCancellation()
        }
        throw AIError.unparseable
    }

    // MARK: - Networking

    private func complete(_ request: DecisionRequest, strict: Bool) async throws -> ChatResponse.Message {
        var system = Self.systemPrompt
        if strict {
            system += "\n\nIMPORTANT: Your previous reply did not include a valid tool call. You MUST respond by calling exactly ONE of the provided tools — no prose."
        }

        var parts: [ChatContentPart] = [
            .text(Self.contextText(for: request)),
            .imageJPEG(base64: request.imageBase64),
        ]
        if let overview = request.overviewImageBase64, !overview.isEmpty {
            parts.append(.text("SECOND IMAGE — the whole-page overview you requested (\(request.overviewNote ?? "stitched screens")). It has NO badges: use it for orientation only, never to pick tap targets."))
            parts.append(.imageJPEG(base64: overview))
        }

        return try await send(
            model: request.modelID,
            system: system,
            parts: parts,
            tools: Self.tools(
                hasPlan: request.hasPlan,
                hasBookmarks: request.hasBookmarks,
                allowShortlist: request.allowShortlist
            )
        )
    }

    /// Shared transport for every AI call the app makes — step decisions, mission
    /// planning, and the independent check. One chat completion with required
    /// tool calling, one place for error mapping.
    func send(
        model: String,
        system: String,
        parts: [ChatContentPart],
        tools: [ToolDefinition],
        maxTokens: Int = 1000,
        temperature: Double = 0.2
    ) async throws -> ChatResponse.Message {
        var base = Config.EXPO_PUBLIC_TOOLKIT_URL
        let key = Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY
        guard !base.isEmpty, !key.isEmpty else { throw AIError.notConfigured }
        if !base.lowercased().hasPrefix("http") { base = "https://" + base }
        if base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/v2/vercel/v1/chat/completions") else { throw AIError.notConfigured }

        let body = ChatRequestBody(
            model: model,
            messages: [
                ChatMessage(role: "system", content: .string(system)),
                ChatMessage(role: "user", content: .parts(parts)),
            ],
            maxTokens: maxTokens,
            temperature: temperature,
            tools: tools,
            toolChoice: "required"
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: break
        case 401, 403: throw AIError.auth
        case 402: throw AIError.balance
        case 408, 429: throw AIError.rateLimited
        default: throw AIError.server(status)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let message = decoded.choices.first?.message else {
            throw AIError.emptyResponse
        }
        let hasToolCall = !(message.toolCalls ?? []).isEmpty
        let hasContent = !(message.content ?? "").isEmpty
        guard hasToolCall || hasContent else {
            throw AIError.emptyResponse
        }
        return message
    }

    // MARK: - Parsing

    /// Maps a native tool call to one turn: either a single committed move, or
    /// the shortlist of candidates the app will score against the live page.
    nonisolated static func turn(fromToolNamed name: String, argumentsJSON: String) -> AgentTurn? {
        let normalized = name.trimmed.lowercased()
        if normalized == "weigh_options" {
            guard let shortlist = shortlist(fromArgumentsJSON: argumentsJSON) else { return nil }
            return .shortlist(reasoning: shortlist.reasoning, candidates: shortlist.candidates)
        }
        guard let decision = decision(fromToolNamed: normalized, argumentsJSON: argumentsJSON) else { return nil }
        return .move(decision)
    }

    nonisolated private struct ShortlistArguments: Decodable {
        struct Draft: Decodable {
            let move: String?
            let element: Int?
            let text: String?
            let submit: Bool?
            let option: String?
            let on: Bool?
            let value: Double?
            let direction: String?
            let amount: Double?
            let url: String?
            let x: Double?
            let y: Double?
            let rationale: String?
            let confidence: Double?
        }

        let reasoning: String?
        let task: Int?
        let completedTasks: [Int]?
        let candidates: [Draft]?

        enum CodingKeys: String, CodingKey {
            case reasoning, task, candidates
            case completedTasks = "completed_tasks"
        }
    }

    /// Parses a `weigh_options` call into unscored candidates. Returns nil when
    /// nothing usable came back, so the caller can retry.
    nonisolated static func shortlist(fromArgumentsJSON json: String) -> (reasoning: String?, candidates: [MoveCandidate])? {
        let payload = json.trimmed
        let data = Data((payload.isEmpty ? "{}" : payload).utf8)
        guard let args = try? JSONDecoder().decode(ShortlistArguments.self, from: data) else { return nil }

        let drafted: [MoveCandidate] = (args.candidates ?? []).compactMap { draft in
            guard let raw = draft.move?.trimmed.lowercased(),
                  let kind = AgentActionKind(rawValue: raw),
                  kind.isModelCallable,
                  kind.isPageAction
            else { return nil }

            var action = AgentAction(type: kind.rawValue)
            action.element = draft.element
            action.text = draft.text
            action.submit = draft.submit
            action.option = draft.option
            action.on = draft.on
            action.value = draft.value
            action.direction = draft.direction
            action.amount = draft.amount
            action.url = draft.url
            action.x = draft.x
            action.y = draft.y
            action.task = args.task
            action.completedTasks = args.completedTasks

            let reported = draft.confidence ?? 50
            let confidence = reported <= 1 ? reported : reported / 100
            return MoveCandidate(
                action: action,
                rationale: draft.rationale?.trimmed ?? "",
                confidence: min(max(confidence, 0), 1)
            )
        }

        guard !drafted.isEmpty else { return nil }
        return (args.reasoning, Array(drafted.prefix(4)))
    }

    /// Maps a native tool call (function name + JSON arguments) to an `AgentDecision`.
    nonisolated static func decision(fromToolNamed name: String, argumentsJSON: String) -> AgentDecision? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let kind = AgentActionKind(rawValue: normalized), kind.isModelCallable else { return nil }

        let payload = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonData = Data((payload.isEmpty ? "{}" : payload).utf8)
        guard let args = try? JSONDecoder().decode(ToolArguments.self, from: jsonData) else { return nil }

        let formFields: [AgentAction.FormField]? = args.fields.map { list in
            list.compactMap { field in
                guard let element = field.element, let text = field.text else { return nil }
                return AgentAction.FormField(element: element, text: text)
            }
        }

        var action = AgentAction(
            type: kind.rawValue,
            element: args.element,
            x: args.x,
            y: args.y,
            text: args.text,
            submit: args.submit,
            direction: args.direction,
            amount: args.amount,
            url: args.url,
            summary: args.summary,
            reason: args.reason
        )
        action.option = args.option
        action.on = args.on
        action.value = args.value
        action.fields = formFields
        action.from = args.from
        action.to = args.to
        action.fromX = args.fromX
        action.fromY = args.fromY
        action.toX = args.toX
        action.toY = args.toY
        action.task = args.task
        action.completedTasks = args.completedTasks
        action.tasks = args.tasks?.filter { !$0.title.trimmed.isEmpty }
        action.bookmark = args.bookmark
        return AgentDecision(reasoning: args.reasoning, action: action)
    }

    /// Legacy fallback: extracts a `{"reasoning":…,"action":…}` JSON object from
    /// plain text content, for models that answer in text instead of a tool call.
    nonisolated static func parseDecision(from raw: String) -> AgentDecision? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end else {
            return nil
        }
        let jsonSlice = String(trimmed[start...end])
        guard let data = jsonSlice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AgentDecision.self, from: data)
    }

    // MARK: - Prompting

    nonisolated private static func contextText(for request: DecisionRequest) -> String {
        var lines: [String] = []
        lines.append("GOAL: \(request.goal)")
        lines.append("")
        if let objection = request.objection, !objection.isEmpty {
            lines.append("THE INDEPENDENT CHECK REJECTED YOUR LAST \"done\" CLAIM. Its objection, in its words:")
            lines.append("\"\(objection)\"")
            lines.append("Fix exactly this before claiming success again. Do not call done until the objection is answered by what is visible on the page.")
            lines.append("")
        }
        if let rescue = request.rescueNote, !rescue.isEmpty {
            lines.append(rescue)
            lines.append("")
        }
        if let briefing = request.planBriefing, !briefing.isEmpty {
            lines.append(briefing)
            lines.append("")
        }
        if let memory = request.memoryNote, !memory.isEmpty {
            lines.append(memory)
            lines.append("")
        }
        if let cautions = request.cautionNote, !cautions.isEmpty {
            lines.append(cautions)
            lines.append("")
        }
        if let bookmarks = request.bookmarksNote, !bookmarks.isEmpty {
            lines.append(bookmarks)
            lines.append("")
        }
        if let deadEnds = request.deadEndNote, !deadEnds.isEmpty {
            lines.append(deadEnds)
            lines.append("")
        }
        lines.append("CURRENT URL: \(request.urlString.isEmpty ? "about:blank" : request.urlString)")
        if !request.pageTitle.isEmpty {
            lines.append("PAGE TITLE: \(request.pageTitle)")
        }
        lines.append("STEP \(request.stepIndex) of \(request.maxSteps)")
        lines.append("")
        lines.append("PREVIOUS STEPS:")
        if request.historyLines.isEmpty {
            lines.append("(none — this is the first step)")
        } else {
            lines.append(contentsOf: request.historyLines)
        }
        if let nudge = request.nudge, !nudge.isEmpty {
            lines.append(nudge)
        }
        if let runnerUp = request.runnerUpNote, !runnerUp.isEmpty {
            lines.append(runnerUp)
        }
        if let difficulty = request.difficultyNote, !difficulty.isEmpty {
            lines.append(difficulty)
        }
        if request.allowShortlist {
            lines.append("BECAUSE THIS STEP IS HARD you may answer with weigh_options instead of a single move: 2-4 candidate moves with a rationale and confidence each. The app scores them against this page and plays the best one. Use it when you are genuinely unsure which route is right; commit to a single move when you are not.")
        }
        if let extracted = request.extractedText, !extracted.isEmpty {
            lines.append("")
            lines.append("CLEANED PAGE READING FROM LAST STEP (whole page, headings marked #, lists as •):")
            lines.append(extracted)
        }
        lines.append("")
        if let map = request.pageMap, !map.isEmpty {
            lines.append(map)
            lines.append("")
            if request.overviewImageBase64 != nil {
                lines.append("TWO images are attached: (1) the current badged screenshot — ground truth for acting; (2) the whole-page overview you requested — orientation only, NO badges, never pick targets from it.")
            }
            lines.append("The attached image is the current screenshot; interactive elements wear small numbered badges matching the ELEMENTS list above. Decide the single next action and call the matching tool — prefer element-targeted moves with those numbers.")
        } else {
            lines.append("PAGE SCAN UNAVAILABLE THIS STEP — no numbered badges on the screenshot and no ELEMENTS list. If you must tap, use the coordinate \"tap\" tool.")
            lines.append("")
            lines.append("The attached image is the current screenshot of the browser viewport (a mobile browser). Decide the single next action and call the matching tool.")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated private static let systemPrompt = """
    You are Pilot, an AI agent that controls a mobile web browser to accomplish the user's goal. Each turn you receive a screenshot of the current viewport, a numbered map of the interactive elements on screen (ELEMENTS), and context. Respond by calling exactly ONE of the provided tools — the tool call IS your action for this turn.

    ELEMENTS: every interactive element wears a small numbered badge on the screenshot, and the ELEMENTS list describes each one — e.g. [14] button "Add to cart", [7] field "Email" (empty, required). The numbers are ground truth. Badge colors: cyan = button, blue = link, amber = field, pink = toggle, green = dropdown, gray = other. Elements marked (in embedded panel: …) live inside embedded widgets (players, maps, payment boxes) — all element-targeted moves work on them normally.

    YOUR HANDS (prefer the most specific tool for the job):
    - tap_element / type_into: the reliable basics.
    - fill_form: several fields in ONE move — always prefer it when a form has 2+ fields.
    - select_option for dropdowns; set_toggle (state-aware ON/OFF) for toggles/checkboxes; set_slider (percent 0-100) for sliders.
    - drag / long_press / hover / swipe: synthetic gestures. Every gesture result ends with a reaction verdict — "page reacted (…)" or "no visible reaction". If nothing reacted, do NOT repeat the same gesture; try another route (arrows, buttons, direct URL) or report honestly. long_press only triggers what the site itself defines. hover wakes desktop hover menus; anything new gets numbered next turn.
    - Coordinate "tap" is the LAST RESORT for badge-free surfaces (maps, canvases, unscannable panels).

    YOUR SIGHT:
    - extract: a cleaned reading of the ENTIRE page (menus stripped, headings marked #, lists as •). Prefer it over scroll-hunting for informational goals.
    - page_overview: one tall stitched picture of up to 6 screens, attached to your NEXT turn. Orientation only — NO badges on it; never pick targets from it. Use sparingly: when lost, or when the goal spans the whole page.

    THE MISSION PLAN (present when a MISSION PLAN block appears in your context):
    - A short checklist was written before your first move: numbered tasks, each with a plain "done when" test, plus one SUCCESS MEANS statement for the whole mission.
    - Work the plan instead of re-deriving the mission every turn. With every tool call report "task" (the task number your move serves) and "completed_tasks" (task numbers you can SEE are finished on THIS screen — evidence, never intent or hope).
    - The plan is a map, not a cage: you may reorder, shortcut or skip. Tasks you step over are recorded as skipped, never as done.
    - revise_plan rewrites the REMAINING tasks when reality disagrees with the plan — a task is impossible, the site is built differently, or you found a faster route. It consumes your turn and is capped at 2 rewrites.

    JUDGMENT UNDER UNCERTAINTY:
    - On hard moments the weigh_options tool appears: draft 2-4 possible moves with your own confidence instead of committing blind. The app checks each one against the live page (does the element exist, is it disabled, has it already failed, does it serve the current task) and plays the best. Honest confidence numbers make this work; inflated ones waste the step.
    - When a CHECKPOINTS list appears you also have rewind: go back to a numbered checkpoint and take a different branch. Use it when a route is exhausted, not when a single tap missed. It restores the PAGE, not text you already typed — never rewind to escape a half-filled form, re-fill it instead.
    - When you land back at a checkpoint you are given what was already tried from there. Do not repeat any of it.

    THE INDEPENDENT CHECK:
    - When you call done, a SEPARATE reviewer looks at a fresh screenshot and the page text and decides whether the SUCCESS MEANS statement is visibly true. It never sees your reasoning, so confident wording cannot help you.
    - If it rejects your claim you are sent back to work with its objection. So only call done when the evidence is actually on the page, and put the real answer — read from the page, never invented — in the summary.

    RULES:
    1. Call exactly one tool per turn, always with a short "reasoning" (one or two sentences).
    2. Prefer "navigate" with a direct URL when you know the destination — e.g. https://duckduckgo.com/?q=your+query for searches.
    3. Respect element states: never press one marked (disabled); don't set_toggle to a state it's already in; fill (empty, required) fields before submitting a form.
    4. The VIEW line says where you are on the page and how many elements sit above/below the visible area — scroll only when what you need is off-screen.
    5. If a cookie/consent banner or overlay blocks the page (see the NOTE line), dismiss it first via its numbered button.
    6. If the screenshot looks blank or mid-load, use "wait".
    7. Results are honest — read them and adapt. A "no visible reaction" verdict means that route failed; never repeat it more than once.
    8. If your recent actions repeat without progress, change strategy — another element, another route, another page.
    9. When the goal asks for information, use "extract" to read the page before "done", and put the answer in the "done" summary.
    10. Use "fail" only when the goal is truly impossible (bot walls, CAPTCHAs, login required).
    11. Never invent facts — read them from the page.
    12. Only use "fail" when the goal is truly out of reach. If checkpoints remain with routes you have not tried, going back and trying one is the right move, not giving up.
    """
}
