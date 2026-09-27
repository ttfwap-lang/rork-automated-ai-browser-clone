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
        let lower = Wording.appAuthored(result).lowercased()
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
    ///
    /// Reads only the app's own wording: quoted page content and addresses are
    /// stripped first, so tapping a button named "Report an error" or typing
    /// "missing dog" into a search box is not mistaken for a failed move.
    static func readsAsFailure(_ result: String) -> Bool {
        let lower = Wording.appAuthored(result).lowercased()
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
        Wording.appAuthored(result).localizedCaseInsensitiveContains(noReactionPhrase)
    }

    // MARK: - In-page watcher scripts

    /// Sorts a batch of mutation records into `out.hard` (content changed, a
    /// meaningful state flipped, or the change touched the target itself) and
    /// `out.soft` (style/class churn somewhere else — carousels, timers, ads).
    /// The agent's own ripple never counts.
    static let sortFunction = #"""
        function __rorkSort(list, target, out) {
          var MEANINGFUL = { 'aria-expanded':1, 'aria-selected':1, 'aria-checked':1, 'aria-pressed':1, 'aria-hidden':1, 'aria-busy':1, 'open':1, 'checked':1, 'selected':1, 'disabled':1, 'hidden':1, 'value':1 };
          var SKIP = { SCRIPT:1, STYLE:1, LINK:1, META:1, NOSCRIPT:1 };
          function agentNode(n) {
            return n && n.nodeType === 1 && (n.id === '__agent_css' || (n.classList && n.classList.contains('__agent_ripple')));
          }
          function related(n) {
            if (!target || !n || n.nodeType !== 1) { return false; }
            try { return n === target || target.contains(n) || n.contains(target); } catch (e) { return false; }
          }
          function counts(n) { return !agentNode(n) && !(n && n.nodeType === 1 && SKIP[n.tagName]); }
          for (var i = 0; i < list.length; i++) {
            var m = list[i];
            if (agentNode(m.target)) { continue; }
            if (m.type === 'attributes') {
              if (MEANINGFUL[m.attributeName] || related(m.target)) { out.hard++; } else { out.soft++; }
              continue;
            }
            if (m.type === 'childList') {
              var real = 0;
              for (var a = 0; a < m.addedNodes.length; a++) { if (counts(m.addedNodes[a])) { real++; } }
              for (var r = 0; r < m.removedNodes.length; r++) { if (counts(m.removedNodes[r])) { real++; } }
              if (real === 0) { continue; }
              out.added += real;
              out.hard++;
              continue;
            }
            out.hard++;
          }
        }
        """#

    /// Counts the page's own fetch/XHR requests, so settling can wait for a
    /// reaction that is still on its way from the network. Requests pending for
    /// more than a few seconds are treated as long-polls and ignored.
    static let networkFunctions = #"""
        function __rorkNetInstall() {
          if (window.__rorkNet) { return; }
          var net = { pending: {}, seq: 0 };
          window.__rorkNet = net;
          function begin() { var id = ++net.seq; net.pending[id] = Date.now(); return id; }
          function end(id) { delete net.pending[id]; }
          try {
            var of = window.fetch;
            if (typeof of === 'function') {
              window.fetch = function() {
                var id = begin();
                var p;
                try { p = of.apply(window, arguments); } catch (e) { end(id); throw e; }
                try { p.then(function(){ end(id); }, function(){ end(id); }); } catch (e) { end(id); }
                return p;
              };
            }
          } catch (e) {}
          try {
            var xs = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.send = function() {
              var id = begin();
              try { this.addEventListener('loadend', function(){ end(id); }); } catch (e) { end(id); }
              try { return xs.apply(this, arguments); } catch (e) { end(id); throw e; }
            };
          } catch (e) {}
        }
        function __rorkInflight() {
          var net = window.__rorkNet;
          if (!net) { return 0; }
          var now = Date.now(), n = 0;
          for (var k in net.pending) {
            if (now - net.pending[k] < 4000) { n++; } else { delete net.pending[k]; }
          }
          return n;
        }
        """#

    /// Installs the long-lived quiet observer (and the request counter) in the
    /// current document. Idempotent. `last` moves only on hard changes, so a
    /// spinning carousel cannot keep a page from ever reading as settled.
    static let quietInstallFunction = #"""
        function __rorkQuietInstall() {
          var q = window.__rorkQuiet;
          if (q && q.obs) { return q; }
          q = { t0: Date.now(), last: Date.now(), hard: 0, soft: 0 };
          q.obs = new MutationObserver(function(list){
            var out = { hard: 0, soft: 0, added: 0 };
            __rorkSort(list, null, out);
            q.hard += out.hard;
            q.soft += out.soft;
            if (out.hard > 0) { q.last = Date.now(); }
          });
          q.obs.observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
          window.__rorkQuiet = q;
          __rorkNetInstall();
          return q;
        }
        """#

    static let quietInstallScript = """
        (function(){
          try {
            \(sortFunction)
            \(networkFunctions)
            \(quietInstallFunction)
            __rorkQuietInstall();
            return 'ok';
          } catch (e) { return 'quiet error: ' + e.message; }
        })()
        """

    /// How long since the page last really changed, and how many requests are
    /// still out. `ok: false` means the document was replaced since install.
    static let quietProbeScript = """
        (function(){
          try {
            \(networkFunctions)
            var q = window.__rorkQuiet;
            if (!q) { return JSON.stringify({ ok: false }); }
            return JSON.stringify({ ok: true, since: Date.now() - q.last, inflight: __rorkInflight() });
          } catch (e) { return JSON.stringify({ ok: false }); }
        })()
        """

    /// Starts the background-noise baseline once the page has settled. Whatever
    /// churn happens between now and the next move is the page's own idle rate.
    static let markBaselineScript = #"""
        (function(){
          try {
            var q = window.__rorkQuiet;
            if (!q) { return 'no quiet observer'; }
            q.bt0 = Date.now(); q.bh = q.hard; q.bs = q.soft;
            return 'ok';
          } catch (e) { return 'baseline error: ' + e.message; }
        })()
        """#

    /// Result of one quiet probe.
    nonisolated struct Quiet: Equatable {
        let ok: Bool
        /// Seconds since the last hard change.
        let quietFor: TimeInterval
        let inflight: Int
    }

    nonisolated private struct QuietPayload: Decodable {
        let ok: Bool
        let since: Double?
        let inflight: Int?
    }

    static func parseQuiet(_ raw: String) -> Quiet {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{",
              let payload = try? JSONDecoder().decode(QuietPayload.self, from: Data(trimmed.utf8)),
              payload.ok
        else { return Quiet(ok: false, quietFor: 0, inflight: 0) }
        return Quiet(ok: true, quietFor: max(0, (payload.since ?? 0) / 1000), inflight: max(0, payload.inflight ?? 0))
    }

    /// True once the page has gone this long without a hard change and has no
    /// request still out.
    static func isSettled(_ quiet: Quiet, window: TimeInterval = 0.35) -> Bool {
        quiet.ok && quiet.quietFor >= window && quiet.inflight == 0
    }

    /// Starts the watcher around one move. `targetID` is the element's number in
    /// the frame the script runs in; changes on, inside or around it always count.
    static func startScript(targetID: Int?) -> String {
        let target = targetID.map(String.init) ?? "null"
        return """
        (function(){
          try {
            \(sortFunction)
            \(networkFunctions)
            \(quietInstallFunction)
            if (window.__rorkWatch && window.__rorkWatch.obs) { try { window.__rorkWatch.obs.disconnect(); } catch (e) {} }
            var q = __rorkQuietInstall();
            var TARGET = \(target);
            var target = null;
            try {
              var reg = window.__rorkAgent && window.__rorkAgent.els;
              if (reg && TARGET !== null) { target = reg[TARGET] || null; }
            } catch (e) {}
            var SEL = 'a[href],button,input,select,textarea,[role="button"],[role="link"],[role="menuitem"],[role="option"],[role="checkbox"],[role="switch"]';
            var now = Date.now();
            var w = { hard: 0, soft: 0, added: 0, url: location.href, count0: -1, t0: now, base: null };
            if (q.bt0) { w.base = { t: now - q.bt0, hard: q.hard - q.bh, soft: q.soft - q.bs }; }
            try { w.count0 = document.querySelectorAll(SEL).length; } catch (e) {}
            w.obs = new MutationObserver(function(list){
              if (w.hard + w.soft >= 2000) { try { w.obs.disconnect(); } catch (e) {} return; }
              __rorkSort(list, target, w);
            });
            w.obs.observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
            window.__rorkWatch = w;
            return 'ok';
          } catch (e) { return 'watch error: ' + e.message; }
        })()
        """
    }

    /// Stops the watcher. Background churn is subtracted at twice the page's own
    /// idle rate, so a ticking page does not make every move look like it worked;
    /// on a quiet page nothing is subtracted.
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
            var dur = Math.max(1, Date.now() - w.t0);
            var hard = w.hard, soft = w.soft;
            if (w.base && w.base.t >= 800) {
              hard = Math.max(0, hard - Math.ceil(2 * (w.base.hard / w.base.t) * dur));
              soft = Math.max(0, soft - Math.ceil(2 * (w.base.soft / w.base.t) * dur));
            }
            return JSON.stringify({ ok: true, muts: Math.min(hard + soft, 500), added: w.added, urlChanged: location.href !== w.url, newInteractive: Math.max(delta, 0) });
          } catch (e) { return JSON.stringify({ ok: false }); }
        })()
        """#
}
