import SwiftUI

/// Manual browsing controls: back/forward, editable URL field, reload, loading line.
struct BrowserToolbar: View {
    @Environment(AgentViewModel.self) private var agent
    @State private var urlDraft = ""
    @FocusState private var urlFocused: Bool

    var body: some View {
        let proxy = agent.webProxy
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                navButton("chevron.left", enabled: proxy.canGoBack) { proxy.goBack() }
                navButton("chevron.right", enabled: proxy.canGoForward) { proxy.goForward() }

                HStack(spacing: 6) {
                    Image(systemName: urlDraft.hasPrefix("https") ? "lock.fill" : "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Search or enter URL", text: $urlDraft)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($urlFocused)
                        .onSubmit {
                            proxy.load(urlDraft)
                            urlFocused = false
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surface, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(urlFocused ? Theme.cyan.opacity(0.5) : Theme.line, lineWidth: 1)
                )

                navButton(proxy.isLoading ? "xmark" : "arrow.clockwise", enabled: true) {
                    if proxy.isLoading {
                        proxy.stopLoading()
                    } else {
                        proxy.reload()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ZStack {
                Rectangle().fill(Theme.line).frame(height: 1)
                if proxy.isLoading {
                    LoadingLine()
                }
            }
            .frame(height: 2)
        }
        .onChange(of: proxy.currentURLString) { _, newValue in
            if !urlFocused {
                urlDraft = newValue
            }
        }
        .onAppear {
            urlDraft = proxy.currentURLString
        }
    }

    private func navButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary.opacity(0.4))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
    }
}
