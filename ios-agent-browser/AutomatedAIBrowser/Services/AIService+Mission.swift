import Foundation

/// The two mission-level AI calls that sit either side of the step loop: the
/// planner that writes the checklist before the first move, and the independent
/// check that has to confirm a claimed success before a run can be called
/// complete.
///
/// The check is deliberately starved of the agent's own reasoning — reviewers
/// that read an agent's self-justification agree with it far too often — so it
/// receives only the goal, the success statement, a fresh screenshot, the page
/// text, the claimed result, and a bare trail of moves and their outcomes.
extension AIService {

    // MARK: - Requests

    nonisolated struct PlanRequest: Sendable {
        let goal: String
        let urlString: String
        let pageTitle: String
        let modelID: String
        /// The free on-device restatement of the goal, when one was written.
        var refinement: GoalRefiner.Refinement? = nil
        /// A proven route recalled for this site, folded in silently.
        var memoryNote: String? = nil
        /// What has gone wrong on this site before, folded in silently.
        var cautionNote: String? = nil
    }

    nonisolated struct VerifyRequest: Sendable {
        let goal: String
        let successStatement: String
        let answerShape: String?
        let claimedResult: String
        /// Bare action trail — moves and outcomes only, never the agent's reasoning.
        let actionTrail: [String]
        let urlString: String
        let pageTitle: String
        let pageText: String
        let imageBase64: String
        let modelID: String
    }

    // MARK: - Tool schemas

    nonisolated private static var writePlanTool: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "write_plan",
                description: "Write the mission checklist for this goal: 3 to 7 tasks for a normal mission, 1 or 2 for a trivial one, in the order they should be done.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "tasks": .objectArray(
                            "The tasks, in order. 3-7 for a normal mission, 1-2 for a trivial one.",
                            itemProperties: [
                                "title": .string("Short imperative title, e.g. 'Search flights for those dates'."),
                                "done_when": .string("A plain, observable test that proves this task is finished, e.g. 'a results list with prices is on screen'. It must be checkable by looking at the screen."),
                                "hint": .string("Optional route hint, e.g. 'go straight to the site's search URL'."),
                            ],
                            required: ["title", "done_when"]
                        ),
                        "success_statement": .string("ONE sentence stating what must be visibly true for the whole mission to count as achieved. An independent reviewer will later be held to exactly this sentence, so make it concrete and checkable on screen."),
                        "answer_shape": .string("For question-style goals only: the shape of the expected answer — 'a price', 'a date', 'a name', 'a list of titles'."),
                    ],
                    required: ["tasks", "success_statement"]
                )
            )
        )
    }

    nonisolated private static var reportVerdictTool: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolFunction(
                name: "report_verdict",
                description: "Report your independent verdict on the agent's claim, based only on the evidence in front of you.",
                parameters: ToolParameters(
                    type: "object",
                    properties: [
                        "verdict": .stringEnum(
                            "confirmed = the screen or page text visibly proves the success statement. rejected = the evidence contradicts the claim, or its key detail is nowhere to be found. unclear = the evidence genuinely cannot settle it either way.",
                            values: ["confirmed", "rejected", "unclear"]
                        ),
                        "evidence": .string("The specific thing you can see that justifies your verdict — quote text or name what is on screen. One or two sentences."),
                        "objection": .string("For rejected or unclear: exactly what is missing or wrong, written for the agent to act on."),
                        "corrected_answer": .string("If the agent's claimed result misstates something visible on the page, the correct value as the page actually shows it."),
                    ],
                    required: ["verdict", "evidence"]
                )
            )
        )
    }

    // MARK: - Argument DTOs

    nonisolated private struct PlanArguments: Decodable {
        struct Draft: Decodable {
            let title: String?
            let doneWhen: String?
            let hint: String?

            enum CodingKeys: String, CodingKey {
                case title, hint
                case doneWhen = "done_when"
            }
        }

        let tasks: [Draft]?
        let successStatement: String?
        let answerShape: String?

        enum CodingKeys: String, CodingKey {
            case tasks
            case successStatement = "success_statement"
            case answerShape = "answer_shape"
        }
    }

    nonisolated private struct VerdictArguments: Decodable {
        let verdict: String?
        let evidence: String?
        let objection: String?
        let correctedAnswer: String?

        enum CodingKeys: String, CodingKey {
            case verdict, evidence, objection
            case correctedAnswer = "corrected_answer"
        }
    }

    // MARK: - Mission plan

    /// Writes the opening mission checklist. Throws on any failure — the caller
    /// falls back to a single-task plan so a run can never be blocked by this.
    func plan(_ request: PlanRequest) async throws -> MissionPlan {
        var lines = ["USER'S GOAL: \(request.goal)"]
        if let refinement = request.refinement {
            lines.append(refinement.briefingLine)
        }
        lines.append("")
        if let memory = request.memoryNote, !memory.isEmpty {
            lines.append(memory)
            lines.append("")
        }
        if let cautions = request.cautionNote, !cautions.isEmpty {
            lines.append(cautions)
            lines.append("Plan around these where it is cheap to do so — do not build the whole plan around avoiding them.")
            lines.append("")
        }
        lines.append("THE BROWSER IS CURRENTLY ON:")
        lines.append("URL: \(request.urlString.isEmpty ? "about:blank" : request.urlString)")
        lines.append("TITLE: \(request.pageTitle.isEmpty ? "(untitled)" : request.pageTitle)")
        lines.append("")
        lines.append("Write the mission checklist now by calling write_plan exactly once.")
        let context = lines.joined(separator: "\n")

        let message = try await send(
            model: request.modelID,
            system: Self.plannerPrompt,
            parts: [.text(context)],
            tools: [Self.writePlanTool],
            maxTokens: 900,
            temperature: 0.3
        )

        guard let call = message.toolCalls?.first,
              let function = call.function,
              function.name.trimmed.lowercased() == "write_plan",
              let data = (function.arguments?.trimmed.isEmpty == false ? function.arguments : "{}")?.data(using: .utf8),
              let args = try? JSONDecoder().decode(PlanArguments.self, from: data)
        else {
            throw AIError.unparseable
        }

        let drafts = (args.tasks ?? []).compactMap { draft -> PlannedTask? in
            guard let title = draft.title?.trimmed, !title.isEmpty else { return nil }
            return PlannedTask(title: title, doneWhen: draft.doneWhen, hint: draft.hint)
        }

        guard let plan = MissionPlan.make(
            from: drafts,
            successStatement: args.successStatement ?? request.goal,
            answerShape: args.answerShape
        ) else {
            throw AIError.unparseable
        }
        return plan
    }

    // MARK: - Independent check

    /// Judges a claimed success against a fresh look at the page. Throws when the
    /// check itself cannot run — the caller then reports the run as unconfirmed
    /// rather than silently green.
    func verify(_ request: VerifyRequest) async throws -> VerificationResult {
        var lines: [String] = []
        lines.append("THE USER ASKED FOR: \(request.goal)")
        lines.append("")
        lines.append("SUCCESS MEANS (the statement you are judging): \(request.successStatement)")
        if let shape = request.answerShape, !shape.isEmpty {
            lines.append("EXPECTED ANSWER SHAPE: \(shape)")
        }
        lines.append("")
        lines.append("THE AGENT CLAIMS: \(request.claimedResult)")
        lines.append("")
        lines.append("WHAT IT ACTUALLY DID (moves and outcomes only — its explanations are withheld from you on purpose):")
        if request.actionTrail.isEmpty {
            lines.append("(no completed moves were recorded)")
        } else {
            lines.append(contentsOf: request.actionTrail)
        }
        lines.append("")
        lines.append("THE BROWSER RIGHT NOW:")
        lines.append("URL: \(request.urlString.isEmpty ? "about:blank" : request.urlString)")
        lines.append("TITLE: \(request.pageTitle.isEmpty ? "(untitled)" : request.pageTitle)")
        lines.append("")
        lines.append("CURRENT PAGE TEXT (cleaned, headings marked #, lists as •):")
        lines.append(request.pageText.isEmpty ? "(the page returned no readable text)" : request.pageText)
        lines.append("")
        lines.append("A FRESH SCREENSHOT of that same page is attached. Judge the claim against this evidence and call report_verdict exactly once.")

        var parts: [ChatContentPart] = [.text(lines.joined(separator: "\n"))]
        if !request.imageBase64.isEmpty {
            parts.append(.imageJPEG(base64: request.imageBase64))
        }

        let message = try await send(
            model: request.modelID,
            system: Self.verifierPrompt,
            parts: parts,
            tools: [Self.reportVerdictTool],
            maxTokens: 700,
            temperature: 0.0
        )

        guard let call = message.toolCalls?.first,
              let function = call.function,
              function.name.trimmed.lowercased() == "report_verdict",
              let data = (function.arguments?.trimmed.isEmpty == false ? function.arguments : "{}")?.data(using: .utf8),
              let args = try? JSONDecoder().decode(VerdictArguments.self, from: data),
              let verdict = VerificationVerdict(rawValue: (args.verdict ?? "").trimmed.lowercased())
        else {
            throw AIError.unparseable
        }

        let evidence = args.evidence?.trimmed ?? ""
        return VerificationResult(
            verdict: verdict,
            evidence: evidence.isEmpty ? "the check gave no evidence" : evidence,
            objection: args.objection?.trimmed.isEmpty == false ? args.objection?.trimmed : nil,
            correctedAnswer: args.correctedAnswer?.trimmed.isEmpty == false ? args.correctedAnswer?.trimmed : nil,
            checkedBy: request.modelID
        )
    }

    // MARK: - Prompts

    nonisolated private static let plannerPrompt = """
    You are the planner for Pilot, an AI agent that drives a mobile web browser. You do not touch the page yourself — you write the checklist the doer will work from, and the success statement an independent reviewer will later judge.

    Write a plan that is short, ordered, and honest:
    - 3 to 7 tasks for a normal mission. 1 or 2 for a trivial one ("scroll down", "what does this page say"). Never pad a simple goal into busywork.
    - Each task is one concrete step of progress with a "done when" test that can be checked BY LOOKING AT THE SCREEN. "a results list with prices is on screen" is a good test; "the search worked" is not.
    - Order tasks so each one is possible once the previous is done.
    - Prefer direct routes: a search URL beats hunting for a search box, a site's own filters beat scrolling.
    - The success statement is one sentence describing what must be visibly true at the end. Include the specific thing the user asked for (the item, the number, the date). It is the sentence the reviewer will be held to, so vagueness there costs the user a failed check.
    - For question-style goals, set answer_shape to the kind of answer expected.
    - Never assume site structure you cannot know. If the route is uncertain, make the first task "find X on this site" rather than inventing menu names.

    Call write_plan exactly once. No prose.
    """

    nonisolated private static let verifierPrompt = """
    You are an independent reviewer. An AI browsing agent claims it finished a task in a mobile web browser. You did NOT do the work, you have no stake in it, and you must not assume it went well.

    You receive: the user's goal in their own words, the success statement the mission was held to, the agent's claimed result, a bare list of the moves it made with their outcomes, the current page's cleaned text, and a FRESH screenshot of the browser right now.

    You do NOT receive the agent's own explanations or justifications. That is deliberate: agent self-justification makes reviewers agree far too readily. Judge only the evidence in front of you.

    Call report_verdict exactly once:
    - confirmed — the screenshot or page text visibly proves the success statement is true. Name the evidence.
    - rejected — the evidence contradicts the claim, or the specific thing the user asked for is nowhere in the evidence. Write an objection the agent can act on ("the cart still shows 0 items", "no price appears anywhere on this page").
    - unclear — the evidence genuinely cannot settle it. Say what evidence would.

    Rules you must hold to:
    - A confident-sounding claim is not evidence. An empty or half-loaded page is not evidence.
    - If the claim is broadly right but a detail is wrong (a wrong price, date, name, or count), supply corrected_answer with the value the page actually shows.
    - If the goal was a question, the answer must actually appear in the page text or screenshot for you to confirm it.
    - Never guess about a screen you cannot see, and never give the benefit of the doubt. Unconfirmed is a better outcome for the user than a false success.
    """
}
