import Foundation

/// The honesty layer: a change-watcher that runs around EVERY move — taps,
/// typing, scrolls, navigation, gestures and form hands — and reports whether
/// the page actually reacted: content changes, address changes, and newly
/// appeared interactive elements. The agent's own tap ripple is filtered out so
/// it never counts as a reaction.
///
/// Different moves need different evidence, so the wording is specialised:
/// scrolling is judged by whether the page moved, typing by whether the field
/// took the text, and navigation by whether the address actually changed.
nonisolated enum ReactionWatch {

    nonisolated struct Verdict: Equatable {
        let text: String
    }

    nonisolated private struct Payload: Decodable {
        let ok: Bool
        let muts: Int?
        let added: Int?
        let urlChanged: Bool?
        let newInteractive: Int?
    }

    /// Parses the end-watch JSON. `pageNavigated` is the Swift-side URL check —
    /// it catches full navigations that wipe the in-page watcher.
    static func verdict(fromRaw raw: String, pageNavigated: Bool) -> Verdict {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{",
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(trimmed.utf8)),
              payload.ok else {
            return Verdict(text: pageNavigated
                ? "the page navigated to a new address"
                : "reaction unknown — the page may have reloaded")
        }
        return format(
            mutations: payload.muts ?? 0,
            urlChanged: (payload.urlChanged ?? false) || pageNavigated,
            newInteractive: payload.newInteractive ?? 0
        )
    }

    /// The phrase that means "nothing happened" — the one signal the escalation,
    /// dead-end and difficulty logic all key off.
    static let noReactionPhrase = "no visible reaction"

    /// Pure verdict wording, unit-tested.
    static func format(mutations: Int, urlChanged: Bool, newInteractive: Int) -> Verdict {
        if !urlChanged && mutations <= 0 {
            return Verdict(text: "\(noReactionPhrase) — this site may need real finger input")
        }
        var parts: [String] = []
        if urlChanged { parts.append("address changed") }
        if mutations > 0 {
            let count = mutations >= 500 ? "500+" : String(mutations)
            parts.append("\(count) change\(mutations == 1 ? "" : "s")")
        }
        if newInteractive > 0 {
            parts.append("\(newInteractive) new interactive element\(newInteractive == 1 ? "" : "s")")
        }
        return Verdict(text: "page reacted (\(parts.joined(separator: ", ")))")
    }

    // MARK: - Move-specific verdicts

    /// Scrolling barely mutates the DOM, so the honest evidence is movement.
    /// Content that lazy-loads without moving still counts as a reaction.
    static func scrollVerdict(movedBy delta: Double, watcher: String) -> Verdict {
        let moved = abs(delta)
        if moved >= 8 {
            return Verdict(text: "the page moved \(Int(moved.rounded()))px")
        }
        if !watcher.contains(noReactionPhrase) && !watcher.isEmpty {
            return Verdict(text: "the page did not move but \(watcher)")
        }
        return Verdict(text: "the page did not move — you may be at the end of the page")
    }

    /// Typing into a plain field changes no DOM node, so the honest evidence is
    /// the field's own value afterwards. A site that reformats what it was given
    /// (phone numbers, dates) is reported as reformatted, never as a failure.
    static func typingVerdict(
        typed: String,
        fieldValue: String?,
        watcher: String,
        submitted: Bool
    ) -> Verdict {
        let wanted = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var base: String
        var usedWatcher = false

        switch fieldValue {
        case .none:
            if watcher.contains(noReactionPhrase) || watcher.isEmpty {
                base = "the field is no longer on the page"
            } else {
                base = watcher
                usedWatcher = true
            }
        case .some(let value) where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            base = wanted.isEmpty
                ? "the field is empty"
                : "the field did not take the text — it is still empty"
        case .some(let value) where value.lowercased().contains(wanted) || wanted.contains(value.lowercased()):
            base = "the field now holds \"\(String(value.prefix(40)))\""
        case .some(let value):
            base = "the field now holds \"\(String(value.prefix(40)))\" — the site reformatted it"
        }

        guard submitted, !watcher.isEmpty, !usedWatcher else { return Verdict(text: base) }
        return Verdict(text: "\(base); after submit: \(watcher)")
    }

    /// Going back or opening an address: the honest evidence is the address
    /// actually moving, which the app can see without asking the page.
    static func addressVerdict(before: String, after: String) -> Verdict {
        guard !after.isEmpty else {
            return Verdict(text: "the page did not load — that move went nowhere")
        }
        guard after != before else {
            return Verdict(text: "the address did not change — that move went nowhere")
        }
        return Verdict(text: "landed on \(shortAddress(after))")
    }

    /// Trims a URL to something readable in a one-line log entry.
    static func shortAddress(_ urlString: String) -> String {
        var trimmed = urlString
        for prefix in ["https://", "http://"] where trimmed.hasPrefix(prefix) {
            trimmed.removeFirst(prefix.count)
        }
        if trimmed.hasPrefix("www.") { trimmed.removeFirst(4) }
        return trimmed.count > 60 ? String(trimmed.prefix(59)) + "…" : trimmed
    }

    // MARK: - Attaching verdicts honestly

    /// Appends a reaction verdict to a result line — unless the move never
    /// actually ran (stale element, missing argument, script error, or a skip
    /// like "already ON"), in which case a verdict would be misleading.
    static func combine(_ result: String, _ verdict: String) -> String {
        guard !verdict.isEmpty else { return result }
        guard shouldAttachVerdict(to: result) else { return result }
        return "\(result) · \(verdict)"
    }

    /// False when the result line already says the move never happened.
    static func shouldAttachVerdict(to result: String) -> Bool {
        let lower = result.lowercased()
        let neverRan = [
            "no action taken", "no longer on the page", "missing", "error",
            "not supported", "not a typeable field", "nothing at that point",
            "no field is focused", "had no fields", "needs both ends",
        ]
        return !neverRan.contains { lower.contains($0) }
    }

    /// The single source of truth for "that move failed": what escalates the next
    /// step to the frontier model, records a dead end at the current checkpoint,
    /// and puts the runner-up move back on the table.
    static func readsAsFailure(_ result: String) -> Bool {
        let lower = result.lowercased()
        let signals = [
            noReactionPhrase, "no longer on the page", "couldn't", "could not",
            "no action taken", "error", "missing", "nothing at that point",
            "not typeable", "not a typeable field", "no field is focused",
            "not supported", "did not move", "did not take the text",
            "went nowhere", "is no longer on the page",
        ]
        return signals.contains { lower.contains($0) }
    }

    /// True when the move ran but the page did nothing — not a failure, not a
    /// success. Kept apart from `readsAsFailure` so the live panel can colour it
    /// amber instead of lying in either direction.
    static func readsAsNoReaction(_ result: String) -> Bool {
        result.localizedCaseInsensitiveContains(noReactionPhrase)
    }

    // MARK: - In-page watcher scripts

    static let startScript = #"""
        (function(){
          try {
            if (window.__rorkWatch && window.__rorkWatch.obs) { try { window.__rorkWatch.obs.disconnect(); } catch (e) {} }
            var SEL = 'a[href],button,input,select,textarea,[role="button"],[role="link"],[role="menuitem"],[role="option"],[role="checkbox"],[role="switch"]';
            var w = { muts: 0, added: 0, url: location.href, count0: -1 };
            try { w.count0 = document.querySelectorAll(SEL).length; } catch (e) {}
            function agentNode(n) {
              return n && n.nodeType === 1 && (n.id === '__agent_css' || (n.classList && n.classList.contains('__agent_ripple')));
            }
            w.obs = new MutationObserver(function(list){
              if (w.muts >= 500) { try { w.obs.disconnect(); } catch (e) {} return; }
              for (var i = 0; i < list.length; i++) {
                var m = list[i];
                if (agentNode(m.target)) { continue; }
                if (m.type === 'childList') {
                  var real = 0;
                  for (var a = 0; a < m.addedNodes.length; a++) { if (!agentNode(m.addedNodes[a])) { real++; } }
                  for (var r = 0; r < m.removedNodes.length; r++) { if (!agentNode(m.removedNodes[r])) { real++; } }
                  if (real === 0) { continue; }
                  w.added += real;
                }
                w.muts++;
              }
            });
            w.obs.observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
            window.__rorkWatch = w;
            return 'ok';
          } catch (e) { return 'watch error: ' + e.message; }
        })()
        """#

    static let endScript = #"""
        (function(){
          try {
            var w = window.__rorkWatch;
            if (!w) { return JSON.stringify({ ok: false }); }
            try { w.obs.disconnect(); } catch (e) {}
            window.__rorkWatch = null;
            var SEL = 'a[href],button,input,select,textarea,[role="button"],[role="link"],[role="menuitem"],[role="option"],[role="checkbox"],[role="switch"]';
            var now = -1;
            try { now = document.querySelectorAll(SEL).length; } catch (e) {}
            var delta = (w.count0 >= 0 && now >= 0) ? (now - w.count0) : 0;
            return JSON.stringify({ ok: true, muts: w.muts, added: w.added, urlChanged: location.href !== w.url, newInteractive: Math.max(delta, 0) });
          } catch (e) { return JSON.stringify({ ok: false }); }
        })()
        """#
}
