import WebKit

/// Collects a handle (WKFrameInfo) for every embedded panel (iframe) as pages
/// load, via a tiny hello message posted from each subframe. Handles get
/// matched to visible iframes at scan time so the agent can look and act
/// inside panels. Fails soft: unmatched panels stay single tappable regions.
final class FrameRegistry: NSObject, WKScriptMessageHandler {

    struct Panel {
        let frame: WKFrameInfo
        let urlString: String
        let host: String
    }

    static let messageName = "rorkFrames"

    /// Injected into every subframe (not the main frame) at document end.
    static let helloScript = "try { if (window.top !== window.self && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rorkFrames) { window.webkit.messageHandlers.rorkFrames.postMessage({ href: String(location.href || '') }); } } catch (e) {}"

    private(set) var panels: [Panel] = []

    func reset() {
        panels.removeAll()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageName else { return }
        let frameInfo = message.frameInfo
        guard !frameInfo.isMainFrame else { return }
        let posted = (message.body as? [String: Any])?["href"] as? String
        let urlString = (posted?.isEmpty == false ? posted : frameInfo.request.url?.absoluteString) ?? ""
        guard !urlString.isEmpty, urlString != "about:blank" else { return }
        panels.removeAll { $0.urlString == urlString }
        panels.append(Panel(
            frame: frameInfo,
            urlString: urlString,
            host: URL(string: urlString)?.host ?? "embedded"
        ))
        if panels.count > 24 {
            panels.removeFirst(panels.count - 24)
        }
    }

    /// Best-effort match of a visible iframe's src to a registered panel:
    /// exact URL, then host + path, then host, then single-candidate fallback.
    func match(src: String, excluding used: Set<String>) -> Panel? {
        let available = panels.filter { !used.contains($0.urlString) }
        guard !available.isEmpty else { return nil }
        if !src.isEmpty {
            if let exact = available.first(where: { $0.urlString == src }) { return exact }
            if let srcURL = URL(string: src), let srcHost = srcURL.host {
                if let hostPath = available.first(where: { panel in
                    guard let url = URL(string: panel.urlString) else { return false }
                    return url.host == srcHost && url.path == srcURL.path
                }) {
                    return hostPath
                }
                if let hostOnly = available.first(where: { URL(string: $0.urlString)?.host == srcHost }) {
                    return hostOnly
                }
            }
        }
        return available.count == 1 ? available.first : nil
    }
}
