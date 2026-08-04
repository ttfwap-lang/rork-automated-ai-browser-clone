import Foundation

/// The one paid call a self-healing replay may make: choosing which of the
/// elements ACTUALLY on the page is the one a saved step meant.
///
/// It is deliberately a multiple-choice question rather than an open one. The
/// model never receives a page and a wish — it receives a shortlist the app built
/// from the live scan, and its answer is rejected unless it names one of those
/// exact numbers. A healer that can invent a target is a healer that eventually
/// presses "Delete account" because it was the nearest thing to "Delete filter".
extension AIService {

    nonisolated struct RepairRequest: Sendable {
        /// What the saved step was trying to do, in plain words.
        let intent: String
        /// The control the route remembers, and what kind of thing it was.
        let missingName: String
        let missingKind: String
        /// The only answers that will be accepted.
        let candidates: [StepHealer.Candidate]
        let urlString: String
        let pageTitle: String
        let modelID: String
    }

    nonisolated private static var pickReplacementTool: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "pick_replacement",
                description: "Choose which element on the CURRENT page is the one the saved step meant, or say that none of them is.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "element": .integer("The element number from the CANDIDATES list. It MUST be one of the numbers listed — never a number from anywhere else.", min: 1, max: 999),
                        "none": .boolean("true when none of the candidates is the control the saved step meant. Prefer this over a guess."),
                        "why": .string("One short sentence: why this candidate is the same control, or why none of them is."),
                    ],
                    required: ["why"]
                )
            )
        )
    }

    nonisolated private struct RepairArguments: Decodable {
        let element: Int?
        let none: Bool?
        let why: String?
    }

    nonisolated struct RepairChoice: Equatable, Sendable {
        let elementID: Int
        let why: String
    }

    /// Picks the replacement element, or returns nil when the model declines or
    /// answers with anything that is not on the shortlist.
    func repairTarget(_ request: RepairRequest) async throws -> RepairChoice? {
        guard !request.candidates.isEmpty else { return nil }

        let message = try await send(
            model: request.modelID,
            system: Self.repairPrompt,
            parts: [.text(Self.repairContext(for: request))],
            tools: [Self.pickReplacementTool],
            maxTokens: 300,
            temperature: 0.1
        )

        guard let call = message.toolCalls?.first,
              let function = call.function,
              function.name.trimmed.lowercased() == "pick_replacement",
              let raw = function.arguments,
              let data = (raw.trimmed.isEmpty ? "{}" : raw).data(using: .utf8),
              let args = try? JSONDecoder().decode(RepairArguments.self, from: data)
        else {
            return nil
        }

        if args.none == true { return nil }
        guard let chosen = args.element else { return nil }
        // The shortlist is the whole guardrail: an answer outside it is discarded
        // rather than trusted.
        guard request.candidates.contains(where: { $0.id == chosen }) else { return nil }

        let why = (args.why?.trimmed).flatMap { $0.isEmpty ? nil : $0 }
            ?? "the model matched it to the saved step"
        return RepairChoice(elementID: chosen, why: String(why.prefix(140)))
    }

    nonisolated private static func repairContext(for request: RepairRequest) -> String {
        var lines = [
            "WHAT THE SAVED STEP DOES: \(request.intent)",
            "THE CONTROL IT REMEMBERS: a \(request.missingKind) labelled “\(request.missingName)” — it is not on the page under that name any more.",
            "CURRENT URL: \(request.urlString.isEmpty ? "about:blank" : request.urlString)",
        ]
        if !request.pageTitle.isEmpty {
            lines.append("PAGE TITLE: \(request.pageTitle)")
        }
        lines.append("")
        lines.append("CANDIDATES — every \(request.missingKind) on the page right now that could be it. These numbers are the ONLY valid answers:")
        lines.append(contentsOf: request.candidates.map { candidate in
            "\(candidate.line) — closeness \(Int((candidate.closeness * 100).rounded()))%"
        })
        lines.append("")
        lines.append("Call pick_replacement once: either the number of the candidate that is the same control, or none = true.")
        return lines.joined(separator: "\n")
    }

    nonisolated private static let repairPrompt = """
    A saved automation is being replayed on a site that has changed. One of its steps points at a control that is no longer there under the name it remembers. Your only job is to decide which of the listed candidates is that same control — or that none of them is.

    Call pick_replacement exactly once.

    Rules:
    - You may ONLY answer with an element number from the CANDIDATES list. Any other number is discarded and the replay stops, so a number you made up helps nobody.
    - Same PURPOSE, not same wording. "Search" and "Find" are the same control; "Search" and "Search history" are not.
    - When the candidates are all plausible but none is clearly the same control, answer none = true. A wrong press inside somebody's saved automation is far worse than a replay that stops and says so.
    - Never choose a control that would submit, buy, send or delete unless the saved step itself was that kind of control.
    """
}
