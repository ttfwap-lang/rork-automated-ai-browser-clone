import SwiftUI

/// Full-page viewer that displays the complete web page content
/// Uses the real WebView service for actual browser rendering
public final class FullPageView: ObservableObject {
    /// The underlying WebView service that renders the page
    private let webView: WebView
    
    /// The URL being displayed
    private let url: URL
    
    /// Whether the view is currently displaying content
    private var isDisplaying: Bool = false
    
    /// Load the full page content
    public func display() {
        isDisplaying = true
        webView.url = url
        webView.load(url: url)
    }
    
    /// Hide the full page view
    public func hide() {
        isDisplaying = false
    }
    
    /// Get the current URL being displayed
    public var currentURL: URL {
        return url
    }
}

// MARK: - SwiftUI View
@main
struct FullPageViewView: View {
    /// Display the full page content
    var body: some View {
        VStack {
            Spacer()
            
            // The WebView will render the full page here
            WebViewView()
                .frame(height: .infinity)
                .background(Color.black.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
        }
        .onAppear {
            display()
        }
        .onDisappear {
            hide()
        }
    }
}

/// Custom WebView representation for SwiftUI
/// Renders the WKWebView inside a SwiftUI view
private struct WebViewView: UIViewRepresentable {
    let webView: WebView
    let url: URL
    
    func makeUIViewPresentation() -> SomeUIView {
        let container = ZStack {
            WebView()
                .frame(width: bounds.width, height: bounds.height)
                .ignoresSafeArea()
        }
        return container
    }
    
    func updateUIView(_ uiView: SomeUIView, context: Context) {
        // The WebView inside handles the actual rendering
        // No additional updates needed
    }
}
