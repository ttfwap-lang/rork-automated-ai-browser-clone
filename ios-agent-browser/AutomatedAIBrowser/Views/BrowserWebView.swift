import SwiftUI
import WebKit

/// Hosts the shared WKWebView owned by WebViewProxy.
struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
