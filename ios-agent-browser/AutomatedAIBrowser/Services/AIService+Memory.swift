import Foundation

/// The cloud fallback for writing a memory.
///
/// Writing a recipe is free on any iPhone that can run Apple's on-device model.
/// This is the path for the phones that cannot: one small call, made only after a
/// confirmed success, that labels a route which has already been derived from
/// what actually happened. It never sees a value the user typed — only the shape
/// of the route — so the "typed values are never stored" guarantee holds on this
/// path too.
extension AIService {

    nonisolated struct LabelRequest: Sendable {
        let goal: String
        let host: String
        /// The route in plain language, derived mechanically from the run.
        let routeLines: [String]
        let modelID: String
    }

    nonisolated private static var labelRouteTool: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "label_route",
                description: "Label a browsing route that has just been proven to work, so it can be recognised the next time a similar goal comes up on the same site.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "intent": .string("The KIND of goal this route solves, 3-8 words, general rather than specific: 'find a product's price', not 'find the price of the red trainers'. Never include search terms, names, numbers or anything the person typed."),
                        "title": .string("A short name a person would recognise, 2-5 words."),
                        "traps": .stringArray("Up to two things that got in the way and had to be handled — a cookie banner, a misleading link, a filter that did nothing. Empty when the route was clean."),
                    ],
                    required: ["intent", "title"]
                )
            )
        )
    }

    nonisolated private struct LabelArguments: Decodable {
        let intent: String?
        let title: String?
        let traps: [String]?
    }

    /// Labels a proven route. Throws on any failure — the caller then falls back
    /// to a mechanical label, so a memory is still written either way.
    func label(_ request: LabelRequest) async throws -> RecipeDistiller.Label {
        let context = RecipeDistiller.prompt(
            goal: request.goal,
            host: request.host,
            routeLines: request.routeLines
        )

        let message = try await send(
            model: request.modelID,
            system: Self.labelPrompt,
            parts: [.text(context)],
            tools: [Self.labelRouteTool],
            maxTokens: 300,
            temperature: 0.2
        )

        guard let call = message.toolCalls?.first,
              let function = call.function,
              function.name.trimmed.lowercased() == "label_route",
              let data = (function.arguments?.trimmed.isEmpty == false ? function.arguments : "{}")?.data(using: .utf8),
              let args = try? JSONDecoder().decode(LabelArguments.self, from: data),
              let intent = args.intent?.trimmed, !intent.isEmpty,
              let title = args.title?.trimmed, !title.isEmpty
        else {
            throw AIError.unparseable
        }

        return RecipeDistiller.Label(
            intent: String(intent.prefix(90)),
            title: String(title.prefix(60)),
            traps: (args.traps ?? [])
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
                .prefix(2)
                .map { String($0.prefix(120)) }
        )
    }

    nonisolated private static let labelPrompt = """
    You label browsing routes so they can be recognised again. You are given a goal, a site, and the route that has just been proven to work on it.

    Call label_route exactly once.

    The intent you write is what the next match will be made against, so it has to describe the KIND of goal, not the specific one. "check a delivery date" is a good intent; "check when the blue chair arrives" is not — it would never match again.

    Never put a search term, a person's name, an address, an order number, or anything else the user typed into any field you return. The route was derived without those on purpose.
    """
}
