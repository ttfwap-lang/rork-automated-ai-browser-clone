import SwiftUI

/// Main cockpit: browser viewport with agent telemetry, command bar, and modal surfaces.
struct ContentView: View {
    @Environment(AgentViewModel.self) private var agent
    @Environment(RoutineStore.self) private var routines
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showMemory = false

    var body: some View {
        @Bindable var agent = agent
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(
                    onMemory: { presentAuxiliary { showMemory = true } },
                    onHistory: { presentAuxiliary { showHistory = true } },
                    onSettings: { presentAuxiliary { showSettings = true } }
                )
                BrowserToolbar()
                browserArea
                bottomDock
            }
        }
        .sheet(isPresented: $agent.isFeedPresented) {
            ActionFeedSheet()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showMemory) {
            MemoryView()
        }
        .onAppear {
            agent.loadHomepageIfNeeded()
        }
    }

    private var browserArea: some View {
        ZStack {
            BrowserWebView(webView: agent.webProxy.webView)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
            ScanningBorder(active: agent.isRunning && agent.isScanningVisual, cornerRadius: 18)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        // Sits over the page rather than beside it, so watching the site and
        // following the reasoning are the same act. Only the panel's own frame
        // takes taps — everything around it lands on the page.
        .overlay(alignment: .top) {
            if agent.isRunning {
                LiveThinkingPanel()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: agent.isRunning)
    }

    private var bottomDock: some View {
        VStack(spacing: 0) {
            if let banner = agent.outcomeBanner, !agent.isRunning {
                OutcomeBannerView(banner: banner)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if agent.pendingStep != nil {
                ApprovalControls()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if agent.isRunning {
                MissionProgressLine()
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                StatusStrip()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !agent.isRunning, !routines.isEmpty {
                RoutineStrip()
                    .padding(.top, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            CommandBar()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: agent.isRunning)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: agent.outcomeBanner)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: agent.pendingStep?.id)
    }

    /// Dismisses the mission log first so a second sheet can present cleanly.
    private func presentAuxiliary(_ present: @escaping () -> Void) {
        if agent.isFeedPresented {
            agent.isFeedPresented = false
            Task {
                try? await Task.sleep(for: .milliseconds(420))
                present()
            }
        } else {
            present()
        }
    }
}
