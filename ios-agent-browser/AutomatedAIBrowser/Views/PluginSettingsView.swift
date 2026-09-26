import SwiftUI
import Foundation

/// Configuration and status for the optional BrowserAct and Crawl4AI adapters.
/// Secrets are editable only here and are never written to UserDefaults, run
/// history, prompts, logs, recipes, or routines.
struct PluginSettingsView: View {
    @Environment(PluginManager.self) private var plugins
    @State private var browserActKey = ""
    @State private var crawl4AIKey = ""
    @State private var browserActTest = ""
    @State private var crawl4AITest = ""
    @State private var browserActTesting = false
    @State private var crawl4AITesting = false

    var body: some View {
        Form {
            browserActSection(plugins: plugins)
            crawl4AISection(plugins: plugins)
            artifactsSection
            safetySection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("External Plugins")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            plugins.refreshCredentialState()
            browserActKey = plugins.browserActAPIKeyForEditing()
            crawl4AIKey = plugins.crawl4AIAPIKeyForEditing()
        }
        .onDisappear {
            browserActKey = ""
            crawl4AIKey = ""
        }
    }

    private func browserActSection(plugins: PluginManager) -> some View {
        @Bindable var plugins = plugins
        return Section {
            Toggle("Enable BrowserAct", isOn: $plugins.browserActEnabled)
            SecureField("API key", text: $browserActKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Save Key") { plugins.saveBrowserActAPIKey(browserActKey) }
                    .disabled(browserActKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Text(plugins.hasBrowserActAPIKey ? "KEYCHAIN ✓" : "NO KEY")
                    .techLabel(9)
                    .foregroundStyle(plugins.hasBrowserActAPIKey ? Theme.green : Theme.textSecondary)
            }
            if plugins.hasBrowserActAPIKey {
                Button("Remove Saved Key", role: .destructive) {
                    browserActKey = ""
                    plugins.removeBrowserActAPIKey()
                }
            }

            TextField("Default Bot ID (optional)", text: $plugins.browserActBotID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Official template ID (optional)", text: $plugins.browserActTemplateID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Template proxy region (optional)", text: $plugins.browserActProxyRegion)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Target URL input key", text: $plugins.browserActTargetParameter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Stepper(
                "Wait for a new task: \(plugins.browserActWaitSeconds)s",
                value: $plugins.browserActWaitSeconds,
                in: 0...60,
                step: 5
            )

            Button {
                browserActTesting = true
                browserActTest = ""
                Task {
                    browserActTest = await plugins.testBrowserAct()
                    browserActTesting = false
                }
            } label: {
                Label(browserActTesting ? "Testing…" : "Test Connection", systemImage: "network")
            }
            .disabled(browserActTesting || !plugins.hasBrowserActAPIKey)
            if !browserActTest.isEmpty {
                Text(browserActTest)
                    .font(.system(size: 12))
                    .foregroundStyle(browserActTest.hasPrefix("Connected") ? Theme.green : Theme.amber)
            }
        } header: {
            Label("BrowserAct", systemImage: BrowserPluginID.browserAct.symbol)
        } footer: {
            Text("Runs published Bots or official templates in BrowserAct's remote browser through the current v3 API. Supports Bot/template schema discovery, task start and wait, status/detail, resume/cancel, task filtering, and proxy regions. The current page URL is supplied under the input key configured below unless your input list already defines it. Keep passwords and tokens in BrowserAct's hosted Bot credential configuration; the plugin refuses credential-shaped inputs.")
        }
    }

    private func crawl4AISection(plugins: PluginManager) -> some View {
        @Bindable var plugins = plugins
        return Section {
            Toggle("Enable Crawl4AI", isOn: $plugins.crawl4AIEnabled)
            Picker("Service", selection: $plugins.crawl4AIServiceKind) {
                ForEach(Crawl4AIServiceKind.allCases) { kind in
                    Text(kind.name).tag(kind)
                }
            }
            .onChange(of: plugins.crawl4AIServiceKind) { _, _ in
                crawl4AIKey = plugins.crawl4AIAPIKeyForEditing()
                crawl4AITest = ""
            }
            TextField(
                plugins.crawl4AIServiceKind == .cloud ? "Cloud API URL" : "HTTPS server URL",
                text: Binding(
                    get: {
                        plugins.crawl4AIServiceKind == .cloud
                            ? "https://api.crawl4ai.com"
                            : plugins.crawl4AIBaseURL
                    },
                    set: { newValue in
                        if plugins.crawl4AIServiceKind == .server {
                            plugins.crawl4AIBaseURL = newValue
                        }
                    }
                )
            )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(plugins.crawl4AIServiceKind == .cloud)
            SecureField(plugins.crawl4AIServiceKind == .cloud ? "Cloud API token" : "Server API token", text: $crawl4AIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Save Token") { plugins.saveCrawl4AIAPIKey(crawl4AIKey) }
                    .disabled(crawl4AIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Text(plugins.hasCrawl4AIAPIKey ? "KEYCHAIN ✓" : "NO TOKEN")
                    .techLabel(9)
                    .foregroundStyle(plugins.hasCrawl4AIAPIKey ? Theme.green : Theme.textSecondary)
            }
            if plugins.hasCrawl4AIAPIKey {
                Button("Remove Saved Token", role: .destructive) {
                    crawl4AIKey = ""
                    plugins.removeCrawl4AIAPIKey()
                }
            }
            Stepper(
                "Shared plugin output cap: \(plugins.crawl4AIOutputLimit / 1_000)k characters",
                value: $plugins.crawl4AIOutputLimit,
                in: 6_000...60_000,
                step: 2_000
            )
            Stepper(
                "Screenshot wait: \(String(format: "%.1f", plugins.crawl4AIScreenshotWait))s",
                value: $plugins.crawl4AIScreenshotWait,
                in: 0...10,
                step: 0.5
            )

            Button {
                crawl4AITesting = true
                crawl4AITest = ""
                Task {
                    crawl4AITest = await plugins.testCrawl4AI()
                    crawl4AITesting = false
                }
            } label: {
                Label(crawl4AITesting ? "Testing…" : "Test Connection", systemImage: "network")
            }
            .disabled(
                crawl4AITesting
                    || !plugins.hasCrawl4AIAPIKey
                    || (plugins.crawl4AIServiceKind == .server && plugins.crawl4AIBaseURL.isEmpty)
            )
            if !crawl4AITest.isEmpty {
                Text(crawl4AITest)
                    .font(.system(size: 12))
                    .foregroundStyle(crawl4AITest.hasPrefix("Connected") ? Theme.green : Theme.amber)
            }
        } header: {
            Label("Crawl4AI", systemImage: BrowserPluginID.crawl4AI.symbol)
        } footer: {
            Text(plugins.crawl4AIServiceKind == .cloud
                 ? "Crawl4AI Cloud adds scrape, structured extraction, web search, direct answers, streamed batches, asynchronous jobs, recipes, balance, and cost estimates. Cloud requests/results may be retained under the provider's current policy; residential proxy and country selection are available but always require approval."
                 : "A self-hosted Crawl4AI server supports Docker/MCP Markdown, sanitized HTML, batch/stream/jobs, local rendered-link discovery, server configs, screenshots, PDFs, optional JavaScript, page Q&A, schemas/hooks, and health. The HTTPS address is trusted user configuration, so point it only at a server you control (a private reverse proxy is fine). Hardened v0.9 servers deliberately reject some dynamic crawler settings, JavaScript, and hooks.")
        }
    }

    @ViewBuilder
    private var artifactsSection: some View {
        Section {
            if plugins.artifacts.isEmpty {
                Text("No plugin artifacts yet")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(plugins.artifacts) { artifact in
                    HStack(spacing: 10) {
                        Image(systemName: artifact.mimeType.hasPrefix("image/") ? "photo" : "doc.richtext")
                            .foregroundStyle(Theme.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(artifact.fileName)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text("\(artifact.operation) · \(ByteCountFormatter.string(fromByteCount: Int64(artifact.byteCount), countStyle: .file))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if let url = plugins.artifactURL(for: artifact) {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                        Button(role: .destructive) {
                            plugins.deleteArtifact(artifact)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                Button("Delete All Plugin Artifacts", role: .destructive) {
                    plugins.clearArtifacts()
                }
            }
        } header: {
            Text("Saved Artifacts")
        } footer: {
            Text("Crawl4AI screenshots/PDFs and BrowserAct output files are downloaded immediately, before temporary URLs can expire. The BrowserAct CDN fetch never receives your BrowserAct API key, refuses private destinations, and does not follow redirects. Up to 30 files and 200 MB total are kept in the app's protected Documents directory for export or preview.")
        }
    }

    private var safetySection: some View {
        Section {
            Label("Every model-requested external call waits for your approval", systemImage: "hand.raised.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.amber)
            if let note = plugins.credentialNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red)
            }
        } header: {
            Text("Privacy & Safety")
        } footer: {
            Text("Before any call, the approval card names the provider, service, and destinations. Its collapsed disclosure shows the complete bounded request arguments so you can inspect full destination queries, input values, scripts, configuration, and injected defaults locally; requests over the app's combined size limit are refused, and none of that preview is written to history or logs. Credential-shaped fields and signed URLs are rejected before upload. Cloud and self-hosted Crawl4AI tokens are stored separately, so a Cloud key is never sent to a self-hosted server. Remote output is treated as untrusted page data, stripped of large binary payloads, live-session/download URLs, cookies/headers, and URL query values, capped, and supplied to the agent for one turn. Plugin calls are never learned into local one-tap replays. Removing a key disables its plugin immediately.")
        }
    }
}
