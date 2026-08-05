import Foundation

/// A finished run saved to device history. `plan` and `verdictRaw` are optional
/// so runs saved before mission planning shipped keep opening normally.
nonisolated struct AgentRun: Codable, Identifiable, Hashable {
    let id: UUID
    let goal: String
    let date: Date
    let outcome: RunOutcome
    let summary: String
    let steps: [PersistedStep]
    /// The mission checklist as it stood when the run ended.
    var plan: MissionPlan? = nil
    /// The independent check's final verdict, when one ran.
    var verdictRaw: String? = nil
    /// Routing accounting: how every paid AI call split between the two models.
    /// (Named for the steps they used to count; they now include planning and checks.)
    var fastSteps: Int? = nil
    var preciseSteps: Int? = nil
    /// How many times the agent went back to a checkpoint.
    var rewinds: Int? = nil
    /// How many candidate moves were weighed across the run.
    var weighedMoves: Int? = nil
    /// The paid calls that are not step decisions: the opening plan and each check.
    var planningCalls: Int? = nil
    var checkCalls: Int? = nil
    /// The one paid call writing a memory can cost on a phone that cannot run
    /// the free tier.
    var memoryCalls: Int? = nil
    /// Decisions made on this iPhone's own model, which cost nothing.
    var freeSteps: Int? = nil
    /// The remembered route this run recognised, when one was used.
    var memoryUsed: String? = nil
    /// How many opening moves were replayed from that memory.
    var replayedMoves: Int? = nil
    /// False when the replay stopped early because the site had changed.
    var headStartHeld: Bool? = nil
    /// The saved one-tap replay this run came from, when it came from one.
    var routineTitle: String? = nil
    /// How many saved steps had to be repaired because the site had moved them.
    var healedMoves: Int? = nil
    /// Paid calls spent working out where a moved control had gone.
    var repairCalls: Int? = nil
    /// How many cautions from this site's notebook were folded into the briefing.
    var cautionsUsed: Int? = nil
    /// How many times you told the agent a move was a mistake.
    var mistakesFlagged: Int? = nil
    /// How many form fields were filled from your own dossier.
    var dossierFills: Int? = nil
    /// How many of this run's form fields were worked out for nothing — by the
    /// page declaring its purpose, by its label, or by your iPhone reading it.
    var freeFieldMatches: Int? = nil

    var verdict: VerificationVerdict? {
        verdictRaw.flatMap { VerificationVerdict(rawValue: $0) }
    }

    /// Browser steps only — the independent check is not a step you paid for.
    var browserStepCount: Int {
        steps.filter { $0.kind != .verify }.count
    }

    /// "5 free, 7 fast, 4 precise" — nil when the run predates model routing.
    /// The free share is listed first because it is the part that cost nothing.
    var routingSplit: String? {
        let free = freeSteps ?? 0
        let fast = fastSteps ?? 0
        let precise = preciseSteps ?? 0
        guard free + fast + precise > 0 else { return nil }
        var parts: [String] = []
        if free > 0 { parts.append("\(free) free") }
        parts.append("\(fast) fast")
        parts.append("\(precise) precise")
        return parts.joined(separator: ", ")
    }

    /// "Grocery top-up — 5 moves replayed, 1 repaired" — nil when this run was
    /// not launched from a saved replay.
    var routineLine: String? {
        guard let routineTitle, !routineTitle.isEmpty else { return nil }
        var line = routineTitle
        let replayed = replayedMoves ?? 0
        if replayed > 0 {
            line += " — \(replayed) move\(replayed == 1 ? "" : "s") replayed"
        }
        if let healed = healedMoves, healed > 0 {
            line += ", \(healed) repaired"
        }
        if headStartHeld == false {
            line += ", then the site had changed too much"
        }
        return line
    }

    /// "2 cautions from earlier failures here" — nil when the notebook was silent.
    var cautionLine: String? {
        guard let cautionsUsed, cautionsUsed > 0 else { return nil }
        return "\(cautionsUsed) caution\(cautionsUsed == 1 ? "" : "s") from earlier failures on this site"
    }

    /// "18 fields filled from your dossier — 20 matched free" — nil when no form
    /// was filled from your details.
    var dossierLine: String? {
        let filled = dossierFills ?? 0
        let matched = freeFieldMatches ?? 0
        guard filled > 0 || matched > 0 else { return nil }
        var line = "\(filled) field\(filled == 1 ? "" : "s") filled from your dossier"
        if matched > filled {
            line += " — \(matched) matched free on this iPhone"
        }
        return line
    }

    /// "You flagged 1 mistake" — nil when you never stepped in.
    var mistakeLine: String? {
        guard let mistakesFlagged, mistakesFlagged > 0 else { return nil }
        return "you flagged \(mistakesFlagged) mistake\(mistakesFlagged == 1 ? "" : "s")"
    }

    /// "3 moves replayed from memory" — nil when no memory was recalled.
    var memoryLine: String? {
        guard let memoryUsed, !memoryUsed.isEmpty else { return nil }
        let replayed = replayedMoves ?? 0
        guard replayed > 0 else { return "\(memoryUsed) — recalled, nothing replayed" }
        var line = "\(memoryUsed) — \(replayed) opening move\(replayed == 1 ? "" : "s") replayed"
        if headStartHeld == false {
            line += ", then the site had changed"
        }
        return line
    }

    /// Every AI call this run PAID for. Free on-device decisions are deliberately
    /// excluded: counting them here would inflate a number whose whole job is to
    /// tell the user what the run cost.
    var totalCalls: Int? {
        let total = (fastSteps ?? 0) + (preciseSteps ?? 0)
        return total > 0 ? total : nil
    }

    /// "13 calls — 11 steps, 1 plan, 1 check": the number you read is the number
    /// you paid for. Only the parts that actually happened are listed.
    var callBreakdown: String? {
        guard let total = totalCalls else { return nil }
        let planning = planningCalls ?? 0
        let checks = checkCalls ?? 0
        let memory = memoryCalls ?? 0
        let stepCalls = max(total - planning - checks - memory - (repairCalls ?? 0), 0)
        var parts: [String] = []
        if stepCalls > 0 { parts.append("\(stepCalls) step\(stepCalls == 1 ? "" : "s")") }
        if planning > 0 { parts.append("\(planning) plan") }
        if checks > 0 { parts.append("\(checks) check\(checks == 1 ? "" : "s")") }
        if memory > 0 { parts.append("\(memory) memory") }
        if let repairs = repairCalls, repairs > 0 {
            parts.append("\(repairs) repair\(repairs == 1 ? "" : "s")")
        }
        let headline = "\(total) call\(total == 1 ? "" : "s")"
        var line = parts.isEmpty ? headline : "\(headline) — \(parts.joined(separator: ", "))"
        if let free = freeSteps, free > 0 {
            line += " · plus \(free) free on your iPhone"
        }
        return line
    }
}
