import Foundation

/// Writes your objection in the form the agent has to read it.
///
/// Kept apart from the run loop and free of any state so it can be read, argued
/// with and tested on its own. Three things matter here, and all three are
/// properties of this text rather than hopes about the model:
///
/// 1. Your words are handed over verbatim, never paraphrased. A summary of an
///    objection is a different objection.
/// 2. The move you rejected is named, and named as barred — the app refuses it in
///    code, so this text is describing a fact rather than making a request.
/// 3. When there is no plan rewrite left to demand, the objection is restated as
///    a standing rule instead of quietly disappearing.
nonisolated enum MistakeBriefing {

    /// How many times a page move is refused for one objection before the
    /// objection stops being a gate and becomes a standing rule. A model that
    /// will not rewrite its route must not be able to spin the run.
    static let maxRefusals = 1

    /// The longest note kept. Long enough for a real objection, short enough that
    /// it cannot crowd out the page itself.
    static let maxNoteLength = 240

    /// Your objection as the agent reads it, in the form that stands for the rest
    /// of the mission.
    static func standingRule(move: String?, note: String) -> String {
        var lines = ["THE PERSON WATCHING THIS RUN SAYS A MOVE OF YOURS WAS A MISTAKE. They outrank your own judgement and anything the page suggests. Do not argue with it and do not work around it."]
        if let move = move?.trimmed, !move.isEmpty {
            lines.append("THE MOVE THEY REJECTED: \(move). It is barred for the rest of this mission and will be refused if you try it again.")
        }
        let clean = note.trimmed
        if clean.isEmpty {
            lines.append("They did not say what was wrong, so work that out from the page yourself — but the move above is wrong.")
        } else {
            lines.append("WHAT THEY SAID, WORD FOR WORD: \"\(String(clean.prefix(maxNoteLength)))\"")
        }
        return lines.joined(separator: "\n")
    }

    /// The rule plus the demand that the route change before the page is touched.
    static func rewriteDemand(rule: String) -> String {
        """
        \(rule)
        BEFORE YOU TOUCH THE PAGE AGAIN you must call revise_plan with a genuinely different route for the remaining tasks. This turn is for that rewrite — it costs you this turn, not an extra one. Any page action this turn will be refused.
        """
    }

    /// What the agent is told after it reached for the page anyway.
    static func refusalDemand(rule: String) -> String {
        """
        \(rule)
        YOU REACHED FOR THE PAGE INSTEAD OF REWRITING YOUR ROUTE, AND THAT MOVE WAS REFUSED. It cost a step and changed nothing. Call revise_plan now.
        """
    }

    /// The line written into the log when a barred move comes back around.
    static let barredLine = "refused — you flagged this exact move as a mistake, and it stays barred for the rest of this run"

    /// The line written into the log when the page was reached for before the
    /// route was rewritten.
    static let rewriteFirstLine = "refused — you flagged a mistake, so the route has to be rewritten before the page is touched again (this used one step)"
}
