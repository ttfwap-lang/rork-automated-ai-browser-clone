import UIKit
import WebKit

/// Checkpoints: reading the exact scroll position so a point in the mission can
/// be captured, and sending the browser back there later.
///
/// A checkpoint restores the page, not text already typed into a form, and a site
/// that has moved the session on may come back different — which is reported
/// honestly rather than presented as a clean rewind.
extension WebViewProxy {

    enum RestoreOutcome {
        /// Landed exactly where the checkpoint was taken.
        case restored(note: String)
        /// Came back, but not the same page — the agent is told plainly.
        case changed(note: String)
        case failed(why: String)
    }

    /// Current vertical scroll offset in CSS pixels.
    func scrollPosition() async -> Double {
        let raw = await runJS("(function(){ try { return String(Math.round(window.pageYOffset || document.documentElement.scrollTop || 0)); } catch (e) { return '0'; } })()")
        return Double(raw.trimmed) ?? 0
    }

    /// A short, plain label for the page currently on screen.
    func checkpointLabel() async -> String {
        let title = (webView.title ?? "").trimmed
        if !title.isEmpty { return String(title.prefix(48)) }
        guard let host = webView.url?.host else { return "this page" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// Sends the browser back to a checkpoint, preferring the real history entry
    /// so the back/forward trail survives.
    func restore(_ bookmark: PageBookmark) async -> RestoreOutcome {
        guard let target = URL(string: bookmark.urlString) else {
            return .failed(why: "that checkpoint has no usable address")
        }

        let trail = webView.backForwardList.backList + webView.backForwardList.forwardList
        if let entry = trail.last(where: { $0.url.absoluteString == bookmark.urlString }) {
            webView.go(to: entry)
        } else {
            webView.load(URLRequest(url: target))
        }

        await waitForQuiet(maxWait: 10)
        guard !Task.isCancelled else { return .failed(why: "the run was stopped mid-rewind") }

        let landed = webView.url?.absoluteString ?? ""
        guard !landed.isEmpty else {
            return .failed(why: "the page didn't come back")
        }

        if bookmark.scrollY > 1 {
            _ = await runJS("(function(){ try { window.scrollTo(0, \(Int(bookmark.scrollY))); return 'ok'; } catch (e) { return 'no'; } })()")
            try? await Task.sleep(for: .milliseconds(350))
        }

        if landed != bookmark.urlString {
            return .changed(note: "landed on \(landed) instead of the checkpoint — this page may have moved on, so read it fresh")
        }
        return .restored(note: "back at \(bookmark.label)")
    }
}
