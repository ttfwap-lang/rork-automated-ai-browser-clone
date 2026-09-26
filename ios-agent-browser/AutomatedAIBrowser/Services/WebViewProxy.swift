import WebKit
import Observation

/// Owns the WKWebView and gives the agent full control of it:
/// snapshots, synthetic taps (with a glowing ripple), typing, scrolling, and
/// navigation. Pro hands (form moves, gestures, whole-page sight, embedded
/// panel routing) live in WebViewProxy+ProHands.
@Observable
final class WebViewProxy: NSObject, WKNavigationDelegate, WKUIDelegate {
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

    /// Records when a JavaScript dialog appeared and was auto-dismissed,
    /// so the agent's step result can observe that the page asked something.
    private(set) var lastDialogNotice: String?

    func consumeLastDialogNotice() -> String? {
        defer { lastDialogNotice = nil }
        return lastDialogNotice
    }

    /// Records when a navigation was refused due to an unsupported scheme (e.g. mailto, tel),
    /// so the agent's step result can observe the refusal.
    private(set) var lastNavigationRefusal: String?

    func consumeLastNavigationRefusal() -> String? {
        defer { lastNavigationRefusal = nil }
        return lastNavigationRefusal
    }

    /// Callback invoked when WebKit's web content process terminates (jetsam or crash).
    var onWebContentProcessTerminated: (@MainActor () -> Void)?

    /// Records when WebKit's web content process terminated.
    private(set) var didContentProcessTerminate = false

    func consumeContentProcessTermination() -> Bool {
        defer { didContentProcessTerminate = false }
        return didContentProcessTerminate
    }

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
        webView.uiDelegate = self
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

    // MARK: - Bounded Async Helper

    /// Runs a WebKit async operation bounded by a timeout and task cancellation,
    /// guaranteeing exactly-once resumption via an internal NSLock.
    private func boundedAsync<T: Sendable>(
        timeout: TimeInterval,
        timeoutValue: T,
        cancelValue: T,
        operationName: String,
        start: @escaping (ContinuationGate<T>) -> Void
    ) async -> T {
        guard !Task.isCancelled else {
            webView.stopLoading()
            AppLog.webview.info("\(operationName, privacy: .public) cancelled before start")
            return cancelValue
        }

        let gateBox = GateBox<T>()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let gate = ContinuationGate(continuation)
                gateBox.set(gate)

                if Task.isCancelled {
                    _ = gate.resume(returning: cancelValue)
                    return
                }

                let timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled else { return }
                    if gate.resume(returning: timeoutValue) {
                        AppLog.webview.warning("\(operationName, privacy: .public) timed out after \(Int(timeout), privacy: .public)s")
                    }
                }
                gate.attachTimeoutTask(timeoutTask)

                start(gate)
            }
        } onCancel: {
            if let gate = gateBox.get() {
                if gate.resume(returning: cancelValue) {
                    AppLog.webview.info("\(operationName, privacy: .public) cancelled during execution")
                }
            }
            Task { @MainActor [weak self] in
                self?.webView.stopLoading()
                AppLog.webview.info("\(operationName, privacy: .public) cancellation: webView.stopLoading() called")
            }
        }
    }

    // MARK: - Snapshot

    /// Captures the visible viewport, already downscaled for AI input.
    /// Bounded by a 5-second timeout and cancellable.
    func snapshot(width: Double = 700) async -> UIImage? {
        guard webView.bounds.width > 0, webView.bounds.height > 0 else { return nil }
        return await boundedAsync(
            timeout: 5,
            timeoutValue: nil,
            cancelValue: nil,
            operationName: "snapshot"
        ) { [weak self] gate in
            guard let self else {
                gate.resume(returning: nil)
                return
            }
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = NSNumber(value: width)
            self.webView.takeSnapshot(with: config) { image, _ in
                gate.resume(returning: image)
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
            AppLog.webview.warning("Page scan unavailable: \(String(raw.prefix(120)), privacy: .private)")
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

    /// Absolute links currently rendered in the main document, bounded and
    /// de-duplicated by the page script. This is the local half of Crawl4AI's
    /// breadth-first discovery workflow; the remote crawler does the fetching.
    func discoverLinks(limit: Int = 30, sameOrigin: Bool = true) async -> [String] {
        let raw = await runJS(PageReader.linkDiscoveryScript(maxCount: limit, sameOrigin: sameOrigin))
        guard let data = raw.data(using: .utf8),
              let links = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Array(links.prefix(min(max(limit, 1), 100)))
    }

    // MARK: - JS plumbing

    /// Runs a script in the main frame or, when `frame` is given, inside that
    /// embedded panel. All agent scripts return strings; JS errors come back
    /// as readable "js error: …" lines so callers can fail soft.
    /// Bounded by a 10-second timeout and cancellable.
    func runJS(_ script: String, in frame: WKFrameInfo? = nil) async -> String {
        await boundedAsync(
            timeout: 10,
            // NOTE (C-1, Stage 1b.2): Timeout returns "js error: timed out" as a prose sentinel
            // which ReactionWatch.readsAsFailure already catches. Stage 1b.2 introduces MoveOutcome.scriptTimedOut.
            timeoutValue: "js error: timed out",
            cancelValue: "js error: cancelled",
            operationName: "runJS"
        ) { [weak self] gate in
            guard let self else {
                gate.resume(returning: "js error: web view deallocated")
                return
            }
            self.webView.evaluateJavaScript(script, in: frame, in: .page) { result in
                let outcome: String
                switch result {
                case .success(let value):
                    outcome = (value as? String) ?? ""
                case .failure(let error):
                    outcome = "js error: \(error.localizedDescription)"
                }
                gate.resume(returning: outcome)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let url = AppLog.sanitize(url: webView.url)
        AppLog.webview.info("Navigation started: \(url, privacy: .private)")
        isLoading = true
        frameRegistry.reset()
        panelRoutes = [:]
        syncState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let url = AppLog.sanitize(url: webView.url)
        AppLog.webview.info("Navigation committed: \(url, privacy: .private)")
        syncState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = AppLog.sanitize(url: webView.url)
        AppLog.webview.info("Navigation finished: \(url, privacy: .private)")
        isLoading = false
        syncState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let url = AppLog.sanitize(url: webView.url)
        AppLog.webview.error("Navigation failed: \(url, privacy: .private), error=\(error.localizedDescription, privacy: .private)")
        isLoading = false
        syncState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let url = AppLog.sanitize(url: webView.url)
        AppLog.webview.error("Provisional navigation failed: \(url, privacy: .private), error=\(error.localizedDescription, privacy: .private)")
        isLoading = false
        syncState()
    }

    /// Invoked when WebKit's web content process terminates (jetsam under memory pressure or a crash).
    /// To recover, we log the event, mark state, notify the agent, and reload the last known URL.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let url = AppLog.sanitize(url: webView.url)
        AppLog.webview.error("Web content process terminated (jetsam/crash): \(url, privacy: .private)")
        didContentProcessTerminate = true
        onWebContentProcessTerminated?()

        if let currentURL = webView.url {
            webView.load(URLRequest(url: currentURL))
        } else if !currentURLString.isEmpty, let target = URL(string: currentURLString) {
            webView.load(URLRequest(url: target))
        } else {
            webView.reload()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        let allowedSchemes: Set<String> = ["http", "https", "about"]

        if allowedSchemes.contains(scheme) || scheme.isEmpty {
            AppLog.webview.info("Navigation policy allowed: \(AppLog.sanitize(url: url), privacy: .private)")
            decisionHandler(.allow)
        } else {
            let refusal = "refused non-web address (\(scheme):) — unsupported scheme"
            lastNavigationRefusal = refusal
            AppLog.webview.warning("Navigation policy refused unsupported scheme '\(scheme, privacy: .public)': \(AppLog.sanitize(url: url), privacy: .private)")
            decisionHandler(.cancel)
        }
    }

    // MARK: - WKUIDelegate

    /// Intercepts target="_blank" and window.open() links. WebKit defaults to dropping
    /// these if unhandled. We redirect the request into the existing web view so the
    /// agent continues seamlessly on the same tab.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            let url = AppLog.sanitize(url: navigationAction.request.url)
            AppLog.webview.info("Popup intercepted (target=_blank): loading in existing view: \(url, privacy: .private)")
            webView.load(navigationAction.request)
        }
        return nil
    }

    /// Auto-dismisses JavaScript alerts so modal dialogs do not stall the agent loop.
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        lastDialogNotice = "alert \"\(message)\" dismissed"
        AppLog.webview.info("JavaScript alert auto-dismissed: message=\(message, privacy: .private)")
        completionHandler()
    }

    /// Auto-confirms JavaScript confirmation dialogs so the agent loop proceeds.
    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        lastDialogNotice = "confirm \"\(message)\" confirmed"
        AppLog.webview.info("JavaScript confirm auto-confirmed: message=\(message, privacy: .private)")
        completionHandler(true)
    }

    /// Auto-answers JavaScript text input prompts with the page's default text.
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let answer = defaultText ?? ""
        lastDialogNotice = "prompt \"\(prompt)\" answered with \"\(answer)\""
        AppLog.webview.info("JavaScript prompt auto-answered: prompt=\(prompt, privacy: .private)")
        completionHandler(defaultText)
    }

    private func syncState() {
        currentURLString = webView.url?.absoluteString ?? ""
        pageTitle = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

// MARK: - Continuation Helpers

/// Thread-safe gate ensuring a CheckedContinuation is resumed at most once
/// across success, timeout, and cancellation paths.
final class ContinuationGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func attachTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        if continuation == nil {
            task.cancel()
        } else {
            timeoutTask = task
        }
    }

    @discardableResult
    func resume(returning value: T) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let cont = continuation else { return false }
        continuation = nil
        cont.resume(returning: value)
        return true
    }
}

private final class GateBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var gate: ContinuationGate<T>?

    func set(_ gate: ContinuationGate<T>) {
        lock.lock()
        defer { lock.unlock() }
        self.gate = gate
    }

    func get() -> ContinuationGate<T>? {
        lock.lock()
        defer { lock.unlock() }
        return gate
    }
}

