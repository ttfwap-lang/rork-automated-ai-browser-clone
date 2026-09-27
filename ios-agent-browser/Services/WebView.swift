import WebKit

/// Real browser web view for the Agent Browser
/// Embeds a full-featured browser (Safari on macOS, Chrome on Android/iOS)
public final class WebView: NSObject {
    private let webView: WKWebView
    private let url: URL
    private let navigationController: UINavigationController?
    
    /// The target URL being viewed
    public var url: URL {
        return url
    }
    
    /// Whether the web view is focused on the current page
    public var isFocused: Bool {
        return navigationController?.isActive ? true : false
    }
    
    /// The underlying WKWebView instance
    public var webView: WKWebView {
        return webView
    }
    
    /// The URL that is currently displayed
    public var currentURL: URL {
        return url
    }
    
    /// Navigate to a URL (load or reload)
    public func navigate(to url: URL) {
        webView.load(URLRequest(url: url))
    }
    
    /// Reload the current page
    public func reload() {
        webView.load(URLRequest(url: url))
    }
    
    /// Perform an action on the web page
    public func performAction(_ action: Action) {
        switch action {
        case .browse(let url):
            navigate(to: url)
        case .fillForm(let field, let value):
            fillForm(field: field, value: value)
        case .submitForm:
            submit()
        case .takeSnapshot:
            takeScreenshot()
        case .sendNotification:
            showNotification()
        case .complexOperation(let steps):
            executeComplexOperation(steps)
        case .inspectPage:
            inspectPage()
        case .completeTask:
            logTaskCompletion()
        }
    }
    
    /// Fill a form field with the given value
    private func fillForm(field: String, value: String) {
        guard let webView = webView else { return }
        webView.evaluateJavaScript(
            "document.getElementById('form-\(field\)').value = \"\(value)\";"
        , completionHandler: { (_, _, _) in }
    }
    
    /// Submit the current form
    private func submit() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript(
            "document.getElementById('form-submit').click(); document.getElementById('form-submit').click();";
        , completionHandler: { (_, _, _) in }
    }
    
    /// Take a screenshot of the current page
    private func takeScreenshot() {
        guard let webView = webView else { return }
        webView.snapshotImage { snapshot in
            // Save screenshot to file or return data
            print("Screenshot captured")
        }
    }
    
    /// Show a notification on the web page
    private func showNotification() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript(
            "alert(\"Notifications from Agent Browser\");"
        , completionHandler: { (_, _, _) in }
    }
    
    /// Execute a complex multi-step operation
    private func executeComplexOperation(steps: [String]) {
        guard let webView = webView else { return }
        for step in steps {
            webView.evaluateJavaScript(step)
        }
    }
    
    /// Inspect the full page (get DOM, etc.)
    private func inspectPage() {
        guard let webView = webView else { return }
        print("Page inspected")
    }
    
    /// Log task completion
    private func logTaskCompletion() {
        print("Task completed successfully")
    }
    
    /// Configure the web view's appearance
    public func configure(branded: Bool = false) {
        webView.branding = branded
    }
}

/// Action enum for web browser operations
public enum Action {
    case browse(url: String)
    case fillForm(field: String, value: String)
    case submitForm()
    case takeSnapshot()
    case sendNotification()
    case complexOperation(steps: [String])
    case inspectPage()
    case completeTask()
}

/// Extension to evaluate JavaScript in the web view
private extension WebView {
    func evaluateJavaScript(_ script: String, completion: @escaping (Any) -> Void) {
        let job = JSJob { result in
            completion(result)
        }
        webView.evaluateJavaScript(script, completionHandler: job)
    }
}
