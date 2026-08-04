import Foundation

/// The mission checklist written before the first move: numbered tasks with
/// observable finish tests, plus the single success statement the independent
/// check is later held to.
///
/// The plan is a map, never a cage — the doer may reorder, shortcut or skip, and
/// this type records what actually happened rather than what was intended.
nonisolated struct MissionPlan: Codable, Hashable {
    /// How many times a run may rewrite its plan.
    static let maxRevisions = 2
    /// Upper bound on tasks accepted from the model.
    static let maxTasks = 7

    var tasks: [MissionTask]
    /// The one sentence that defines success for the whole mission.
    var successStatement: String
    /// For question-style goals: the shape of the expected answer ("a price").
    var answerShape: String?
    /// How many times the plan has been rewritten.
    var revisions: Int
    /// True when planning was unavailable and this is the single-task fallback.
    var isFallback: Bool

    init(
        tasks: [MissionTask],
        successStatement: String,
        answerShape: String? = nil,
        revisions: Int = 0,
        isFallback: Bool = false
    ) {
        self.tasks = tasks
        self.successStatement = successStatement
        self.answerShape = answerShape
        self.revisions = revisions
        self.isFallback = isFallback
    }

    /// The single-task plan used when planning is unavailable — a run can never
    /// break because the planner failed.
    static func fallback(goal: String) -> MissionPlan {
        MissionPlan(
            tasks: [
                MissionTask(
                    number: 1,
                    title: goal,
                    doneWhen: "the goal is visibly achieved on the page",
                    state: .current
                )
            ],
            successStatement: goal,
            isFallback: true
        )
    }

    /// Builds a plan from model drafts, numbering them 1…n.
    static func make(
        from drafts: [PlannedTask],
        successStatement: String,
        answerShape: String?
    ) -> MissionPlan? {
        let cleaned = drafts
            .map { PlannedTask(title: $0.title.trimmed, doneWhen: $0.doneWhen?.trimmed, hint: $0.hint?.trimmed) }
            .filter { !$0.title.isEmpty }
            .prefix(maxTasks)
        guard !cleaned.isEmpty else { return nil }

        var plan = MissionPlan(
            tasks: cleaned.enumerated().map { offset, draft in
                MissionTask(
                    number: offset + 1,
                    title: draft.title,
                    doneWhen: draft.doneWhen?.isEmpty == false ? draft.doneWhen! : "this task is visibly finished on screen",
                    hint: draft.hint?.isEmpty == false ? draft.hint : nil
                )
            },
            successStatement: successStatement.trimmed.isEmpty ? "the goal is achieved" : successStatement.trimmed,
            answerShape: answerShape?.trimmed.isEmpty == false ? answerShape?.trimmed : nil
        )
        plan.refreshCurrent()
        return plan
    }

    // MARK: - Progress

    var doneCount: Int { tasks.filter { $0.state == .done }.count }
    var skippedCount: Int { tasks.filter { $0.state == .skipped }.count }
    var settledCount: Int { tasks.filter { $0.state.isSettled }.count }

    /// 0…1 across settled tasks, for the progress bar.
    var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(settledCount) / Double(tasks.count)
    }

    var currentTask: MissionTask? {
        tasks.first { $0.state == .current }
    }

    var canRevise: Bool { revisions < Self.maxRevisions }

    func task(numbered number: Int) -> MissionTask? {
        tasks.first { $0.number == number }
    }

    // MARK: - Mutation

    /// Recomputes which task is current: the first unsettled task, everything
    /// after it pending.
    mutating func refreshCurrent() {
        var foundCurrent = false
        for index in tasks.indices where !tasks[index].state.isSettled {
            tasks[index].state = foundCurrent ? .pending : .current
            foundCurrent = true
        }
    }

    /// Applies what the agent reported this step: tasks it can SEE are finished,
    /// and the task its move serves (anything it stepped over is marked skipped,
    /// never done). Returns how many tasks were newly ticked.
    @discardableResult
    mutating func apply(claimedCurrent: Int?, completed: [Int]?) -> Int {
        var ticked = 0
        for number in completed ?? [] {
            guard let index = tasks.firstIndex(where: { $0.number == number }) else { continue }
            guard tasks[index].state != .done else { continue }
            tasks[index].state = .done
            tasks[index].skipReason = nil
            ticked += 1
        }

        if let claimed = claimedCurrent,
           let target = tasks.firstIndex(where: { $0.number == claimed }) {
            for index in tasks.indices where index < target && !tasks[index].state.isSettled {
                tasks[index].state = .skipped
                tasks[index].skipReason = "the agent moved straight to task \(claimed)"
            }
        }

        refreshCurrent()
        return ticked
    }

    /// Un-ticks the last finished task — used when the independent check rejects
    /// a success claim, so the checklist never shows work that wasn't accepted.
    mutating func untickLatest() {
        guard let index = tasks.lastIndex(where: { $0.state == .done }) else { return }
        tasks[index].state = .pending
        refreshCurrent()
    }

    /// Rewrites the remaining tasks. Finished and skipped tasks stay exactly as
    /// they are; new tasks continue the numbering so earlier references keep
    /// pointing at the same work.
    mutating func revise(with drafts: [PlannedTask]) {
        let settled = tasks.filter { $0.state.isSettled }
        var nextNumber = tasks.map(\.number).max() ?? settled.count
        var rebuilt = settled

        for draft in drafts where !draft.title.trimmed.isEmpty {
            guard rebuilt.count < Self.maxTasks + settled.count else { break }
            nextNumber += 1
            rebuilt.append(
                MissionTask(
                    number: nextNumber,
                    title: draft.title.trimmed,
                    doneWhen: draft.doneWhen?.trimmed.isEmpty == false ? draft.doneWhen!.trimmed : "this task is visibly finished on screen",
                    hint: draft.hint?.trimmed.isEmpty == false ? draft.hint?.trimmed : nil
                )
            )
        }

        tasks = rebuilt
        revisions += 1
        isFallback = false
        refreshCurrent()
    }

    // MARK: - Briefing

    /// The checklist as the doer sees it each step — leads its briefing so the
    /// agent stops re-deriving the whole mission from scratch.
    var briefingText: String {
        var lines: [String] = []
        let header = isFallback
            ? "MISSION PLAN (planning was unavailable — single-task fallback):"
            : "MISSION PLAN — \(doneCount) of \(tasks.count) tasks done:"
        lines.append(header)

        for task in tasks {
            switch task.state {
            case .done:
                lines.append("\(task.number). [x] \(task.title)")
            case .current:
                lines.append("\(task.number). [-> CURRENT] \(task.title) — done when: \(task.doneWhen)")
            case .pending:
                lines.append("\(task.number). [ ] \(task.title) — done when: \(task.doneWhen)")
            case .skipped:
                let why = task.skipReason.map { " — \($0)" } ?? ""
                lines.append("\(task.number). [skipped] \(task.title)\(why)")
            }
        }

        lines.append("SUCCESS MEANS: \(successStatement)")
        if let shape = answerShape, !shape.isEmpty {
            lines.append("ANSWER SHAPE: \(shape)")
        }

        if let current = currentTask {
            lines.append("YOUR CURRENT TASK: \(current.number). \(current.title) — done when: \(current.doneWhen)")
            if let hint = current.hint, !hint.isEmpty {
                lines.append("ROUTE HINT for this task: \(hint)")
            }
        } else {
            lines.append("EVERY TASK IS SETTLED — if the success statement is visibly true, call done with the answer; if it is not, call revise_plan.")
        }

        lines.append("With every tool call also report \"task\" (the task number your move serves) and \"completed_tasks\" (task numbers you can SEE are finished on this screen — evidence, never intent).")
        return lines.joined(separator: "\n")
    }
}

extension String {
    /// Whitespace- and newline-trimmed copy.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
