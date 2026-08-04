import WebKit
import Observation

/// Owns the WKWebView and gives the agent full control of it:
/// snapshots, synthetic taps (with a glowing ripple), typing, scrolling, and
/// navigation. Pro hands (form moves, gestures, whole-page sight, embedded
/// panel routing) live in WebViewProxy+ProHands.
@Observable
final class WebViewProxy: NSObject, WKNavigationDelegate {
    /// Where an element-targeted action must run: which embedded panel frame
    /// owns the element and its local badge number inside that frame.
    struct PanelRoute {
        let frame: WKFrameInfo
        let localID: Int
        let host: String
        let originX: Double
        let originY: Double
    }

    let webView: WKWebView
    /// Collects frame handles for embedded panels as pages load.
    let frameRegistry = FrameRegistry()
    /// Global element id → embedded panel route, rebuilt on every observe().
    var panelRoutes: [Int: PanelRoute] = [:]
    /// State for the reaction watcher (set by beginReactionWatch).
    var reactionWatchFrame: WKFrameInfo?
    var reactionWatchURL = ""

    private(set) var isLoading = false
    private(set) var currentURLString = ""
    private(set) var pageTitle = ""
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.043, green: 0.055, blue: 0.075, alpha: 1)
        webView.scrollView.backgroundColor = .clear
        super.init()
        webView.navigationDelegate = self
        let controller = webView.configuration.userContentController
        controller.add(frameRegistry, name: FrameRegistry.messageName)
        controller.addUserScript(WKUserScript(
            source: FrameRegistry.helloScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
    }

    // MARK: - Navigation

    /// Loads a URL string; bare words become a DuckDuckGo search.
    func load(_ raw: String) {
        var target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        let lower = target.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            if target.contains(" ") || !target.contains(".") {
                let query = target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? target
                target = "https://duckduckgo.com/?q=\(query)"
            } else {
                target = "https://\(target)"
            }
        }
        guard let url = URL(string: target) else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    /// Waits until the page stops loading (or the timeout passes), plus a short settle delay.
    func waitForQuiet(maxWait: TimeInterval) async {
        let start = Date()
        try? await Task.sleep(for: .milliseconds(250))
        while webView.isLoading && Date().timeIntervalSince(start) < maxWait && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
        try? await Task.sleep(for: .milliseconds(350))
    }

    // MARK: - Snapshot

    /// Captures the visible viewport, already downscaled for AI input.
    func snapshot(width: Double = 700) async -> UIImage? {
        guard webView.bounds.width > 0, webView.bounds.height > 0 else { return nil }
        return await withCheckedContinuation { continuation in
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = NSNumber(value: width)
            webView.takeSnapshot(with: config) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Observation

    /// Runs the Set-of-Mark page scan: catalogs, numbers, and registers every
    /// pressable element, then merges in up to two visible embedded panels.
    /// Returns nil when the site blocks scripts or the page isn't ready —
    /// callers then fall back to pure-vision behavior.
    func observe() async -> PageObservation? {
        panelRoutes = [:]
        let raw = await runJS(PageScanner.scanScript)
        guard let observation = PageScanner.parse(raw) else {
            print("[WebViewProxy] page scan unavailable: \(String(raw.prefix(120)))")
            return nil
        }
        return await mergingPanelElements(into: observation)
    }

    // MARK: - Agent actions

    /// Taps catalogued element `id` through its true center (auto-scrolled into
    /// view), with stale-element re-matching by name and an honest miss report.
    /// Routes automatically into the owning embedded panel when needed.
    func tapElement(id: Int, descriptor: String, expectedName: String) async -> String {
        let route = panelRoutes[id]
        return await runJS(
            PageScanner.tapScript(id: route?.localID ?? id, display: id, descriptor: descriptor, expectedName: expectedName),
            in: route?.frame
        )
    }

    /// Focuses catalogued field `id` and types into it in one move, with optional submit.
    func typeInto(id: Int, text: String, submit: Bool, descriptor: String, expectedName: String) async -> String {
        let route = panelRoutes[id]
        return await runJS(
            PageScanner.typeScript(id: route?.localID ?? id, display: id, text: text, submit: submit, descriptor: descriptor, expectedName: expectedName),
            in: route?.frame
        )
    }

    /// Taps at normalized (0–1000) screenshot coordinates, showing a cyan ripple on the page.
    /// Last-resort move for element-free surfaces (maps, canvases).
    func tap(normX: Double, normY: Double) async -> String {
        let x = min(max(normX, 0), 1000) / 1000.0 * webView.bounds.width
        let y = min(max(normY, 0), 1000) / 1000.0 * webView.bounds.height
        let js = #"""
        (function(){
          var x = \#(String(format: "%.1f", x)), y = \#(String(format: "%.1f", y));
          try {
            if (!document.getElementById('__agent_css')) {
              var st = document.createElement('style'); st.id = '__agent_css';
              st.textContent = '@keyframes __agentPulse{0%{transform:translate(-50%,-50%) scale(.4);opacity:.95}100%{transform:translate(-50%,-50%) scale(2.6);opacity:0}} .__agent_ripple{position:fixed;width:44px;height:44px;border-radius:50%;border:2px solid #00E5FF;background:rgba(0,229,255,.25);box-shadow:0 0 18px #00E5FF;pointer-events:none;z-index:2147483647;animation:__agentPulse .7s ease-out forwards}';
              document.head.appendChild(st);
            }
            var r = document.createElement('div'); r.className = '__agent_ripple';
            r.style.left = x + 'px'; r.style.top = y + 'px';
            document.body.appendChild(r);
            setTimeout(function(){ r.remove(); }, 750);
            var el = document.elementFromPoint(x, y);
            if (!el) { return 'nothing at that point'; }
            var opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y };
            el.dispatchEvent(new PointerEvent('pointerdown', opts));
            el.dispatchEvent(new MouseEvent('mousedown', opts));
            el.dispatchEvent(new PointerEvent('pointerup', opts));
            el.dispatchEvent(new MouseEvent('mouseup', opts));
            var target = el.closest('a,button,input,textarea,select,[role="button"],[onclick],[contenteditable]') || el;
            if (target && target.matches && target.matches('input,textarea,[contenteditable]')) { target.focus(); }
            if (target && typeof target.click === 'function') { target.click(); }
            else { el.dispatchEvent(new MouseEvent('click', opts)); }
            var tag = (target.tagName || '?').toLowerCase();
            var txt = ((target.innerText || target.value || target.getAttribute('aria-label') || '') + '').trim().slice(0, 40);
            return 'tapped <' + tag + '>' + (txt ? ' "' + txt + '"' : '');
          } catch (e) { return 'tap error: ' + e.message; }
        })()
        """#
        return await runJS(js)
    }

    /// Types into the focused field using native value setters so frameworks like React notice.
    func typeText(_ text: String, submit: Bool) async -> String {
        let literal = PageScanner.jsStringLiteral(text)
        let js = #"""
        (function(){
          var t = \#(literal); var doSubmit = \#(submit ? "true" : "false");
          var el = document.activeElement;
          if (!el || el === document.body) { return 'no field is focused — tap a field first'; }
          try {
            if (el.isContentEditable) {
              document.execCommand('insertText', false, t);
            } else if ('value' in el) {
              var proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
              var desc = Object.getOwnPropertyDescriptor(proto, 'value');
              if (desc && desc.set) { desc.set.call(el, t); } else { el.value = t; }
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            } else { return 'focused element is not typeable'; }
            if (doSubmit) {
              var ke = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
              el.dispatchEvent(new KeyboardEvent('keydown', ke));
              el.dispatchEvent(new KeyboardEvent('keypress', ke));
              el.dispatchEvent(new KeyboardEvent('keyup', ke));
              if (el.form) { if (el.form.requestSubmit) { el.form.requestSubmit(); } else { el.form.submit(); } }
            }
            return 'typed "' + t.slice(0, 40) + '"' + (doSubmit ? ' and submitted' : '');
          } catch (e) { return 'type error: ' + e.message; }
        })()
        """#
        return await runJS(js)
    }

    func scroll(direction: String, amount: Double) async -> String {
        let clamped = min(max(abs(amount), 100), 1600)
        let signed = direction.lowercased() == "up" ? -clamped : clamped
        let js = #"""
        (function(){
          var amt = \#(String(format: "%.0f", signed));
          window.scrollBy({ top: Number(amt), left: 0, behavior: 'smooth' });
          return 'scrolled \#(direction.lowercased() == "up" ? "up" : "down") \#(String(format: "%.0f", clamped))px';
        })()
        """#
        return await runJS(js)
    }

    /// Cleaned whole-page reading: main content detected, menus and clutter
    /// stripped, headings marked with #, lists as bullets — the entire page,
    /// not just the visible part.
    func extractText() async -> String {
        await runJS(PageReader.readScript)
    }

    // MARK: - JS plumbing

    /// Runs a script in the main frame or, when `frame` is given, inside that
    /// embedded panel. All agent scripts return strings; JS errors come back
    /// as readable "js error: …" lines so callers can fail soft.
    func runJS(_ script: String, in frame: WKFrameInfo? = nil) async -> String {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script, in: frame, in: .page) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: (value as? String) ?? "")
                case .failure(let error):
                    continuation.resume(returning: "js error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        frameRegistry.reset()
        panelRoutes = [:]
        syncState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        syncState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        syncState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        syncState()
    }

    private func syncState() {
        currentURLString = webView.url?.absoluteString ?? ""
        pageTitle = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}
