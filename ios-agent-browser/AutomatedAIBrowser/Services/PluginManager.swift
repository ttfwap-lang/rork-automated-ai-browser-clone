import Foundation
import Observation

/// Owns optional external-plugin configuration and executes one approved plugin
/// call at a time. Non-secret settings live in UserDefaults; API credentials live
/// only in the Keychain. The model never receives a credential.
@Observable
final class PluginManager {
    var browserActEnabled: Bool {
        didSet { defaults.set(browserActEnabled, forKey: Keys.browserActEnabled) }
    }

    var browserActBotID: String {
        didSet { defaults.set(browserActBotID, forKey: Keys.browserActBotID) }
    }

    var browserActTemplateID: String {
        didSet { defaults.set(browserActTemplateID, forKey: Keys.browserActTemplateID) }
    }

    var browserActProxyRegion: String {
        didSet { defaults.set(browserActProxyRegion, forKey: Keys.browserActProxyRegion) }
    }

    var browserActTargetParameter: String {
        didSet { defaults.set(browserActTargetParameter, forKey: Keys.browserActTargetParameter) }
    }

    var browserActWaitSeconds: Int {
        didSet { defaults.set(browserActWaitSeconds, forKey: Keys.browserActWaitSeconds) }
    }

    var crawl4AIEnabled: Bool {
        didSet { defaults.set(crawl4AIEnabled, forKey: Keys.crawl4AIEnabled) }
    }

    var crawl4AIServiceKind: Crawl4AIServiceKind {
        didSet {
            defaults.set(crawl4AIServiceKind.rawValue, forKey: Keys.crawl4AIServiceKind)
            refreshCredentialState()
        }
    }

    var crawl4AIBaseURL: String {
        didSet { defaults.set(crawl4AIBaseURL, forKey: Keys.crawl4AIBaseURL) }
    }

    var crawl4AIOutputLimit: Int {
        didSet { defaults.set(crawl4AIOutputLimit, forKey: Keys.crawl4AIOutputLimit) }
    }

    var crawl4AIScreenshotWait: Double {
        didSet { defaults.set(crawl4AIScreenshotWait, forKey: Keys.crawl4AIScreenshotWait) }
    }

    private(set) var hasBrowserActAPIKey = false
    private(set) var hasCrawl4AIAPIKey = false
    private(set) var credentialNote: String?
    /// Screenshots and PDFs already fetched from short-lived remote artifact
    /// stores. Bytes are kept in Documents so they do not expire before use.
    private(set) var artifacts: [PluginArtifactRecord] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let credentials: PluginCredentialStore
    @ObservationIgnored private let client: PluginAPIClient
    @ObservationIgnored private let artifactDirectory: URL

    private static let maximumArtifactCount = 30
    private static let maximumArtifactBytes = 200_000_000
    private static let maximumRequestCharacters = 1_000_000

    private enum Keys {
        static let browserActEnabled = "plugins.browserAct.enabled"
        static let browserActBotID = "plugins.browserAct.botID"
        static let browserActTemplateID = "plugins.browserAct.templateID"
        static let browserActProxyRegion = "plugins.browserAct.proxyRegion"
        static let browserActTargetParameter = "plugins.browserAct.targetParameter"
        static let browserActWaitSeconds = "plugins.browserAct.waitSeconds"
        static let crawl4AIEnabled = "plugins.crawl4AI.enabled"
        static let crawl4AIServiceKind = "plugins.crawl4AI.serviceKind"
        static let crawl4AIBaseURL = "plugins.crawl4AI.baseURL"
        static let crawl4AIOutputLimit = "plugins.crawl4AI.outputLimit"
        static let crawl4AIScreenshotWait = "plugins.crawl4AI.screenshotWait"
        static let artifacts = "plugins.artifacts.v1"
    }

    init(
        defaults: UserDefaults = .standard,
        credentials: PluginCredentialStore? = nil,
        client: PluginAPIClient? = nil
    ) {
        self.defaults = defaults
        self.credentials = credentials ?? PluginCredentialStore()
        self.client = client ?? PluginAPIClient()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.artifactDirectory = documents.appendingPathComponent("PluginArtifacts", isDirectory: true)

        browserActEnabled = defaults.bool(forKey: Keys.browserActEnabled)
        browserActBotID = defaults.string(forKey: Keys.browserActBotID) ?? ""
        browserActTemplateID = defaults.string(forKey: Keys.browserActTemplateID) ?? ""
        browserActProxyRegion = defaults.string(forKey: Keys.browserActProxyRegion) ?? ""
        browserActTargetParameter = defaults.string(forKey: Keys.browserActTargetParameter) ?? "url"
        let storedWait = defaults.object(forKey: Keys.browserActWaitSeconds) == nil
            ? 45
            : defaults.integer(forKey: Keys.browserActWaitSeconds)
        browserActWaitSeconds = min(max(storedWait, 0), 60)

        crawl4AIEnabled = defaults.bool(forKey: Keys.crawl4AIEnabled)
        crawl4AIServiceKind = Crawl4AIServiceKind(
            rawValue: defaults.string(forKey: Keys.crawl4AIServiceKind) ?? ""
        ) ?? .server
        let storedBaseURL = defaults.string(forKey: Keys.crawl4AIBaseURL) ?? ""
        // Keep the self-hosted endpoint in its own setting slot. Cloud is
        // deliberately a fixed effective origin, so switching service kinds
        // must not overwrite a server URL the user may want to restore.
        crawl4AIBaseURL = storedBaseURL == "https://api.crawl4ai.com" ? "" : storedBaseURL
        let storedOutputLimit = defaults.object(forKey: Keys.crawl4AIOutputLimit) == nil
            ? 18_000
            : defaults.integer(forKey: Keys.crawl4AIOutputLimit)
        crawl4AIOutputLimit = min(max(storedOutputLimit, 6_000), 60_000)
        let storedScreenshotWait = (defaults.object(forKey: Keys.crawl4AIScreenshotWait) as? NSNumber)?.doubleValue ?? 2
        crawl4AIScreenshotWait = min(max(storedScreenshotWait, 0), 10)

        refreshCredentialState()
        loadArtifacts()
    }

    private var effectiveCrawl4AIBaseURL: String {
        crawl4AIServiceKind == .cloud ? "https://api.crawl4ai.com" : crawl4AIBaseURL
    }

    private var crawl4AICredentialAccount: PluginCredentialStore.Account {
        crawl4AIServiceKind == .cloud ? .crawl4AICloud : .crawl4AIServer
    }

    private func executionServiceKind(for action: AgentAction) -> Crawl4AIServiceKind {
        action.approvalServiceKind
            .flatMap(Crawl4AIServiceKind.init(rawValue:))
            ?? crawl4AIServiceKind
    }

    private func executionCredentialAccount(for action: AgentAction) -> PluginCredentialStore.Account {
        executionServiceKind(for: action) == .cloud ? .crawl4AICloud : .crawl4AIServer
    }

    var enabledPluginCount: Int { availablePluginIDs.count }

    var availablePluginIDs: [String] {
        var ids: [String] = []
        if browserActEnabled && hasBrowserActAPIKey {
            ids.append(BrowserPluginID.browserAct.rawValue)
        }
        if crawl4AIEnabled && hasCrawl4AIAPIKey && validServerURL(effectiveCrawl4AIBaseURL) != nil {
            ids.append(BrowserPluginID.crawl4AI.rawValue)
        }
        return ids
    }

    func approvalEndpoint(for plugin: BrowserPluginID) -> String {
        switch plugin {
        case .browserAct: "https://api.browseract.com"
        case .crawl4AI: effectiveCrawl4AIBaseURL
        }
    }

    func browserActAPIKeyForEditing() -> String {
        do { return try credentials.read(.browserAct) ?? "" } catch { return "" }
    }

    func crawl4AIAPIKeyForEditing() -> String {
        do { return try credentials.read(crawl4AICredentialAccount) ?? "" } catch { return "" }
    }

    func saveBrowserActAPIKey(_ raw: String) {
        saveCredential(raw, account: .browserAct)
    }

    func saveCrawl4AIAPIKey(_ raw: String) {
        saveCredential(raw, account: crawl4AICredentialAccount)
    }

    func removeBrowserActAPIKey() {
        removeCredential(.browserAct)
    }

    func removeCrawl4AIAPIKey() {
        removeCredential(crawl4AICredentialAccount)
    }

    func artifactURL(for record: PluginArtifactRecord) -> URL? {
        guard let url = safeArtifactURL(for: record) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        return url
    }

    private func safeArtifactURL(for record: PluginArtifactRecord) -> URL? {
        let fileName = record.fileName
        guard !fileName.isEmpty,
              fileName.count <= 160,
              fileName.rangeOfCharacter(from: .controlCharacters) == nil,
              !fileName.contains("/"),
              !fileName.contains("\\"),
              fileName != ".",
              fileName != "..",
              fileName == URL(fileURLWithPath: fileName).lastPathComponent
        else { return nil }

        let root = artifactDirectory.standardizedFileURL
        let candidate = root.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPath),
              candidate.deletingLastPathComponent().standardizedFileURL == root
        else { return nil }

        // Textual containment is not enough if a stale/tampered record points at
        // a symlink. Resolve both sides before allowing a file to be shared or
        // removed through the artifact API.
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        guard resolvedCandidate.path.hasPrefix(resolvedRootPath) else { return nil }
        return candidate
    }

    func deleteArtifact(_ record: PluginArtifactRecord) {
        if let url = artifactURL(for: record) { try? FileManager.default.removeItem(at: url) }
        artifacts.removeAll { $0.id == record.id }
        persistArtifacts()
    }

    func clearArtifacts() {
        for record in artifacts {
            if let url = artifactURL(for: record) { try? FileManager.default.removeItem(at: url) }
        }
        artifacts = []
        persistArtifacts()
    }

    func refreshCredentialState() {
        do {
            hasBrowserActAPIKey = try credentials.read(.browserAct) != nil
            hasCrawl4AIAPIKey = try credentials.read(crawl4AICredentialAccount) != nil
            if !hasBrowserActAPIKey && !hasCrawl4AIAPIKey { credentialNote = nil }
        } catch {
            hasBrowserActAPIKey = false
            hasCrawl4AIAPIKey = false
            credentialNote = error.localizedDescription
        }
    }

    func testBrowserAct() async -> String {
        do {
            guard let token = try credentials.read(.browserAct), !token.isEmpty else {
                return "Save a BrowserAct API key first."
            }
            let response = try await client.request(
                baseURL: "https://api.browseract.com",
                path: "/v3/bots/regions",
                bearerToken: token,
                timeout: 20
            )
            let text = PluginAPIClient.compactJSONText(from: response.data, limit: 2_000)
            guard let text else {
                return Task.isCancelled
                    ? "Connection test cancelled."
                    : "Connected — BrowserAct returned an unreadable response."
            }
            return "Connected — BrowserAct returned \(text.count) characters."
        } catch {
            return "Connection failed: \(PluginAPIClient.sanitizeAndTruncate(error.localizedDescription, limit: 500))"
        }
    }

    func testCrawl4AI() async -> String {
        guard validServerURL(effectiveCrawl4AIBaseURL) != nil else {
            return "Enter the full HTTPS Crawl4AI server address first."
        }
        do {
            guard let token = try credentials.read(crawl4AICredentialAccount), !token.isEmpty else {
                return "Save a Crawl4AI API token first."
            }
            if crawl4AIServiceKind == .cloud {
                let response = try await client.request(
                    baseURL: effectiveCrawl4AIBaseURL,
                    path: "/v1/prices",
                    bearerToken: token,
                    timeout: 20
                )
                return "Connected — Crawl4AI Cloud returned \(response.data.count) bytes of pricing data."
            }
            let response = try await client.request(
                baseURL: effectiveCrawl4AIBaseURL,
                path: "/schema",
                bearerToken: token,
                timeout: 20
            )
            let object = try Self.decodedObject(response.data)
            let crawler = object["crawler"] != nil
            let browser = object["browser"] != nil
            return "Connected — schema includes crawler: \(crawler ? "yes" : "no"), browser: \(browser ? "yes" : "no")."
        } catch {
            return "Connection failed: \(PluginAPIClient.sanitizeAndTruncate(error.localizedDescription, limit: 500))"
        }
    }

    // MARK: - Agent execution

    /// Fallback copy for a response the reader could not turn into text.
    /// `compactJSONText` and `sanitizeAndTruncate` both fail closed when the
    /// current task is cancelled, so the message must not accuse the server of
    /// sending something unreadable when the user actually pressed Stop.
    private static var unreadableResponseNotice: String {
        Task.isCancelled
            ? "Plugin call was cancelled before the response was read"
            : "BrowserAct returned an unreadable task response"
    }

    /// Runs before the approval card. Credential-shaped values and malformed
    /// destinations are rejected without spending a turn or asking the user to
    /// approve a request the adapter will refuse anyway.
    func refusalReason(for action: AgentAction) -> String? {
        guard action.kind == .runPlugin else { return nil }
        guard let plugin = action.plugin.flatMap(BrowserPluginID.init(rawValue:)),
              availablePluginIDs.contains(plugin.rawValue) else {
            return "That external plugin is disabled or not fully configured."
        }
        guard (action.plugin?.utf8.count ?? 0) <= 64,
              (action.operation?.utf8.count ?? 0) <= 256,
              boundedRequestCharacters(action) <= Self.maximumRequestCharacters else {
            return "The external request is too large to inspect safely; reduce its arguments before approval."
        }

        do {
            switch plugin {
            case .browserAct:
                guard let rawOperation = action.operation?.trimmed.lowercased(),
                      rawOperation.count <= 80,
                      let operation = BrowserActOperation(rawValue: rawOperation) else {
                    return "That BrowserAct operation is not supported."
                }
                if operation == .listRegions, hasPluginArguments(action) {
                    return "BrowserAct list_regions does not accept request arguments."
                }
                let identifier = action.identifier?.trimmed ?? ""
                guard identifier.count <= 512 else { return "That BrowserAct identifier is too long." }
                let configuredRunID: String
                switch operation {
                case .runBot: configuredRunID = browserActBotID.trimmed
                case .runTemplate: configuredRunID = browserActTemplateID.trimmed
                default: configuredRunID = ""
                }
                let effectiveRunID = identifier.isEmpty ? configuredRunID : identifier
                if !effectiveRunID.isEmpty {
                    do {
                        try validateProviderIdentifier(effectiveRunID)
                    } catch {
                        return "That BrowserAct identifier is unsafe."
                    }
                }
                if operation == .runBot, identifier.isEmpty, browserActBotID.trimmed.isEmpty {
                    return "Choose or configure a BrowserAct Bot ID first."
                }
                if operation == .runTemplate, identifier.isEmpty, browserActTemplateID.trimmed.isEmpty {
                    return "Choose or configure a BrowserAct template ID first."
                }
                let taskOperations: Set<BrowserActOperation> = [.getTask, .getStatus, .resumeTask, .cancelTask]
                if taskOperations.contains(operation), identifier.isEmpty {
                    return "That BrowserAct task operation needs a task ID."
                }
                if operation == .getBot, identifier.isEmpty { return "get_bot needs a Bot ID." }
                if operation == .getTemplate, identifier.isEmpty { return "get_template needs a template ID." }
                if let botType = action.botType?.trimmed.lowercased(),
                   !botType.isEmpty,
                   !["workflow", "agent"].contains(botType) {
                    return "BrowserAct Bot type must be workflow or agent."
                }
                if let status = action.status?.trimmed.lowercased(),
                   !status.isEmpty,
                   !["created", "running", "pausing", "paused", "finished", "canceled", "failed"].contains(status) {
                    return "That BrowserAct task status is not supported."
                }
                let createdFrom = try parsedISODate(action.createdFrom, label: "created_from")
                let createdTo = try parsedISODate(action.createdTo, label: "created_to")
                if let createdFrom, let createdTo, createdFrom > createdTo {
                    return "BrowserAct created_from must not be later than created_to."
                }
                if operation == .runTemplate {
                    let region = action.resolvedProxyRegion ?? browserActProxyRegion.trimmed
                    if !region.isEmpty,
                       region.count > 32 || !region.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                        return "The configured BrowserAct proxy region is not a valid region code."
                    }
                }
                if operation == .runBot || operation == .runTemplate,
                   let wait = action.resolvedWaitSeconds ?? action.waitSeconds,
                   !wait.isFinite || wait < 0 || wait > 60 {
                    return "BrowserAct wait_seconds must be between 0 and 60."
                }
                if let page = action.page, page < 1 || page > 500 {
                    return "BrowserAct page must be between 1 and 500."
                }
                let browserActMaximumLimit = operation == .listTemplates ? 500 : 100
                if let limit = action.limit, limit < 1 || limit > browserActMaximumLimit {
                    return "BrowserAct limit must be between 1 and \(browserActMaximumLimit) for that operation."
                }
                if let keyword = action.keyword?.trimmed, keyword.count > 200 {
                    return "That BrowserAct filter value is too long (maximum 200 characters)."
                }

                if (action.configuration?.utf8.count ?? 0) > 100_000 {
                    return "BrowserAct configuration is limited to 100,000 bytes."
                }
                let supplied = try configurationObject(action.configuration)
                let isRun = operation == .runBot || operation == .runTemplate
                if isRun {
                    guard action.resolvedTargetParameter != nil else {
                        return "The approved BrowserAct target mapping snapshot is missing."
                    }
                    guard action.resolvedWaitSeconds != nil || action.waitSeconds != nil else {
                        return "The approved BrowserAct wait snapshot is missing."
                    }
                    if operation == .runTemplate, action.resolvedProxyRegion == nil {
                        return "The approved BrowserAct proxy region snapshot is missing."
                    }
                }
                if !isRun, !supplied.isEmpty {
                    return "BrowserAct typed input configuration is only valid for run_bot or run_template."
                }
                if supplied.keys.contains(where: { $0 != "input" }) {
                    return "BrowserAct configuration may contain only the typed `input` object; callback URLs are intentionally unavailable."
                }
                if (action.inputParameters?.count ?? 0) > 100 {
                    return "BrowserAct accepts at most 100 input parameters."
                }
                if !isRun, !(action.inputParameters ?? []).isEmpty {
                    return "BrowserAct input parameters are only valid for run_bot or run_template."
                }
                if let rawInput = supplied["input"], !(rawInput is [String: Any]) {
                    return "BrowserAct configuration input must be a JSON object."
                }
                var input = (supplied["input"] as? [String: Any]) ?? [:]
                guard input.count <= 100 else {
                    return "BrowserAct typed input accepts at most 100 fields."
                }
                var inputNames = Set(input.keys.map { $0.lowercased() })
                for pair in action.inputParameters ?? [] {
                    let name = pair.name.trimmed
                    guard !name.isEmpty,
                          name.count <= 200,
                          name.rangeOfCharacter(from: .controlCharacters) == nil,
                          pair.value.utf8.count <= 4_000
                    else {
                        return "BrowserAct input names must contain 1-200 characters and values at most 4,000 bytes."
                    }
                    guard inputNames.insert(name.lowercased()).inserted else {
                        return "BrowserAct input names must be unique, ignoring case."
                    }
                    input[name] = pair.value
                }
                let targetKey = action.resolvedTargetParameter ?? browserActTargetParameter.trimmed
                if isRun, !targetKey.isEmpty {
                    guard targetKey.count <= 200,
                          targetKey.rangeOfCharacter(from: .controlCharacters) == nil,
                          !isSensitiveFieldName(targetKey)
                    else {
                        return "The configured BrowserAct target input name is unsafe."
                    }
                    let hasTarget = input.keys.contains { $0.caseInsensitiveCompare(targetKey) == .orderedSame }
                    if !hasTarget, let pageURL = action.url?.trimmed, !pageURL.isEmpty {
                        input[targetKey] = pageURL
                    }
                }
                try validateNoEmbeddedCredentials(input)
                if let url = action.url?.trimmed, !url.isEmpty, validPageURL(url) == nil {
                    return "BrowserAct was given an unsafe or malformed page URL."
                }
                if let keyword = action.keyword { try validateNoEmbeddedCredentials(keyword) }

            case .crawl4AI:
                guard let rawOperation = action.operation?.trimmed.lowercased(),
                      rawOperation.count <= 80,
                      let operation = Crawl4AIOperation(rawValue: rawOperation) else {
                    return "That Crawl4AI operation is not supported."
                }
                let approvedServiceKind = executionServiceKind(for: action)
                guard operation.serviceKind == approvedServiceKind else {
                    return "That operation belongs to Crawl4AI \(operation.serviceKind.name), not \(approvedServiceKind.name)."
                }
                let noArgumentOperations: Set<Crawl4AIOperation> = [
                    .schema, .hooks, .mcpSchema, .health, .recipes, .recipeHealth, .prices, .balance,
                ]
                if noArgumentOperations.contains(operation), hasPluginArguments(action) {
                    return "Crawl4AI \(operation.rawValue) does not accept request arguments."
                }
                let identifier = action.identifier?.trimmed ?? ""
                guard identifier.count <= 512 else { return "That Crawl4AI identifier is too long." }
                if !identifier.isEmpty {
                    do {
                        try validateProviderIdentifier(identifier)
                    } catch {
                        return "That Crawl4AI identifier is unsafe."
                    }
                }
                if (action.urls?.count ?? 0) > 10_000 {
                    return "Crawl4AI accepts at most 10,000 explicit URLs per call."
                }
                if (action.inputParameters?.count ?? 0) > 100 {
                    return "Crawl4AI accepts at most 100 recipe input parameters."
                }
                if (action.includePatterns?.count ?? 0) > 100
                    || (action.excludePatterns?.count ?? 0) > 100
                    || (action.includePatterns ?? []).contains(where: { $0.count > 300 })
                    || (action.excludePatterns ?? []).contains(where: { $0.count > 300 }) {
                    return "Crawl4AI accepts at most 100 include and exclude patterns each, up to 300 characters per pattern."
                }
                let hasPageURL = action.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let hasURLList = !(action.urls ?? []).isEmpty
                let hasQuery = action.query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let urlListOperations: Set<Crawl4AIOperation> = [.crawl, .stream, .crawlJob, .batch, .scrapeJob]
                if urlListOperations.contains(operation), !hasPageURL, !hasURLList {
                    return "That Crawl4AI operation needs at least one page URL."
                }
                if operation == .discover, !hasPageURL {
                    return "Crawl4AI link discovery needs the current rendered page URL."
                }
                let pageOperations: Set<Crawl4AIOperation> = [
                    .markdown, .html, .screenshot, .pdf, .executeJS, .ask, .scrape, .llmJob,
                ]
                if pageOperations.contains(operation), !hasPageURL {
                    return "That Crawl4AI operation needs a full page URL."
                }
                if operation == .executeJS,
                   (action.scripts?.isEmpty ?? true),
                   action.text?.trimmed.isEmpty != false {
                    return "Crawl4AI execute_js needs at least one script."
                }
                if operation != .executeJS, !(action.scripts ?? []).isEmpty {
                    return "Crawl4AI scripts are only valid for execute_js."
                }
                if operation == .executeJS,
                   !(action.scripts ?? []).isEmpty,
                   action.text?.trimmed.isEmpty != false {
                    return "Use either scripts or inline text for execute_js, not both."
                }
                if operation == .executeJS,
                   let scripts = action.scripts,
                   (scripts.count > 20 || scripts.reduce(0) { $0 + $1.utf8.count } > 100_000) {
                    return "Crawl4AI execute_js accepts at most 20 scripts and 100,000 script bytes."
                }
                if operation == .executeJS,
                   let script = action.text?.trimmed,
                   script.utf8.count > 20_000 {
                    return "A Crawl4AI execute_js snippet is limited to 20,000 bytes."
                }
                let queryOperations: Set<Crawl4AIOperation> = [.ask, .search, .answer, .llmJob]
                if queryOperations.contains(operation), !hasQuery {
                    return "That Crawl4AI operation needs a query."
                }
                let remoteIDOperations: Set<Crawl4AIOperation> = [
                    .crawlJobStatus, .llmJobStatus, .scrapeJobStatus,
                    .scrapeJobResults, .scrapeJobRetry, .artifact,
                ]
                if remoteIDOperations.contains(operation), identifier.isEmpty {
                    return "That Crawl4AI operation needs a remote task or artifact ID."
                }
                if operation == .recipeRun, identifier.isEmpty {
                    return "Crawl4AI recipe_run needs a recipe name."
                }
                if operation == .structuredExtract,
                   !hasPageURL,
                   action.text?.trimmed.isEmpty != false {
                    return "structured_extract needs a page URL or inline content."
                }
                if operation == .structuredExtract,
                   action.instruction?.trimmed.isEmpty != false,
                   action.jsonSchema?.trimmed.isEmpty != false {
                    return "structured_extract needs an extraction instruction or JSON Schema."
                }
                let estimateEndpoint = (action.keyword ?? "").trimmed.lowercased()
                let isEstimateExtraction = operation == .estimate && estimateEndpoint == "extract"
                if action.instruction?.trimmed.isEmpty == false,
                   operation != .structuredExtract,
                   !isEstimateExtraction {
                    return "Crawl4AI extraction instructions are only valid for structured_extract or an extract estimate."
                }
                if action.example?.trimmed.isEmpty == false,
                   operation != .structuredExtract,
                   !isEstimateExtraction {
                    return "Crawl4AI extraction examples are only valid for structured_extract or an extract estimate."
                }
                if operation == .markdown,
                   let filter = action.filter?.lowercased(),
                   !["fit", "raw", "bm25", "llm"].contains(filter) {
                    return "Crawl4AI Markdown filter must be fit, raw, bm25, or llm."
                }
                if let format = action.format?.trimmed.lowercased(),
                   !format.isEmpty,
                   !["md", "html", "both"].contains(format) {
                    return "Crawl4AI format must be md, html, or both."
                }
                if let temperature = action.temperature, !temperature.isFinite || temperature < 0 || temperature > 2 {
                    return "Crawl4AI temperature must be between 0 and 2."
                }
                if operation == .screenshot {
                    if action.resolvedWaitSeconds == nil, action.waitSeconds == nil {
                        return "The approved Crawl4AI screenshot wait snapshot is missing."
                    }
                    if let wait = action.resolvedWaitSeconds ?? action.waitSeconds,
                       !wait.isFinite || wait < 0 || wait > 10 {
                        return "Crawl4AI screenshot wait_seconds must be between 0 and 10."
                    }
                }
                if let proxy = action.proxy?.lowercased(), !proxy.isEmpty,
                   !["none", "isp", "residential"].contains(proxy) {
                    return "Crawl4AI Cloud proxy must be none, isp, or residential."
                }
                if let country = action.country?.trimmed,
                   !country.isEmpty,
                   (country.count != 2 || !country.allSatisfy({ $0.isLetter })) {
                    return "Crawl4AI Cloud country must be a two-letter code."
                }
                if let depth = action.depth, depth < 0 || depth > 5 {
                    return "Crawl4AI depth must be between 0 and 5."
                }
                if let maxPages = action.maxPages, maxPages < 1 || maxPages > 100 {
                    return "Crawl4AI max_pages must be between 1 and 100."
                }
                if let limit = action.limit, limit < 1 || limit > 50 {
                    return "Crawl4AI link limit must be between 1 and 50."
                }
                if let after = action.after, after < 0 {
                    return "Crawl4AI result cursor cannot be negative."
                }
                if let provider = action.provider?.trimmed, provider.count > 200 {
                    return "That Crawl4AI provider name is too long."
                }
                if let keyword = action.keyword?.trimmed, keyword.count > 500 {
                    return "That Crawl4AI keyword is too long."
                }
                if let query = action.query?.trimmed {
                    let maximum: Int = operation == .search || operation == .answer ? 512 : 4_000
                    if query.count > maximum {
                        return "That Crawl4AI query is too long (maximum \(maximum) characters)."
                    }
                }
                if let instruction = action.instruction?.trimmed, instruction.count > 4_000 {
                    return "Crawl4AI extraction instructions are limited to 4,000 characters."
                }
                if let text = action.text?.trimmed, text.count > 200_000 {
                    return "Crawl4AI inline content is limited to 200,000 characters."
                }
                if (action.configuration?.utf8.count ?? 0) > 100_000 {
                    return "Crawl4AI configuration is limited to 100,000 bytes."
                }

                let urlCap: Int? = switch operation {
                case .crawl, .stream, .crawlJob: 100
                case .batch: 50
                case .scrapeJob: 10_000
                case .estimate: 10_000
                default: nil
                }
                if operation == .discover, (action.urls?.count ?? 0) > 50 {
                    return "Crawl4AI discover accepts at most 50 reviewed links per call."
                }
                if let urlCap, (action.urls?.count ?? 0) > urlCap {
                    return "That Crawl4AI operation accepts at most \(urlCap) explicit URLs per call."
                }
                if operation == .stream,
                   (action.urls?.count ?? 0) > 1,
                   action.depth != nil || action.maxPages != nil
                    || !(action.includePatterns ?? []).isEmpty
                    || !(action.excludePatterns ?? []).isEmpty {
                    return "Crawl4AI streaming deep crawl accepts one seed URL; remove the extra URLs or the deep-crawl controls."
                }

                let supplied = try configurationObject(action.configuration)
                try rejectLegacyHookCode(supplied)
                let configurationOperations: Set<Crawl4AIOperation> = [
                    .crawl, .discover, .stream, .crawlJob, .validateConfig, .recipeRun,
                ]
                let isEstimateRecipe = operation == .estimate
                    && (estimateEndpoint == "recipe_run" || estimateEndpoint.hasPrefix("recipes/"))
                if !supplied.isEmpty, !configurationOperations.contains(operation), !isEstimateRecipe {
                    return "Crawl4AI configuration is not accepted for that operation."
                }
                if operation == .crawlJob, supplied["hooks"] != nil {
                    return "Crawl4AI crawl_job does not accept declarative hooks; use crawl or stream for hooks."
                }
                if operation != .recipeRun, !isEstimateRecipe, !(action.inputParameters ?? []).isEmpty {
                    return "Crawl4AI input_parameters are only valid for recipe_run or a recipe estimate."
                }
                if (operation == .recipeRun || isEstimateRecipe),
                   !supplied.isEmpty,
                   !(action.inputParameters ?? []).isEmpty {
                    return "Use either recipe configuration or input_parameters, not both."
                }
                if operation == .validateConfig {
                    guard supplied["type"] is String, supplied["params"] is [String: Any] else {
                        return "Crawl4AI validate_config needs a JSON object with type and params."
                    }
                }
                if !configurationOperations.contains(operation),
                   let inputValues = action.inputParameters?.map(\.value) {
                    try validateNoEmbeddedCredentials(inputValues)
                }
                if operation == .recipeRun || isEstimateRecipe {
                    try validateRecipeInputParameters(action)
                    let recipeInput = supplied.isEmpty ? namedInput(action) : supplied
                    try validateRecipeInputKeys(recipeInput)
                    try validateNoEmbeddedCredentials(recipeInput)
                } else {
                    try validateNoEmbeddedCredentials(supplied)
                }
                if operation == .executeJS {
                    if let scripts = action.scripts { try validateNoEmbeddedCredentials(scripts) }
                    if let text = action.text { try validateNoEmbeddedCredentials(text) }
                }

                if let schema = action.jsonSchema?.trimmingCharacters(in: .whitespacesAndNewlines), !schema.isEmpty {
                    guard schema.utf8.count <= 100_000 else {
                        return "Crawl4AI JSON Schema is limited to 100,000 bytes."
                    }
                    let value = try jsonValue(schema, label: "json_schema")
                    try validateNoEmbeddedCredentials(value)
                }
                if let example = action.example?.trimmingCharacters(in: .whitespacesAndNewlines), !example.isEmpty {
                    guard example.utf8.count <= 100_000 else {
                        return "Crawl4AI extraction examples are limited to 100,000 bytes."
                    }
                    let value = try jsonValue(example, label: "example")
                    guard value is [String: Any] || value is [Any] else {
                        throw PluginAPIError.decoding("example must be a JSON object or array")
                    }
                    try validateNoEmbeddedCredentials(value)
                }
                if operation == .estimate {
                    _ = try estimatePayload(for: action)
                }
                for candidate in ([action.url].compactMap { $0 } + (action.urls ?? [])) where validPageURL(candidate) == nil {
                    return "Crawl4AI was given an unsafe or malformed page URL."
                }
                for text in [action.query, action.instruction, action.text, action.provider, action.keyword].compactMap({ $0 }) {
                    try validateNoEmbeddedCredentials(text)
                }
                for pattern in (action.includePatterns ?? []) + (action.excludePatterns ?? []) {
                    try validateNoEmbeddedCredentials(pattern)
                }
            }
            return nil
        } catch {
            // This string reaches the model, and `sensitiveInput` interpolates a
            // model-supplied field name, so it is sanitized like any other
            // outbound text rather than shown verbatim. The sanitizer fails
            // closed on cancellation, so fall back to a fixed reason there.
            let safe = PluginAPIClient.sanitizeAndTruncate(error.localizedDescription, limit: 300)
            return safe.isEmpty ? "This plugin call was refused before it was sent." : safe
        }
    }

    func execute(_ action: AgentAction, webView: WebViewProxy) async -> PluginExecutionResult {
        guard let plugin = action.plugin.flatMap(BrowserPluginID.init(rawValue:)) else {
            return failure("Plugin is disabled or not fully configured")
        }
        switch plugin {
        case .browserAct where !browserActEnabled:
            return failure("BrowserAct was disabled after approval")
        case .crawl4AI where !crawl4AIEnabled:
            return failure("Crawl4AI was disabled after approval")
        default:
            break
        }
        // App-resolved endpoint/kind fields are populated before the approval
        // card. If settings change while that card is open, execute the exact
        // approved snapshot (or fail if its Keychain credential was removed).
        // Missing metadata is never allowed to fall back to mutable settings.
        guard let approvedEndpoint = action.approvalEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !approvedEndpoint.isEmpty
        else {
            return failure("The external approval snapshot is missing")
        }
        if plugin == .browserAct, approvedEndpoint != "https://api.browseract.com" {
            return failure("The approved BrowserAct endpoint is invalid")
        }

        do {
            switch plugin {
            case .browserAct:
                return try await executeBrowserAct(action)
            case .crawl4AI:
                return try await executeCrawl4AI(action, webView: webView)
            }
        } catch is CancellationError {
            return PluginExecutionResult(summary: "Plugin call cancelled", extracted: nil, succeeded: false)
        } catch {
            return failure(error.localizedDescription)
        }
    }

    private func executeBrowserAct(_ action: AgentAction) async throws -> PluginExecutionResult {
        guard let token = try credentials.read(.browserAct), !token.isEmpty else {
            throw PluginAPIError.notConfigured("BrowserAct")
        }
        guard let rawOperation = action.operation?.trimmed.lowercased(),
              let operation = BrowserActOperation(rawValue: rawOperation)
        else {
            throw PluginAPIError.decoding("unsupported BrowserAct operation")
        }

        let identifier = action.identifier?.trimmed ?? ""
        if !identifier.isEmpty {
            try validateProviderIdentifier(identifier)
        }
        let page = min(max(action.page ?? 1, 1), 500)
        let maximumItems = operation == .listTemplates ? 500 : 100
        let limit = min(max(action.limit ?? 20, 1), maximumItems)
        var path = ""
        var method = PluginAPIClient.Method.get
        var body: [String: Any]?
        var query: [URLQueryItem] = []

        switch operation {
        case .runBot, .runTemplate:
            method = .post
            // AgentViewModel resolves the configured ID into the approval
            // snapshot before showing the card. Never read the mutable setting
            // again after approval.
            guard !identifier.isEmpty else {
                throw PluginAPIError.notConfigured(operation == .runBot ? "an approved BrowserAct Bot ID" : "an approved BrowserAct template ID")
            }
            let runID = identifier
            guard let safeRunID = safeProviderIdentifier(runID) else {
                throw PluginAPIError.decoding("the configured BrowserAct run ID is unsafe")
            }
            let collection = operation == .runBot ? "bots" : "bots/templates"
            path = "/v3/\(collection)/\(PluginAPIClient.safePathComponent(safeRunID))/runs"
            var input: [String: Any] = [:]
            let supplied = try configurationObject(action.configuration)
            if supplied["input"] != nil && !(supplied["input"] is [String: Any]) {
                throw PluginAPIError.decoding("BrowserAct typed input must be a JSON object")
            }
            if let configuredInput = supplied["input"] as? [String: Any] {
                guard configuredInput.count <= 100,
                      configuredInput.keys.allSatisfy({ $0.rangeOfCharacter(from: .controlCharacters) == nil })
                else {
                    throw PluginAPIError.decoding("BrowserAct typed input contains too many or malformed fields")
                }
                input.merge(configuredInput) { _, new in new }
            }
            for pair in action.inputParameters ?? [] {
                let name = pair.name.trimmed
                guard !name.isEmpty else { continue }
                input[String(name.prefix(200))] = String(pair.value.prefix(4_000))
            }
            let suppliedTarget = action.url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetURL = validPageURL(suppliedTarget ?? "") ?? ""
            if let suppliedTarget, !suppliedTarget.isEmpty, targetURL.isEmpty {
                throw PluginAPIError.decoding("BrowserAct received an unsafe page URL")
            }
            guard let targetKey = action.resolvedTargetParameter else {
                throw PluginAPIError.decoding("the approved BrowserAct target mapping is missing")
            }
            guard targetKey.count <= 200,
                  targetKey.rangeOfCharacter(from: .controlCharacters) == nil,
                  !isSensitiveFieldName(targetKey)
            else {
                throw PluginAPIError.decoding("the configured BrowserAct target input name is unsafe")
            }
            let hasTarget = input.keys.contains { key in
                !targetKey.isEmpty && key.caseInsensitiveCompare(targetKey) == .orderedSame
            }
            if !targetURL.isEmpty, !targetKey.isEmpty, !hasTarget {
                input[targetKey] = targetURL
            }
            try validateNoEmbeddedCredentials(input)
            var payload: [String: Any] = ["input": input]
            if operation == .runTemplate {
                guard let proxyRegion = action.resolvedProxyRegion else {
                    throw PluginAPIError.decoding("the approved BrowserAct proxy region snapshot is missing")
                }
                if !proxyRegion.isEmpty {
                    guard proxyRegion.count <= 32,
                          proxyRegion.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
                    else {
                        throw PluginAPIError.decoding("the approved BrowserAct proxy region is unsafe")
                    }
                    payload["proxy_region"] = proxyRegion.uppercased()
                }
            }
            body = payload

        case .getTask, .getStatus, .resumeTask, .cancelTask:
            guard !identifier.isEmpty else { throw PluginAPIError.notConfigured("a BrowserAct task ID") }
            let taskPath = PluginAPIClient.safePathComponent(identifier)
            path = "/v3/bots/runs/\(taskPath)"
            if operation == .getStatus { path += "/status" }
            if operation == .resumeTask { path += "/resume" }
            if operation == .cancelTask { path += "/cancel" }
            if operation == .resumeTask || operation == .cancelTask { method = .post }

        case .listTasks:
            path = "/v3/bots/runs"
            query = [
                URLQueryItem(name: "bot_id", value: identifier),
                URLQueryItem(name: "bot_name", value: action.keyword?.trimmed ?? ""),
                URLQueryItem(name: "status", value: action.status?.trimmed.lowercased() ?? ""),
                URLQueryItem(name: "created_at_from", value: action.createdFrom ?? ""),
                URLQueryItem(name: "created_at_to", value: action.createdTo ?? ""),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]

        case .listBots:
            path = "/v3/bots"
            query = [
                URLQueryItem(name: "bot_type", value: action.botType?.trimmed.lowercased() ?? ""),
                URLQueryItem(name: "keyword", value: action.keyword ?? ""),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]

        case .getBot:
            guard !identifier.isEmpty else { throw PluginAPIError.notConfigured("a BrowserAct Bot ID") }
            path = "/v3/bots/\(PluginAPIClient.safePathComponent(identifier))"

        case .listTemplates:
            path = "/v3/bots/templates"
            query = [
                URLQueryItem(name: "keyword", value: action.keyword ?? ""),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]

        case .getTemplate:
            guard !identifier.isEmpty else { throw PluginAPIError.notConfigured("a BrowserAct template ID") }
            path = "/v3/bots/templates/\(PluginAPIClient.safePathComponent(identifier))"

        case .listRegions:
            path = "/v3/bots/regions"
        }

        query = query.filter { item in
            guard let value = item.value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let response = try await client.request(
            baseURL: "https://api.browseract.com",
            path: path,
            method: method,
            queryItems: query,
            jsonBody: body,
            bearerToken: token,
            timeout: 30
        )
        guard response.data.count <= 20_000_000 else {
            throw PluginAPIError.decoding("BrowserAct response exceeds the app's safety limit")
        }

        if operation == .runBot || operation == .runTemplate {
            let waitValue: Double
            // The approved snapshot wins. It already folds in any model-supplied
            // request, and it is the value the card disclosed, so re-reading the
            // raw argument here would make the run differ from what was approved.
            if let snapshotWait = action.resolvedWaitSeconds {
                waitValue = snapshotWait
            } else if let explicitWait = action.waitSeconds {
                waitValue = explicitWait
            } else {
                throw PluginAPIError.decoding("the approved BrowserAct wait snapshot is missing")
            }
            guard waitValue.isFinite else {
                throw PluginAPIError.decoding("the approved BrowserAct wait is malformed")
            }
            return try await finishBrowserActRun(
                operation: operation,
                startData: response.data,
                requestedWait: Int(min(max(waitValue, 0), 60)),
                token: token
            )
        }

        if response.data.isEmpty {
            let failed: Bool
            switch operation {
            case .getTask, .getStatus, .listBots, .getBot, .listTemplates, .getTemplate, .listTasks, .listRegions:
                failed = true
            case .resumeTask, .cancelTask:
                failed = false
            case .runBot, .runTemplate:
                failed = false
            }
            return PluginExecutionResult(
                summary: failed ? "Plugin error: BrowserAct \(operation.rawValue) returned an empty response" : "BrowserAct \(operation.rawValue) completed",
                extracted: failed ? "The remote operation returned no readable response." : "BrowserAct \(operation.rawValue) completed successfully.",
                succeeded: !failed
            )
        }
        if operation == .getTask {
            let object = try? Self.decodedObject(response.data)
            let failed = object == nil || Self.responseSignalsFailure(response.data, object: object)
            let persistedFiles: (object: [String: Any], saved: [String])
            if failed {
                persistedFiles = (object ?? [:], [])
            } else {
                persistedFiles = try await persistBrowserActOutputFiles(object ?? [:])
            }
            let output = object == nil
                ? (PluginAPIClient.compactJSONText(from: response.data, limit: crawl4AIOutputLimit) ?? Self.unreadableResponseNotice)
                : Self.compactObject(persistedFiles.object, limit: crawl4AIOutputLimit)
            let fileNote = persistedFiles.saved.isEmpty
                ? ""
                : " · saved \(persistedFiles.saved.count) output file\(persistedFiles.saved.count == 1 ? "" : "s")"
            return PluginExecutionResult(
                summary: (failed ? "Plugin error: " : "") + "BrowserAct get_task returned \(output.count) characters\(fileNote)",
                extracted: output,
                succeeded: !failed
            )
        }
        let object = try? Self.decodedObject(response.data)
        let output = PluginAPIClient.compactJSONText(from: response.data, limit: crawl4AIOutputLimit)
            ?? PluginAPIClient.sanitizeAndTruncate(
                PluginAPIClient.sanitizeHTML(String(decoding: response.data, as: UTF8.self)),
                limit: crawl4AIOutputLimit
            )
        let failed = Self.responseSignalsFailure(response.data, object: object)
        return PluginExecutionResult(
            summary: (failed ? "Plugin error: " : "") + "BrowserAct \(operation.rawValue) returned \(output.count) characters",
            extracted: output,
            succeeded: !failed
        )
    }

    private func finishBrowserActRun(
        operation: BrowserActOperation,
        startData: Data,
        requestedWait: Int,
        token: String
    ) async throws -> PluginExecutionResult {
        let start = try Self.decodedObject(startData)
        let rawTaskID = stringValue(start["task_id"]) ?? stringValue(start["id"])
        guard let taskID = rawTaskID.flatMap({ safeProviderIdentifier($0) }) else {
            let output = PluginAPIClient.compactJSONText(from: startData, limit: crawl4AIOutputLimit) ?? "No task ID returned"
            return PluginExecutionResult(
                summary: "Plugin error: BrowserAct returned no task ID",
                extracted: output,
                succeeded: false
            )
        }
        if Self.responseSignalsFailure(startData, object: start) {
            var failedStart = start
            failedStart["task_id"] = taskID
            return PluginExecutionResult(
                summary: "Plugin error: BrowserAct task \(taskID) could not start",
                extracted: Self.compactObject(failedStart, limit: crawl4AIOutputLimit),
                succeeded: false
            )
        }
        guard requestedWait > 0 else {
            let failed = Self.responseSignalsFailure(startData, object: start)
            return PluginExecutionResult(
                summary: (failed ? "Plugin error: " : "") + "BrowserAct task \(taskID) started",
                extracted: Self.compactObject(start, limit: crawl4AIOutputLimit),
                succeeded: !failed
            )
        }

        let deadline = Date().addingTimeInterval(TimeInterval(requestedWait))
        var latest: [String: Any] = start
        while Date() < deadline && !Task.isCancelled {
            try await Task.sleep(for: .seconds(2))
            let statusResponse: PluginAPIClient.Response
            do {
                statusResponse = try await client.request(
                    baseURL: "https://api.browseract.com",
                    path: "/v3/bots/runs/\(PluginAPIClient.safePathComponent(taskID))/status",
                    bearerToken: token,
                    timeout: 20
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return browserActStatusUnavailable(taskID: taskID, latest: latest)
            }
            guard let statusObject = try? Self.decodedObject(statusResponse.data) else {
                return browserActStatusUnavailable(taskID: taskID, latest: latest)
            }
            let status = Self.safeRemoteStatus(statusObject["status"])
            latest = statusObject
            if Self.remoteObjectSignalsFailure(statusObject) {
                var failedStatus = statusObject
                failedStatus["task_id"] = taskID
                return PluginExecutionResult(
                    summary: "Plugin error: BrowserAct \(operation.rawValue) task \(taskID) reported a remote error",
                    extracted: Self.compactObject(failedStatus, limit: crawl4AIOutputLimit),
                    succeeded: false
                )
            }
            if ["finished", "failed", "canceled", "cancelled"].contains(status) {
                let detail: PluginAPIClient.Response
                do {
                    detail = try await client.request(
                        baseURL: "https://api.browseract.com",
                        path: "/v3/bots/runs/\(PluginAPIClient.safePathComponent(taskID))",
                        bearerToken: token,
                        timeout: 30
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    return browserActStatusUnavailable(taskID: taskID, latest: latest)
                }
                guard detail.data.count <= 20_000_000 else {
                    throw PluginAPIError.decoding("BrowserAct task detail exceeds the app's safety limit")
                }
                let detailObject = try? Self.decodedObject(detail.data)
                let failed = Self.responseSignalsFailure(detail.data, object: detailObject) ||
                    Self.remoteObjectSignalsFailure(statusObject)
                let persistedFiles: (object: [String: Any], saved: [String])
                if failed {
                    persistedFiles = (detailObject ?? [:], [])
                } else {
                    persistedFiles = try await persistBrowserActOutputFiles(detailObject ?? [:])
                }
                let output = detailObject == nil
                    ? (PluginAPIClient.compactJSONText(from: detail.data, limit: crawl4AIOutputLimit) ?? Self.unreadableResponseNotice)
                    : Self.compactObject(persistedFiles.object, limit: crawl4AIOutputLimit)
                let fileNote = persistedFiles.saved.isEmpty
                    ? ""
                    : " · saved \(persistedFiles.saved.count) output file\(persistedFiles.saved.count == 1 ? "" : "s")"
                let summary = failed
                    ? "Plugin error: BrowserAct \(operation.rawValue) task \(taskID) \(status)"
                    : "BrowserAct \(operation.rawValue) task \(taskID) \(status)"
                return PluginExecutionResult(
                    summary: summary + fileNote,
                    extracted: output,
                    succeeded: !failed
                )
            }
        }

        var pending = latest
        pending["task_id"] = taskID
        pending["wait_note"] = "Task is still running remotely; call get_status or get_task with this ID later."
        let output = Self.compactObject(pending, limit: crawl4AIOutputLimit)
        return PluginExecutionResult(
            summary: "BrowserAct task \(taskID) is still running after \(requestedWait)s",
            extracted: output
        )
    }

    private func browserActStatusUnavailable(taskID: String, latest: [String: Any]) -> PluginExecutionResult {
        var pending = latest
        pending["task_id"] = taskID
        pending["status_note"] = "status_unavailable"
        pending["wait_note"] = "The task was started, but its status could not be read. Keep this task_id and call get_task later."
        return PluginExecutionResult(
            summary: "Plugin error: BrowserAct task \(taskID) status is unavailable; keep this ID and retry get_task later",
            extracted: Self.compactObject(pending, limit: crawl4AIOutputLimit),
            succeeded: false
        )
    }

    private func executeCrawl4AI(_ action: AgentAction, webView: WebViewProxy) async throws -> PluginExecutionResult {
        guard let serviceKind = action.approvalServiceKind.flatMap(Crawl4AIServiceKind.init(rawValue:)),
              let approvedEndpoint = action.approvalEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
              validApprovedCrawl4AIEndpoint(approvedEndpoint, for: serviceKind)
        else {
            throw PluginAPIError.decoding("the approved Crawl4AI service snapshot is invalid")
        }
        let baseURL = serviceKind == .cloud ? "https://api.crawl4ai.com" : approvedEndpoint
        guard let token = try credentials.read(executionCredentialAccount(for: action)), !token.isEmpty else {
            throw PluginAPIError.notConfigured("Crawl4AI")
        }
        guard let rawOperation = action.operation?.trimmed.lowercased(),
              let operation = Crawl4AIOperation(rawValue: rawOperation)
        else {
            throw PluginAPIError.decoding("unsupported Crawl4AI operation")
        }
        guard operation.serviceKind == serviceKind else {
            throw PluginAPIError.decoding("\(operation.rawValue) belongs to Crawl4AI \(operation.serviceKind.name), not \(serviceKind.name)")
        }
        guard validServerURL(baseURL) != nil else {
            throw PluginAPIError.notConfigured("a valid Crawl4AI server address")
        }

        let method: PluginAPIClient.Method
        let path: String
        var body: [String: Any]?
        var query: [URLQueryItem] = []
        var timeout: TimeInterval = 75

        switch operation {
        case .crawl, .discover, .stream:
            method = .post
            let urls: [String]
            if operation == .discover {
                let current = webView.webView.url?.absoluteString ?? ""
                guard validPageURL(current) != nil else {
                    throw PluginAPIError.decoding("link discovery needs a loaded http(s) page")
                }
                if let approvedURL = action.url?.trimmed,
                   validPageURL(approvedURL) != nil,
                   canonicalPageURL(approvedURL) != canonicalPageURL(current) {
                    throw PluginAPIError.decoding("link discovery can only read the page shown in the approval card")
                }
                let cap = min(max(action.limit ?? 20, 1), 50)
                let discovered: [String]
                if let approved = action.urls, !approved.isEmpty {
                    discovered = approved
                } else {
                    discovered = await webView.discoverLinks(limit: cap, sameOrigin: action.sameOrigin ?? true)
                }
                let currentOrigin = canonicalOrigin(current)
                let reviewed = (action.sameOrigin ?? true)
                    ? discovered.filter { canonicalOrigin($0) == currentOrigin }
                    : discovered
                urls = Array(uniqueURLs([current] + reviewed).prefix(cap))
            } else {
                let requested = requestedPageURLs(action)
                urls = Array(uniqueURLs(requested.filter { validPageURL($0) != nil }).prefix(100))
            }
            guard !urls.isEmpty else { throw PluginAPIError.decoding("no valid crawl URLs were provided") }
            body = try crawlBody(action: action, urls: Array(urls))
            path = operation == .stream ? "/crawl/stream" : "/crawl"

        case .markdown:
            method = .post
            let url = try requiredPageURL(action)
            var payload: [String: Any] = [
                "url": url,
                "f": (action.filter ?? "fit").trimmed.lowercased(),
                "q": action.query ?? "",
                "c": action.keyword ?? "0",
            ]
            if let provider = action.provider?.trimmed, !provider.isEmpty { payload["provider"] = provider }
            if let temperature = action.temperature { payload["temperature"] = temperature }
            body = payload
            path = "/md"

        case .html:
            method = .post
            body = ["url": try requiredPageURL(action)]
            path = "/html"

        case .screenshot:
            method = .post
            let wait: Double
            // As with BrowserAct runs, the approved snapshot is authoritative.
            if let snapshotWait = action.resolvedWaitSeconds {
                wait = snapshotWait
            } else if let explicitWait = action.waitSeconds {
                wait = explicitWait
            } else {
                throw PluginAPIError.decoding("the approved Crawl4AI screenshot wait snapshot is missing")
            }
            guard wait.isFinite else {
                throw PluginAPIError.decoding("the approved Crawl4AI screenshot wait is malformed")
            }
            body = [
                "url": try requiredPageURL(action),
                "screenshot_wait_for": min(max(wait, 0), 10),
                "wait_for_images": action.waitForImages ?? false,
            ]
            path = "/screenshot"

        case .pdf:
            method = .post
            body = ["url": try requiredPageURL(action)]
            path = "/pdf"

        case .executeJS:
            method = .post
            let scripts = action.scripts?.map { String($0.prefix(20_000)) } ?? action.text.map { [String($0.prefix(20_000))] } ?? []
            guard !scripts.isEmpty else { throw PluginAPIError.decoding("execute_js needs at least one script") }
            body = ["url": try requiredPageURL(action), "scripts": scripts]
            path = "/execute_js"
            timeout = 90

        case .ask:
            method = .get
            let url = try requiredPageURL(action)
            guard let question = action.query?.trimmed, !question.isEmpty else {
                throw PluginAPIError.decoding("ask needs a query")
            }
            path = "/llm/" + PluginAPIClient.nestedPagePath(url)
            query = [URLQueryItem(name: "q", value: question)]
            if let provider = action.provider?.trimmed, !provider.isEmpty {
                query.append(URLQueryItem(name: "provider", value: provider))
            }
            if let temperature = action.temperature {
                query.append(URLQueryItem(name: "temperature", value: String(temperature)))
            }

        case .schema:
            method = .get
            path = "/schema"

        case .hooks:
            method = .get
            path = "/hooks/info"

        case .mcpSchema:
            method = .get
            path = "/mcp/schema"

        case .validateConfig:
            method = .post
            let object = try configurationObject(action.configuration)
            guard object["type"] is String, object["params"] is [String: Any] else {
                throw PluginAPIError.decoding("validate_config expects a JSON object with type and params")
            }
            body = object
            path = "/config/dump"

        case .health:
            method = .get
            path = "/health"
            timeout = 20

        case .crawlJob:
            method = .post
            let urls = try crawlURLs(action)
            body = crawlBody(action: action, urls: urls)
            path = "/crawl/job"

        case .crawlJobStatus:
            method = .get
            let taskID = try requiredIdentifier(action)
            path = "/crawl/job/\(PluginAPIClient.safePathComponent(taskID))"

        case .llmJob:
            method = .post
            let question = try requiredQuery(action, operation: "llm_job")
            var payload: [String: Any] = [
                "url": try requiredPageURL(action),
                "q": question,
                "cache": false,
            ]
            if let schema = action.jsonSchema?.trimmed, !schema.isEmpty { payload["schema"] = schema }
            if let provider = action.provider?.trimmed, !provider.isEmpty { payload["provider"] = provider }
            if let temperature = action.temperature { payload["temperature"] = temperature }
            body = payload
            path = "/llm/job"

        case .llmJobStatus:
            method = .get
            let taskID = try requiredIdentifier(action)
            path = "/llm/job/\(PluginAPIClient.safePathComponent(taskID))"

        case .artifact:
            method = .get
            let artifactID = try requiredIdentifier(action)
            path = "/artifacts/\(PluginAPIClient.safePathComponent(artifactID))"
            timeout = 90

        case .scrape:
            method = .post
            var payload = cloudScrapeFields(action)
            payload["url"] = try requiredPageURL(action)
            body = payload
            path = "/scrape"
            timeout = 90

        case .structuredExtract:
            method = .post
            var payload: [String: Any] = [:]
            if let url = action.url?.trimmed, !url.isEmpty {
                payload["url"] = try requiredPageURL(action)
            } else if let content = action.text?.trimmed, !content.isEmpty {
                payload["content"] = String(content.prefix(200_000))
            }
            guard !payload.isEmpty else { throw PluginAPIError.decoding("structured_extract needs a url or supplied content") }
            if let instruction = action.instruction?.trimmed, !instruction.isEmpty {
                payload["instruction"] = String(instruction.prefix(4_000))
            }
            if let schema = action.jsonSchema?.trimmed, !schema.isEmpty {
                payload["schema"] = try jsonValue(schema, label: "json_schema")
            }
            if let example = action.example?.trimmed, !example.isEmpty {
                payload["example"] = try jsonValue(example, label: "example")
            }
            guard payload.count > 1 else { throw PluginAPIError.decoding("structured_extract needs an instruction or schema") }
            body = payload
            path = "/extract"
            timeout = 90

        case .search:
            method = .get
            path = "/search"
            query = [
                URLQueryItem(name: "q", value: try requiredQuery(action, operation: "search")),
                URLQueryItem(name: "rich", value: action.rich == true ? "1" : "0"),
            ]

        case .answer:
            method = .get
            path = "/answer"
            query = [
                URLQueryItem(name: "q", value: try requiredQuery(action, operation: "answer")),
                URLQueryItem(name: "deep", value: action.deep == false ? "0" : "1"),
            ]
            timeout = 90

        case .batch:
            method = .post
            let urls = try crawlURLs(action)
            guard urls.count <= 50 else { throw PluginAPIError.decoding("Cloud batch accepts at most 50 URLs") }
            var payload = cloudScrapeFields(action)
            payload["urls"] = urls
            body = payload
            path = "/scrape/batch"
            timeout = 90

        case .scrapeJob:
            method = .post
            let urls = try crawlURLs(action)
            guard urls.count <= 10_000 else { throw PluginAPIError.decoding("Cloud jobs accept at most 10,000 URLs") }
            var payload = cloudScrapeFields(action)
            payload["urls"] = urls
            body = payload
            path = "/scrape/jobs"
            timeout = 90

        case .scrapeJobStatus:
            method = .get
            let jobID = try requiredIdentifier(action)
            path = "/scrape/jobs/\(PluginAPIClient.safePathComponent(jobID))"

        case .scrapeJobResults:
            method = .get
            let jobID = try requiredIdentifier(action)
            path = "/scrape/jobs/\(PluginAPIClient.safePathComponent(jobID))/results"
            query = [URLQueryItem(name: "after", value: String(max(action.after ?? 0, 0)))]
            timeout = 90

        case .scrapeJobRetry:
            method = .post
            let jobID = try requiredIdentifier(action)
            path = "/scrape/jobs/\(PluginAPIClient.safePathComponent(jobID))/retry"

        case .recipes:
            method = .get
            path = "/recipes"

        case .recipeRun:
            method = .post
            let name = try requiredIdentifier(action)
            path = "/recipes/\(PluginAPIClient.safePathComponent(name))"
            let suppliedRecipeInput = try configurationObject(action.configuration)
            try validateRecipeInputParameters(action)
            let recipeInput = suppliedRecipeInput.isEmpty ? namedInput(action) : suppliedRecipeInput
            try validateRecipeInputKeys(recipeInput)
            var payload = recipeInput
            try validateNoEmbeddedCredentials(payload)
            if action.bypassCache == true { payload["bypass_cache"] = true }
            body = payload
            // Cloud recipes may legitimately run for several minutes. The
            // request and the run segment are both bounded, but long enough
            // to cover the provider's documented job window.
            timeout = 300

        case .recipeHealth:
            method = .get
            path = "/recipes/health"

        case .prices:
            method = .get
            path = "/v1/prices"

        case .balance:
            method = .get
            path = "/v1/billing/balance"

        case .estimate:
            method = .post
            body = try estimatePayload(for: action)
            path = "/v1/estimate"
        }

        let responseLimit: Int = switch operation {
        case .screenshot, .pdf: 40_000_000
        case .artifact: 25_000_000
        default: 20_000_000
        }
        let response = try await client.request(
            baseURL: baseURL,
            path: path,
            method: method,
            queryItems: query,
            jsonBody: body,
            bearerToken: token,
            timeout: timeout,
            maximumResponseBytes: responseLimit
        )

        guard response.data.count <= responseLimit else {
            throw PluginAPIError.decoding("Crawl4AI response exceeds the app's safety limit")
        }

        if operation == .artifact {
            guard response.data.count <= 25_000_000 else {
                throw PluginAPIError.decoding("artifact exceeds the app's 25 MB safety limit")
            }
            let artifactID = try requiredIdentifier(action)
            let record = try saveArtifact(
                response.data,
                plugin: BrowserPluginID.crawl4AI.rawValue,
                operation: operation.rawValue,
                suggestedName: response.suggestedFileName ?? "artifact-\(artifactID)",
                mimeType: response.mimeType
            )
            return PluginExecutionResult(
                summary: "Saved Crawl4AI artifact \(record.fileName)",
                extracted: "Saved locally as \(record.fileName) (\(record.byteCount) bytes). It is available in Settings → External Plugins."
            )
        }

        var artifactNote = ""
        var pluginImageData: Data?
        if operation == .screenshot || operation == .pdf {
            let artifact = try await persistArtifactFromVisualResponse(
                operation: operation,
                data: response.data,
                token: token,
                baseURL: baseURL
            )
            artifactNote = artifact.note
            pluginImageData = artifact.imageData
        }

        let output: String
        let outputLimit = crawl4AIOutputLimit
        let outputFormat = action.format
        if operation == .screenshot || operation == .pdf {
            // Visual bytes are already persisted and, for screenshots, forwarded
            // as an image. Rendering the binary/PDF envelope here would burn
            // CPU and memory on output that is deliberately not sent as text.
            output = ""
        } else {
            let renderTask: Task<String, Never>
            if operation == .stream || operation == .batch || operation == .scrapeJobResults {
                renderTask = Task.detached(priority: .utility) {
                    Self.compactNDJSON(response.data, limit: outputLimit)
                }
            } else {
                renderTask = Task.detached(priority: .utility) {
                    Self.renderCrawl4AI(
                        operation: operation,
                        data: response.data,
                        format: outputFormat,
                        limit: outputLimit
                    )
                }
            }
            output = await withTaskCancellationHandler {
                await renderTask.value
            } onCancel: {
                renderTask.cancel()
            }
            try Task.checkCancellation()
        }
        let returnedID: String
        if operation == .screenshot || operation == .pdf {
            returnedID = ""
        } else {
            returnedID = remoteIdentifier(from: response.data).map { " · remote ID \($0)" } ?? ""
        }
        let remoteAnalysis: (failed: Bool, count: Int?)
        if operation == .screenshot || operation == .pdf {
            // Do not scan a whole PDF/PNG as if it were an NDJSON stream.
            remoteAnalysis = (Self.responseSignalsFailure(response.data), nil)
        } else {
            let analysisTask = Task.detached(priority: .utility) {
                (
                    Self.responseSignalsFailure(response.data) || Self.ndjsonSignalsFailure(response.data),
                    Self.crawlResultCount(from: response.data)
                )
            }
            remoteAnalysis = await withTaskCancellationHandler {
                await analysisTask.value
            } onCancel: {
                analysisTask.cancel()
            }
        }
        try Task.checkCancellation()
        let remoteFailed = remoteAnalysis.failed
        let resultSummary: String
        if let count = remoteAnalysis.count {
            resultSummary = "Crawl4AI crawled \(count) page\(count == 1 ? "" : "s")\(artifactNote.isEmpty ? "" : " · \(artifactNote)")\(returnedID)"
        } else {
            resultSummary = "Crawl4AI \(operation.rawValue) returned \(output.count) characters\(artifactNote.isEmpty ? "" : " · \(artifactNote)")\(returnedID)"
        }
        let finalSummary = remoteFailed ? "Plugin error: \(resultSummary)" : resultSummary
        let carriesAgentContext: Bool = {
            switch operation {
            case .screenshot, .pdf: false
            default: true
            }
        }()
        return PluginExecutionResult(
            summary: finalSummary,
            extracted: carriesAgentContext ? output : nil,
            succeeded: !remoteFailed,
            imageData: pluginImageData
        )
    }

    private func persistBrowserActOutputFiles(
        _ object: [String: Any]
    ) async throws -> (object: [String: Any], saved: [String]) {
        var redacted = object
        var saved: [String] = []
        var seen: Set<String> = []
        var attempts = 0
        let maximumFiles = 4
        let maximumAttempts = 8

        if var outputFiles = redacted["output_files"] as? [String: Any] {
            for format in outputFiles.keys.sorted() where attempts < maximumAttempts && saved.count < maximumFiles {
                guard var metadata = outputFiles[format] as? [String: Any],
                      let rawURL = metadata["download_url"] as? String,
                      !seen.contains(rawURL) else { continue }
                seen.insert(rawURL)
                attempts += 1
                do {
                    let response = try await client.download(absoluteURL: rawURL, timeout: 30)
                    guard response.data.count <= 25_000_000 else {
                        throw PluginAPIError.decoding("output file exceeds the app's 25 MB safety limit")
                    }
                    let fallback = "browseract-\(format).bin"
                    let record = try saveArtifact(
                        response.data,
                        plugin: BrowserPluginID.browserAct.rawValue,
                        operation: "output_file",
                        suggestedName: response.suggestedFileName
                            ?? (metadata["file_name"] as? String)
                            ?? fallback,
                        mimeType: response.mimeType
                    )
                    metadata.removeValue(forKey: "download_url")
                    metadata["local_file"] = record.fileName
                    outputFiles[format] = metadata
                    saved.append(record.fileName)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    metadata["download_url"] = "[signed download removed]"
                    metadata["download_note"] = "The remote file could not be fetched."
                    outputFiles[format] = metadata
                }
            }
            for format in outputFiles.keys {
                if var metadata = outputFiles[format] as? [String: Any],
                   metadata["download_url"] != nil {
                    metadata["download_url"] = "[omitted: file limit]"
                    outputFiles[format] = metadata
                }
            }
            redacted["output_files"] = outputFiles
        }

        if var downloads = redacted["download_files"] as? [Any] {
            for index in downloads.indices where attempts < maximumAttempts && saved.count < maximumFiles {
                guard var metadata = downloads[index] as? [String: Any],
                      let rawURL = metadata["download_url"] as? String,
                      !seen.contains(rawURL) else { continue }
                seen.insert(rawURL)
                attempts += 1
                do {
                    let response = try await client.download(absoluteURL: rawURL, timeout: 30)
                    guard response.data.count <= 25_000_000 else {
                        throw PluginAPIError.decoding("download file exceeds the app's 25 MB safety limit")
                    }
                    let fallback = "browseract-file-\(UUID().uuidString.prefix(8)).bin"
                    let record = try saveArtifact(
                        response.data,
                        plugin: BrowserPluginID.browserAct.rawValue,
                        operation: "download_file",
                        suggestedName: response.suggestedFileName
                            ?? (metadata["file_name"] as? String)
                            ?? fallback,
                        mimeType: response.mimeType
                    )
                    metadata.removeValue(forKey: "download_url")
                    metadata["local_file"] = record.fileName
                    downloads[index] = metadata
                    saved.append(record.fileName)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    metadata["download_url"] = "[signed download removed]"
                    metadata["download_note"] = "The remote file could not be fetched."
                    downloads[index] = metadata
                }
            }
            for index in downloads.indices {
                if var metadata = downloads[index] as? [String: Any],
                   metadata["download_url"] != nil {
                    metadata["download_url"] = "[omitted: file limit]"
                    downloads[index] = metadata
                }
            }
            redacted["download_files"] = downloads
        }
        return (redacted, saved)
    }

    // MARK: - Artifacts

    private func persistArtifactFromVisualResponse(
        operation: Crawl4AIOperation,
        data: Data,
        token: String,
        baseURL: String
    ) async throws -> (note: String, imageData: Data?) {
        let baseKey = operation == .screenshot ? "screenshot" : "pdf"
        let expectedMIME = operation == .screenshot ? "image/png" : "application/pdf"
        let extensionName = operation == .screenshot ? "png" : "pdf"

        // Some deployments return the image/PDF bytes directly instead of a
        // JSON envelope. Preserve those artifacts before attempting JSON decode.
        if isVisualBinary(data, operation: operation) {
            guard data.count <= 25_000_000 else {
                return (note: "visual artifact exceeded the app's 25 MB safety limit", imageData: nil)
            }
            let record = try saveArtifact(
                data,
                plugin: BrowserPluginID.crawl4AI.rawValue,
                operation: operation.rawValue,
                suggestedName: "crawl4ai-\(UUID().uuidString.prefix(8)).\(extensionName)",
                mimeType: expectedMIME
            )
            return (note: "saved \(record.fileName)", imageData: operation == .screenshot ? data : nil)
        }

        let object = (try? Self.decodedObject(data)) ?? [:]
        let artifactID = stringValue(object["artifact_id"]).flatMap { safeProviderIdentifier($0) }
        let artifactSuffix = artifactID.map { " · remote artifact \($0)" } ?? ""

        // A few Crawl4AI deployments return a temporary HTTPS URL rather than an
        // artifact ID. It is fetched without the service API credential.
        let temporaryURLKeys = [baseKey, "\(baseKey)_url", "download_url", "file_url"]
        if let rawURL = temporaryURLKeys.compactMap({ object[$0] as? String }).first,
           let url = URL(string: rawURL),
           url.scheme?.lowercased() == "https" {
            do {
                let response = try await client.download(absoluteURL: rawURL, timeout: 60)
                let record = try saveArtifact(
                    response.data,
                    plugin: BrowserPluginID.crawl4AI.rawValue,
                    operation: operation.rawValue,
                    suggestedName: response.suggestedFileName ?? "crawl4ai-\(UUID().uuidString.prefix(8)).\(extensionName)",
                    mimeType: response.mimeType == "application/octet-stream" ? expectedMIME : response.mimeType
                )
                return (note: "saved \(record.fileName)", imageData: operation == .screenshot ? response.data : nil)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let safeError = PluginAPIClient.sanitizeAndTruncate(error.localizedDescription, limit: 500)
                AppLog.plugin.warning("Crawl4AI visual artifact download failed: \(safeError, privacy: .private)")
                return (note: "artifact reference returned, but its temporary file could not be downloaded", imageData: nil)
            }
        }

        if let encoded = object[baseKey] as? String {
            let base64Value: String
            if encoded.lowercased().hasPrefix("data:") {
                guard let comma = encoded.firstIndex(of: ",") else {
                    return (note: "artifact reference returned; its data URI was malformed", imageData: nil)
                }
                base64Value = String(encoded[encoded.index(after: comma)...])
            } else {
                base64Value = encoded
            }
            let decodeTask = Task.detached(priority: .utility) {
                Data(base64Encoded: base64Value, options: .ignoreUnknownCharacters)
            }
            let decodedBytes = await withTaskCancellationHandler {
                await decodeTask.value
            } onCancel: {
                decodeTask.cancel()
            }
            try Task.checkCancellation()
            guard let bytes = decodedBytes, !bytes.isEmpty, bytes.count <= 25_000_000 else {
                return (note: "artifact reference returned; encoded bytes were empty or too large", imageData: nil)
            }
            let record = try saveArtifact(
                bytes,
                plugin: BrowserPluginID.crawl4AI.rawValue,
                operation: operation.rawValue,
                suggestedName: "crawl4ai-\(UUID().uuidString.prefix(8)).\(extensionName)",
                mimeType: expectedMIME
            )
            return (note: "saved \(record.fileName)\(artifactSuffix)", imageData: operation == .screenshot ? bytes : nil)
        }

        if let artifactID {
            do {
                let response = try await client.request(
                    baseURL: baseURL,
                    path: "/artifacts/\(PluginAPIClient.safePathComponent(artifactID))",
                    bearerToken: token,
                    timeout: 90,
                    maximumResponseBytes: 25_000_000
                )
                guard response.data.count <= 25_000_000 else {
                    throw PluginAPIError.decoding("artifact exceeds the app's 25 MB safety limit")
                }
                let fallbackName = "crawl4ai-\(artifactID).\(extensionName)"
                let record = try saveArtifact(
                    response.data,
                    plugin: BrowserPluginID.crawl4AI.rawValue,
                    operation: operation.rawValue,
                    suggestedName: response.suggestedFileName ?? fallbackName,
                    mimeType: response.mimeType == "application/octet-stream" ? expectedMIME : response.mimeType
                )
                return (note: "saved \(record.fileName)\(artifactSuffix)", imageData: operation == .screenshot ? response.data : nil)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                let safeError = PluginAPIClient.sanitizeAndTruncate(error.localizedDescription, limit: 500)
                AppLog.plugin.warning("Crawl4AI artifact download failed: \(safeError, privacy: .private)")
                return (note: "artifact reference returned, but its temporary file could not be downloaded\(artifactSuffix)", imageData: nil)
            }
        }
        return (note: "artifact reference returned; no downloadable bytes were included", imageData: nil)
    }

    private func isVisualBinary(_ data: Data, operation: Crawl4AIOperation) -> Bool {
        guard !data.isEmpty else { return false }
        let bytes = [UInt8](data.prefix(8))
        if operation == .pdf {
            return String(decoding: bytes, as: UTF8.self).hasPrefix("%PDF-")
        }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true } // PNG
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true } // JPEG
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true } // GIF
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && data.count >= 12 { return true } // WEBP
        return false
    }

    private func saveArtifact(
        _ data: Data,
        plugin: String,
        operation: String,
        suggestedName: String,
        mimeType: String
    ) throws -> PluginArtifactRecord {
        guard !data.isEmpty else { throw PluginAPIError.decoding("artifact response was empty") }
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedDirectory = artifactDirectory
        try? protectedDirectory.setResourceValues(resourceValues)
        let originalName = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = String(originalName.prefix(200))
        let sanitizedName = PluginAPIClient.sanitizeAndTruncate(rawName, limit: 200)
        let unsafeName = originalName.count > 200
            || rawName.isEmpty
            || rawName.contains("?")
            || rawName.contains("#")
            || rawName.contains("%")
            || PluginAPIClient.absoluteURLs(in: rawName).isEmpty == false
            || PluginAPIClient.containsSensitiveRemoteText(rawName)
        var safeBase = sanitizedName
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let source = safeBase as NSString
        let ext = source.pathExtension
        let stem = source.deletingPathExtension
        let maxStem = max(1, 100 - (ext.isEmpty ? 0 : ext.count + 1))
        safeBase = ext.isEmpty
            ? String(stem.prefix(maxStem))
            : "\(String(stem.prefix(maxStem))).\(String(ext.prefix(20)))"
        if unsafeName || safeBase.isEmpty || safeBase == "." || safeBase == ".." || safeBase.hasPrefix(".")
            || isCredentialShapedValue(safeBase) {
            safeBase = "artifact-\(UUID().uuidString.prefix(8))"
        }
        let cleanMIME = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let safeMIME = cleanMIME.count <= 100
            && cleanMIME.range(of: "^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$", options: .regularExpression) != nil
            ? cleanMIME
            : "application/octet-stream"
        var fileName = safeBase
        if FileManager.default.fileExists(atPath: artifactDirectory.appendingPathComponent(fileName).path) {
            let source = fileName as NSString
            let ext = source.pathExtension
            let stem = source.deletingPathExtension
            fileName = ext.isEmpty ? "\(stem)-\(UUID().uuidString.prefix(8))" : "\(stem)-\(UUID().uuidString.prefix(8)).\(ext)"
        }
        let destination = artifactDirectory.appendingPathComponent(fileName)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        let record = PluginArtifactRecord(
            id: UUID(),
            plugin: plugin,
            operation: operation,
            fileName: fileName,
            mimeType: safeMIME,
            byteCount: data.count,
            createdAt: Date()
        )
        artifacts.insert(record, at: 0)
        pruneArtifacts()
        guard artifacts.contains(where: { $0.id == record.id }) else {
            try? FileManager.default.removeItem(at: destination)
            throw PluginAPIError.decoding("artifact storage limit is full")
        }
        persistArtifacts()
        return record
    }

    private func loadArtifacts() {
        guard let data = defaults.data(forKey: Keys.artifacts) else {
            // No metadata has ever been written. Do not sweep a directory that
            // may belong to a newer app version or a restored device backup.
            return
        }
        guard let stored = try? JSONDecoder().decode([PluginArtifactRecord].self, from: data) else {
            AppLog.plugin.warning("Plugin artifact metadata could not be decoded; existing files were left untouched")
            return
        }
        artifacts = stored.filter { artifactURL(for: $0) != nil }
        pruneArtifacts()
        removeOrphanArtifacts()
        persistArtifacts()
    }

    private func pruneArtifacts() {
        while true {
            let totalBytes = artifacts.reduce(Int64(0)) { partial, record in
                let (sum, overflow) = partial.addingReportingOverflow(Int64(max(0, record.byteCount)))
                return overflow ? Int64.max : sum
            }
            guard artifacts.count > Self.maximumArtifactCount
                || totalBytes > Int64(Self.maximumArtifactBytes),
                let old = artifacts.popLast()
            else { break }
            if let url = artifactURL(for: old) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func removeOrphanArtifacts() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: artifactDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        let known = Set(artifacts.map(\.fileName))
        for url in contents where !known.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func persistArtifacts() {
        if let data = try? JSONEncoder().encode(artifacts) {
            defaults.set(data, forKey: Keys.artifacts)
        }
    }

    // MARK: - Request shaping

    private func crawlBody(action: AgentAction, urls: [String]) throws -> [String: Any] {
        let supplied = try configurationObject(action.configuration)
        try rejectLegacyHookCode(supplied)
        try validateNoEmbeddedCredentials(supplied)
        var browserConfig = (supplied["browser_config"] as? [String: Any]) ?? [:]
        var crawlerConfig = (supplied["crawler_config"] as? [String: Any]) ?? [:]
        if browserConfig.isEmpty { browserConfig = ["type": "BrowserConfig", "params": [:]] }
        if crawlerConfig.isEmpty { crawlerConfig = ["type": "CrawlerRunConfig", "params": [:]] }

        let include = (action.includePatterns ?? []).map { String($0.prefix(300)) }
        let exclude = (action.excludePatterns ?? []).map { String($0.prefix(300)) }
        if action.depth != nil || action.maxPages != nil || !include.isEmpty || !exclude.isEmpty {
            var params: [String: Any] = [
                "max_depth": min(max(action.depth ?? 1, 0), 5),
                "max_pages": min(max(action.maxPages ?? max(urls.count, 1), 1), 100),
            ]
            if !include.isEmpty { params["include_patterns"] = include }
            if !exclude.isEmpty { params["exclude_patterns"] = exclude }
            let strategy: [String: Any] = [
                "type": "BFSDeepCrawlStrategy",
                "params": params,
            ]
            let crawlerType = crawlerConfig["type"] as? String
            if crawlerType == "CrawlerRunConfig" {
                var nested = (crawlerConfig["params"] as? [String: Any]) ?? [:]
                nested["deep_crawl_strategy"] = strategy
                crawlerConfig["params"] = nested
            } else {
                crawlerConfig["deep_crawl_strategy"] = strategy
            }
        }
        let isDiscover = Crawl4AIOperation(rawValue: action.operation?.trimmed.lowercased() ?? "") == .discover
        let excludeExternalLinks = isDiscover
            ? (action.sameOrigin ?? true)
            : action.excludeExternalLinks
        if let excludeExternalLinks {
            let crawlerType = crawlerConfig["type"] as? String
            if crawlerType == "CrawlerRunConfig" {
                var nested = (crawlerConfig["params"] as? [String: Any]) ?? [:]
                nested["exclude_external_links"] = excludeExternalLinks
                crawlerConfig["params"] = nested
            } else {
                crawlerConfig["exclude_external_links"] = excludeExternalLinks
            }
        }

        var body: [String: Any] = [
            "urls": urls,
            "browser_config": browserConfig,
            "crawler_config": crawlerConfig,
        ]
        if action.operation != "crawl_job", let hooks = supplied["hooks"] {
            body["hooks"] = hooks
        }
        return body
    }

    private func requestedPageURLs(_ action: AgentAction) -> [String] {
        if let urls = action.urls, !urls.isEmpty { return urls }
        if let url = action.url?.trimmed, !url.isEmpty { return [url] }
        return []
    }

    private func crawlURLs(_ action: AgentAction) throws -> [String] {
        let requested = requestedPageURLs(action)
        let urls = Array(uniqueURLs(requested.filter { validPageURL($0) != nil }).prefix(10_000))
        guard !urls.isEmpty else { throw PluginAPIError.decoding("no valid crawl URLs were provided") }
        return urls
    }

    private func requiredIdentifier(_ action: AgentAction) throws -> String {
        guard let value = action.identifier?.trimmed,
              let safe = safeProviderIdentifier(value)
        else {
            throw PluginAPIError.decoding("this operation needs a safe identifier")
        }
        return safe
    }

    private func requiredQuery(_ action: AgentAction, operation: String) throws -> String {
        guard let value = action.query?.trimmed, !value.isEmpty else {
            throw PluginAPIError.decoding("\(operation) needs a query")
        }
        return value
    }

    private func rejectLegacyHookCode(_ value: Any, depth: Int = 0) throws {
        guard depth < 12 else { throw PluginAPIError.decoding("plugin configuration is nested too deeply") }
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                let keyProbe = PluginAPIClient.canonicalizeRemoteText(key)
                if PluginAPIClient.normalizedFieldName(key) == "hooks"
                    || PluginAPIClient.normalizedFieldName(keyProbe) == "hooks",
                   let hooks = nested as? [String: Any],
                   hooks.keys.contains(where: {
                       let hookKey = PluginAPIClient.canonicalizeRemoteText($0)
                       return PluginAPIClient.normalizedFieldName($0) == "code"
                           || PluginAPIClient.normalizedFieldName(hookKey) == "code"
                   }) {
                    throw PluginAPIError.decoding("legacy Crawl4AI hooks.code is not accepted")
                }
                try rejectLegacyHookCode(nested, depth: depth + 1)
            }
        } else if let array = value as? [Any] {
            for nested in array {
                try rejectLegacyHookCode(nested, depth: depth + 1)
            }
        }
    }

    private func validateNoEmbeddedCredentials(_ value: Any, depth: Int = 0) throws {
        guard depth < 12 else {
            throw PluginAPIError.decoding("plugin configuration is nested too deeply")
        }
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                let nested = dictionary[key] ?? NSNull()
                let keyProbe = PluginAPIClient.canonicalizeRemoteText(key)
                if isSensitiveFieldName(key) || isSensitiveFieldName(keyProbe) {
                    throw PluginAPIError.sensitiveInput(String(key.prefix(80)))
                }
                if isHeaderContainerName(key) || isHeaderContainerName(keyProbe) {
                    throw PluginAPIError.sensitiveInput("header container \(String(key.prefix(80)))")
                }
                if (key.lowercased() == "action" || keyProbe.lowercased() == "action"),
                   let hookAction = nested as? String,
                   (isSensitiveFieldName(hookAction) || hookAction.lowercased() == "set_headers") {
                    throw PluginAPIError.sensitiveInput("hook action \(String(hookAction.prefix(80)))")
                }
                try validateNoEmbeddedCredentials(nested, depth: depth + 1)
            }
        } else if let array = value as? [Any] {
            for nested in array {
                try validateNoEmbeddedCredentials(nested, depth: depth + 1)
            }
        } else if let string = value as? String {
            // A script or inline configuration value can carry a credential
            // without presenting it as a JSON field name. Reuse the same
            // redaction grammar as the output boundary, but treat any change
            // as a refusal rather than sending a partially masked request.
            // Check cancellation first so a stopped run is reported as a stop
            // instead of as a credential refusal.
            try Task.checkCancellation()
            if isCredentialShapedValue(string)
                || PluginAPIClient.containsSensitiveRemoteText(string) {
                throw PluginAPIError.sensitiveInput("credential-shaped value")
            }
            let canonical = PluginAPIClient.canonicalizeRemoteText(string)
            var probes = [string]
            if canonical != string, !probes.contains(canonical) {
                probes.append(canonical)
            }
            for candidate in probes {
                let relativeURLs = PluginAPIClient.relativeURLReferences(in: candidate)
                for url in PluginAPIClient.httpURLs(in: candidate) {
                    let hasHost = url.host != nil
                    let scheme = url.scheme?.lowercased() ?? (hasHost ? "https" : "")
                    guard ["http", "https"].contains(scheme),
                          hasHost,
                          url.user == nil,
                          url.password == nil,
                          !urlContainsSensitiveQuery(url),
                          PluginAPIClient.isPublicNetworkHost(url.host ?? "")
                    else {
                        throw PluginAPIError.sensitiveInput("signed, credential-bearing, private, or malformed URL")
                    }
                }
                for url in PluginAPIClient.absoluteURLs(in: candidate) {
                    let scheme = url.scheme?.lowercased() ?? ""
                    guard ["http", "https"].contains(scheme) else {
                        throw PluginAPIError.sensitiveInput("non-HTTP URL schemes are not accepted in plugin requests")
                    }
                    // HTTP(S) URLs are checked in the dedicated loop above;
                    // this branch mainly rejects DSN-like schemes before they
                    // can carry credentials into a remote configuration.
                }
                for url in relativeURLs {
                    guard url.user == nil,
                          url.password == nil,
                          !urlContainsSensitiveQuery(url)
                    else {
                        throw PluginAPIError.sensitiveInput("signed or credential-bearing relative URL")
                    }
                }
            }
        }
    }

    private func isCredentialShapedValue(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        let prefixes = [
            "sk_live_", "sk_test_", "sk-", "sk-ant-", "ghp_", "gho_", "ghu_", "ghs_",
            "glpat-", "xoxb-", "xoxp-", "akia", "eyj", "aiza", "xai-", "npm_", "dop_v1_",
            "hf_", "r8_", "shpat_",
        ]
        if prefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        if lower.contains("-----begin") && lower.contains("private key-----") { return true }
        if value.range(of: #"^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func safeProviderIdentifier(_ raw: String) -> String? {
        let value = raw.trimmed
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        guard !value.isEmpty,
              value.count <= 512,
              value.rangeOfCharacter(from: .controlCharacters) == nil,
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !value.contains("://"),
              !value.contains("?"),
              !value.contains("#"),
              !value.contains("/"),
              !value.contains("\\"),
              value != ".",
              value != "..",
              !isCredentialShapedValue(value)
        else { return nil }
        do {
            try validateNoEmbeddedCredentials(value)
            return value
        } catch {
            return nil
        }
    }

    private func validateProviderIdentifier(_ raw: String) throws {
        guard safeProviderIdentifier(raw) != nil else {
            throw PluginAPIError.decoding("the provider identifier is unsafe")
        }
    }

    private func isSensitiveFieldName(_ raw: String) -> Bool {
        let normalized = PluginAPIClient.normalizedFieldName(raw)
        let words = Set(normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let sensitiveWords: Set<String> = [
            "password", "passwd", "pass", "pwd", "passphrase", "token", "secret", "credential",
            "credentials", "cookie", "cookies", "auth", "authorization", "authentication",
            "bearer", "session", "apikey", "privatekey", "signature", "sig", "key", "otp",
            "totp", "jwt", "hmac", "signedurl",
        ]
        if !words.isDisjoint(with: sensitiveWords) { return true }
        let compact = normalized.filter { $0.isLetter || $0.isNumber }
        let compactSensitive: Set<String> = [
            "password", "passwd", "passphrase", "token", "accesstoken", "refreshtoken",
            "authtoken", "apitoken", "apikey", "secret", "clientsecret", "credential",
            "credentials", "cookie", "cookies", "authorization", "authentication", "bearer",
            "session", "sessionid", "privatekey", "accesskey", "signingkey", "sharedkey",
            "signature", "sig", "signedurl", "keypairid", "hmac", "accesskeyid",
            "awsaccesskeyid", "googleaccessid", "secretaccesskey", "signed",
        ]
        return compactSensitive.contains(compact)
    }

    private func isHeaderContainerName(_ raw: String) -> Bool {
        let normalized = PluginAPIClient.normalizedFieldName(raw)
        let words = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return words.contains("header") || words.contains("headers")
    }

    private func parsedISODate(_ raw: String?, label: String) throws -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: raw) { return date }
        throw PluginAPIError.decoding("\(label) must be an ISO-8601 date-time")
    }

    private func namedInput(_ action: AgentAction) -> [String: Any] {
        var input: [String: Any] = [:]
        for pair in action.inputParameters ?? [] {
            let name = pair.name.trimmed
            guard !name.isEmpty else { continue }
            input[String(name.prefix(200))] = String(pair.value.prefix(4_000))
        }
        return input
    }

    private func validateRecipeInputParameters(_ action: AgentAction) throws {
        var names = Set<String>()
        for pair in action.inputParameters ?? [] {
            let name = pair.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  name.count <= 200,
                  name.rangeOfCharacter(from: .controlCharacters) == nil,
                  pair.value.utf8.count <= 4_000,
                  names.insert(name.lowercased()).inserted
            else {
                throw PluginAPIError.decoding("Crawl4AI recipe input names must be unique, 1-200 characters, and values at most 4,000 bytes")
            }
        }
    }

    private func validateRecipeInputKeys(_ input: [String: Any]) throws {
        let reserved: Set<String> = ["endpoint", "recipe", "bypass_cache"]
        for key in input.keys {
            let normalized = PluginAPIClient.normalizedFieldName(key).lowercased()
            let normalizedProbe = PluginAPIClient.normalizedFieldName(
                PluginAPIClient.canonicalizeRemoteText(key)
            ).lowercased()
            guard !reserved.contains(normalized),
                  !reserved.contains(normalizedProbe),
                  key.rangeOfCharacter(from: .controlCharacters) == nil
            else {
                throw PluginAPIError.decoding("Crawl4AI recipe inputs cannot overwrite reserved request fields")
            }
        }
    }

    private func estimatePayload(for action: AgentAction) throws -> [String: Any] {
        let rawEndpoint = (action.keyword ?? "scrape").trimmed
        let endpoint = (rawEndpoint.hasPrefix("/") ? String(rawEndpoint.dropFirst()) : rawEndpoint).lowercased()
        let knownEndpoints: Set<String> = [
            "scrape", "search", "answer", "extract", "batch", "scrape/jobs",
            "scrape_job", "recipe_run", "recipe_health", "prices", "balance",
        ]
        guard !endpoint.isEmpty,
              endpoint.count <= 200,
              endpoint.rangeOfCharacter(from: .controlCharacters) == nil,
              knownEndpoints.contains(endpoint) || endpoint.hasPrefix("recipes/")
        else {
            throw PluginAPIError.decoding("estimate needs a supported Cloud endpoint name")
        }
        if endpoint.hasPrefix("recipes/") {
            let name = String(endpoint.dropFirst("recipes/".count))
            guard safeProviderIdentifier(name) != nil else {
                throw PluginAPIError.decoding("estimate has an unsafe recipe name")
            }
        }

        var payload: [String: Any] = ["endpoint": endpoint]
        if endpoint.hasPrefix("recipes/") {
            let recipe = String(endpoint.dropFirst("recipes/".count))
            guard let safeRecipe = safeProviderIdentifier(recipe) else {
                throw PluginAPIError.decoding("estimate has an unsafe recipe name")
            }
            payload["recipe"] = safeRecipe
            let supplied = try configurationObject(action.configuration)
            try validateRecipeInputParameters(action)
            let input = supplied.isEmpty ? namedInput(action) : supplied
            try validateRecipeInputKeys(input)
            try validateNoEmbeddedCredentials(input)
            for (key, value) in input { payload[key] = value }
            if action.bypassCache == true { payload["bypass_cache"] = true }
            return payload
        }
        switch endpoint {
        case "scrape":
            let urls = try crawlURLs(action)
            guard urls.count == 1 else { throw PluginAPIError.decoding("scrape estimates need exactly one page URL") }
            payload["url"] = urls[0]
            for (key, value) in cloudScrapeFields(action) { payload[key] = value }
        case "batch":
            let urls = try crawlURLs(action)
            guard urls.count <= 50 else { throw PluginAPIError.decoding("batch estimates accept at most 50 URLs") }
            payload["urls"] = urls
            for (key, value) in cloudScrapeFields(action) { payload[key] = value }
        case "scrape/jobs", "scrape_job":
            payload["urls"] = try crawlURLs(action)
            for (key, value) in cloudScrapeFields(action) { payload[key] = value }
        case "search":
            let query = try requiredQuery(action, operation: "estimate(search)")
            guard query.count <= 512 else { throw PluginAPIError.decoding("search estimates accept at most 512 query characters") }
            payload["q"] = query
            if let rich = action.rich { payload["rich"] = rich ? 1 : 0 }
        case "answer":
            let query = try requiredQuery(action, operation: "estimate(answer)")
            guard query.count <= 512 else { throw PluginAPIError.decoding("answer estimates accept at most 512 query characters") }
            payload["q"] = query
            if let deep = action.deep { payload["deep"] = deep ? 1 : 0 }
        case "extract":
            if let url = action.url?.trimmed, !url.isEmpty {
                payload["url"] = try requiredPageURL(action)
            } else if let content = action.text?.trimmed, !content.isEmpty {
                payload["content"] = String(content.prefix(200_000))
            } else {
                throw PluginAPIError.decoding("extract estimates need a page URL or inline content")
            }
            if let instruction = action.instruction?.trimmed, !instruction.isEmpty {
                payload["instruction"] = String(instruction.prefix(4_000))
            }
            if let schema = action.jsonSchema?.trimmed, !schema.isEmpty {
                payload["schema"] = try jsonValue(schema, label: "json_schema")
            }
            if let sample = action.example?.trimmed, !sample.isEmpty {
                payload["example"] = try jsonValue(sample, label: "example")
            }
            guard payload["instruction"] != nil || payload["schema"] != nil else {
                throw PluginAPIError.decoding("extract estimates need an instruction or JSON Schema")
            }
        case "recipe_run":
            let recipe = try requiredIdentifier(action)
            payload["recipe"] = recipe
            let supplied = try configurationObject(action.configuration)
            try validateRecipeInputParameters(action)
            let input = supplied.isEmpty ? namedInput(action) : supplied
            try validateRecipeInputKeys(input)
            try validateNoEmbeddedCredentials(input)
            for (key, value) in input { payload[key] = value }
            if action.bypassCache == true { payload["bypass_cache"] = true }
        default:
            // Endpoint-only read-only estimates need no target parameters.
            break
        }
        return payload
    }

    private func cloudScrapeFields(_ action: AgentAction) -> [String: Any] {
        var payload: [String: Any] = [
            "format": (action.format ?? "both").trimmed.lowercased(),
            "parse": cloudParseOptions(action),
        ]
        if let proxy = action.proxy?.trimmed.lowercased(), !proxy.isEmpty { payload["proxy"] = proxy }
        if let country = action.country?.trimmed, !country.isEmpty { payload["country"] = country.lowercased() }
        return payload
    }

    private func cloudParseOptions(_ action: AgentAction) -> Any {
        if action.parseAll == true { return true }
        var selected: [String: Bool] = [:]
        if action.parseLinks == true { selected["links"] = true }
        if action.parseMedia == true { selected["media"] = true }
        if action.parseMetadata == true { selected["metadata"] = true }
        if action.parseTables == true { selected["tables"] = true }
        if selected.isEmpty { return false }
        return selected
    }

    /// Rejects excessively nested JSON *before* `JSONSerialization` sees it.
    /// The post-parse depth guards only run once a value already exists, and a
    /// model can be steered into emitting tens of thousands of nested brackets
    /// through page text, so the structure is counted from the raw bytes first.
    nonisolated static func isWithinJSONNestingLimit(_ raw: String, limit: Int = 32) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for character in raw.utf8 {
            if inString {
                if escaped {
                    escaped = false
                } else if character == UInt8(ascii: "\\") {
                    escaped = true
                } else if character == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch character {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                if depth > limit { return false }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
            default:
                break
            }
        }
        return true
    }

    private func jsonValue(_ raw: String, label: String) throws -> Any {
        guard Self.isWithinJSONNestingLimit(raw) else {
            throw PluginAPIError.decoding("\(label) is nested too deeply")
        }
        guard let data = raw.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(value)
        else {
            throw PluginAPIError.decoding("\(label) must contain valid JSON")
        }
        return value
    }

    private func configurationObject(_ raw: String?) throws -> [String: Any] {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return [:] }
        guard Self.isWithinJSONNestingLimit(raw) else {
            throw PluginAPIError.decoding("configuration is nested too deeply")
        }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw PluginAPIError.decoding("configuration must be a JSON object")
        }
        return object
    }

    private func requiredPageURL(_ action: AgentAction) throws -> String {
        guard let raw = action.url?.trimmed, let valid = validPageURL(raw) else {
            throw PluginAPIError.decoding("a full http(s) page URL is required")
        }
        return valid
    }

    private func canonicalPageURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return raw }
        components.fragment = nil
        return components.string ?? raw
    }

    private func canonicalOrigin(_ raw: String) -> String {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased()
        else { return "" }
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    private func validPageURL(_ raw: String) -> String? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count <= 8_192,
              clean.rangeOfCharacter(from: .controlCharacters) == nil,
              !clean.contains("\\"),
              let url = URL(string: clean),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              PluginAPIClient.isPublicNetworkHost(host),
              url.user == nil,
              url.password == nil,
              !urlContainsSensitiveQuery(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        // Ordinary fragments stay in the browser and are never sent in an HTTP
        // request; credential-shaped fragments were rejected by the guard above.
        components.fragment = nil
        return components.string ?? clean
    }

    private func urlContainsSensitiveQuery(_ url: URL, depth: Int = 0) -> Bool {
        // A query value can itself contain another URL. Bound that recursive
        // inspection so a deliberately deep chain cannot exhaust the stack
        // before the request reaches the normal nesting limit.
        guard depth < 6 else { return true }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        if let items = components.queryItems {
            for item in items {
                if isSensitiveFieldName(item.name) || isCredentialShapedValue(item.value) {
                    return true
                }
                var probe = item.value
                for _ in 0..<3 {
                    if isCredentialShapedValue(probe) { return true }
                    guard let decoded = probe.removingPercentEncoding, decoded != probe else { break }
                    probe = decoded
                }
                for nested in PluginAPIClient.absoluteURLs(in: item.value) + PluginAPIClient.httpURLs(in: item.value) {
                    if nested.user != nil || nested.password != nil || urlContainsSensitiveQuery(nested, depth: depth + 1) {
                        return true
                    }
                }
            }
        }
        // Fragments are not sent in an HTTP request, but a credential-shaped
        // fragment can still be embedded in a nested configuration value and
        // would otherwise be uploaded as part of that value.
        if let fragment = components.fragment,
           !fragment.isEmpty,
           (isSensitiveFieldName(fragment) || isCredentialShapedValue(fragment)) {
            return true
        }
        return false
    }

    private func validApprovedCrawl4AIEndpoint(_ raw: String, for kind: Crawl4AIServiceKind) -> Bool {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .server {
            return validServerURL(clean) != nil
        }
        guard let url = URL(string: clean),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "api.crawl4ai.com",
              url.port == nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.isEmpty || url.path == "/"
        else { return false }
        return true
    }

    private func validServerURL(_ raw: String) -> String? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count <= 2_048,
              clean.rangeOfCharacter(from: .controlCharacters) == nil,
              !clean.contains("\\"),
              let url = URL(string: clean),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil
        else { return nil }
        return clean
    }

    // MARK: - Bounded output

    nonisolated private static func renderCrawl4AI(
        operation: Crawl4AIOperation,
        data: Data,
        format: String?,
        limit: Int
    ) -> String {
        guard !Task.isCancelled else { return "" }
        if let object = try? Self.decodedObject(data) {
            switch operation {
            case .markdown:
                if let markdown = object["markdown"] as? String {
                    return PluginAPIClient.sanitizeAndTruncate(PluginAPIClient.sanitizeHTML(markdown), limit: limit)
                }
            case .html:
                if let html = object["html"] as? String {
                    return PluginAPIClient.sanitizeAndTruncate(
                        PluginAPIClient.sanitizeHTML(html),
                        limit: limit
                    )
                }
            case .ask:
                if let answer = object["answer"] as? String {
                    return PluginAPIClient.sanitizeAndTruncate(PluginAPIClient.sanitizeHTML(answer), limit: limit)
                }
            case .answer:
                if let answer = object["answer"] as? String {
                    return PluginAPIClient.sanitizeAndTruncate(PluginAPIClient.sanitizeHTML(answer), limit: limit)
                }
                if let answer = object["answer"] as? [String: Any],
                   let text = answer["text"] as? String {
                    var sections = [("ANSWER", text)]
                    if let sources = answer["sources"], !(sources is NSNull) {
                        sections.append(("SOURCES", Self.compactObject(
                            (sources as? [String: Any]) ?? ["values": sources],
                            limit: limit / 2
                        )))
                    }
                    return Self.boundedSections(sections, limit: limit)
                }
            case .structuredExtract:
                if let data = object["data"] {
                    let compacted = PluginAPIClient.compactJSONValue(data)
                    if JSONSerialization.isValidJSONObject(compacted),
                       let encoded = try? JSONSerialization.data(withJSONObject: compacted, options: [.prettyPrinted, .sortedKeys]) {
                        return PluginAPIClient.sanitizeAndTruncate(
                            String(decoding: encoded, as: UTF8.self),
                            limit: limit
                        )
                    }
                }
            case .scrape:
                let outputFormat = (format ?? "both").trimmed.lowercased()
                var sections: [(String, String)] = []
                if outputFormat != "html", let markdown = object["markdown"] as? String, !markdown.isEmpty {
                    sections.append(("MARKDOWN", markdown))
                }
                if outputFormat != "md", let html = object["html"] as? String, !html.isEmpty {
                    sections.append(("HTML", PluginAPIClient.sanitizeHTML(html)))
                }
                var parsed = (object["parse"] as? [String: Any]) ?? [:]
                for key in ["links", "media", "metadata", "tables"] where object[key] != nil {
                    parsed[key] = object[key]
                }
                if !parsed.isEmpty {
                    sections.append(("PARSED", Self.compactObject(parsed, limit: limit / 2)))
                }
                if !sections.isEmpty {
                    return Self.boundedSections(sections, limit: limit)
                }
            default:
                break
            }
        }
        if let compact = PluginAPIClient.compactJSONText(from: data, limit: limit) {
            return compact
        }
        return PluginAPIClient.sanitizeAndTruncate(
            PluginAPIClient.sanitizeHTML(String(decoding: data, as: UTF8.self)),
            limit: limit
        )
    }

    nonisolated private static func boundedSections(_ sections: [(String, String)], limit: Int) -> String {
        let available = max(1_000, limit)
        let perSection = max(1_000, (available - sections.count * 24) / max(sections.count, 1))
        let body = sections.map { heading, value in
            "\(heading):\n\(PluginAPIClient.sanitizeAndTruncate(PluginAPIClient.sanitizeHTML(value), limit: perSection))"
        }.joined(separator: "\n\n")
        return PluginAPIClient.sanitizeAndTruncate(body, limit: available)
    }

    nonisolated private static func compactObject(_ object: [String: Any], limit: Int) -> String {
        let compacted = PluginAPIClient.compactJSONValue(object)
        guard JSONSerialization.isValidJSONObject(compacted),
              let data = try? JSONSerialization.data(withJSONObject: compacted, options: [.prettyPrinted, .sortedKeys])
        else { return "{}" }
        return PluginAPIClient.sanitizeAndTruncate(String(decoding: data, as: UTF8.self), limit: limit)
    }

    nonisolated private static func compactNDJSON(_ data: Data, limit: Int) -> String {
        guard !Task.isCancelled else { return "" }
        let allLines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
        let lines = allLines.prefix(80)
        var objects: [Any] = []
        for line in lines {
            guard !Task.isCancelled else { return "" }
            guard let value = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else { continue }
            objects.append(PluginAPIClient.compactJSONValue(value))
        }
        guard JSONSerialization.isValidJSONObject(objects),
              let encoded = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
        else { return "Crawl4AI stream returned no readable JSON records." }
        var text = String(decoding: encoded, as: UTF8.self)
        if allLines.count > lines.count {
            text += "\n…[\(allLines.count - lines.count) additional stream records omitted; use the next page/cursor to continue]"
        }
        return PluginAPIClient.sanitizeAndTruncate(text, limit: limit)
    }

    private func remoteIdentifier(from data: Data) -> String? {
        guard let object = try? Self.decodedObject(data) else { return nil }
        let raw = stringValue(object["task_id"])
            ?? stringValue(object["job_id"])
            ?? stringValue(object["id"])
        return raw.flatMap { safeProviderIdentifier($0) }
    }

    nonisolated private static func crawlResultCount(from data: Data) -> Int? {
        guard !Task.isCancelled else { return nil }
        guard let object = try? Self.decodedObject(data),
              let results = object["results"] as? [Any]
        else { return nil }
        return results.count
    }

    nonisolated private static func decodedObject(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw PluginAPIError.decoding("expected a JSON object") }
        return object
    }

    private func uniqueURLs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { raw in
            guard let valid = validPageURL(raw), seen.insert(valid).inserted else { return nil }
            return valid
        }
    }

    private func boundedRequestCharacters(_ action: AgentAction) -> Int {
        let scalarValues = [
            action.plugin, action.operation, action.identifier, action.url, action.query, action.filter, action.format,
            action.instruction, action.jsonSchema, action.example, action.proxy, action.country,
            action.provider, action.keyword, action.configuration, action.botType, action.status,
            action.createdFrom, action.createdTo, action.text,
        ].compactMap { $0?.utf8.count }.reduce(0, +)
        let listValues = (action.urls ?? []).reduce(0) { $0 + $1.utf8.count }
            + (action.inputParameters ?? []).reduce(0) { $0 + $1.name.utf8.count + $1.value.utf8.count }
            + (action.scripts ?? []).reduce(0) { $0 + $1.utf8.count }
            + (action.includePatterns ?? []).reduce(0) { $0 + $1.utf8.count }
            + (action.excludePatterns ?? []).reduce(0) { $0 + $1.utf8.count }
        return scalarValues + listValues
    }

    private func hasPluginArguments(_ action: AgentAction) -> Bool {
        let values: [Bool] = [
            !(action.identifier?.trimmed.isEmpty ?? true),
            !(action.url?.trimmed.isEmpty ?? true),
            !(action.urls?.isEmpty ?? true),
            !(action.inputParameters?.isEmpty ?? true),
            !(action.query?.trimmed.isEmpty ?? true),
            !(action.filter?.trimmed.isEmpty ?? true),
            !(action.format?.trimmed.isEmpty ?? true),
            !(action.instruction?.trimmed.isEmpty ?? true),
            !(action.jsonSchema?.trimmed.isEmpty ?? true),
            !(action.example?.trimmed.isEmpty ?? true),
            !(action.proxy?.trimmed.isEmpty ?? true),
            !(action.country?.trimmed.isEmpty ?? true),
            action.parseAll != nil,
            action.parseLinks != nil,
            action.parseMedia != nil,
            action.parseMetadata != nil,
            action.parseTables != nil,
            action.rich != nil,
            action.deep != nil,
            action.bypassCache != nil,
            action.after != nil,
            !(action.provider?.trimmed.isEmpty ?? true),
            !(action.keyword?.trimmed.isEmpty ?? true),
            !(action.scripts?.isEmpty ?? true),
            !(action.configuration?.trimmed.isEmpty ?? true),
            action.waitSeconds != nil,
            action.waitForImages != nil,
            !(action.botType?.trimmed.isEmpty ?? true),
            !(action.status?.trimmed.isEmpty ?? true),
            !(action.createdFrom?.trimmed.isEmpty ?? true),
            !(action.createdTo?.trimmed.isEmpty ?? true),
            action.sameOrigin != nil,
            action.excludeExternalLinks != nil,
            !(action.includePatterns?.isEmpty ?? true),
            !(action.excludePatterns?.isEmpty ?? true),
            action.depth != nil,
            action.maxPages != nil,
            action.limit != nil,
            action.page != nil,
            action.temperature != nil,
            !(action.text?.trimmed.isEmpty ?? true),
        ]
        return values.contains(true)
    }

    nonisolated private static func remoteObjectSignalsFailure(_ object: [String: Any]?, depth: Int = 0) -> Bool {
        guard let object, depth < 4 else { return false }
        if let success = object["success"] as? Bool, success == false { return true }
        if let ok = object["ok"] as? Bool, ok == false { return true }
        if let error = object["error"], !(error is NSNull),
           !((error as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            return true
        }
        let failureStates: Set<String> = [
            "error", "failed", "failure", "fail", "timeout", "unavailable", "rejected", "denied", "cancelled", "canceled",
        ]
        for key in ["status", "state"] {
            if let status = (object[key] as? String)?.trimmed.lowercased(), failureStates.contains(status) {
                return true
            }
        }
        for key in ["data", "result", "response"] {
            if let nested = object[key] as? [String: Any],
               Self.remoteObjectSignalsFailure(nested, depth: depth + 1) {
                return true
            }
            if let nested = object[key] as? [Any] {
                for value in nested {
                    if let dictionary = value as? [String: Any],
                       Self.remoteObjectSignalsFailure(dictionary, depth: depth + 1) {
                        return true
                    }
                }
            }
        }
        return false
    }

    nonisolated private static func responseSignalsFailure(_ data: Data, object: [String: Any]? = nil) -> Bool {
        if Self.remoteObjectSignalsFailure(object) { return true }
        // This scan can walk a multi-megabyte body; stop as soon as the caller
        // has cancelled instead of finishing work nobody will read.
        if Task.isCancelled { return false }
        if object == nil,
           let value = try? JSONSerialization.jsonObject(with: data) {
            if let dictionary = value as? [String: Any],
               Self.remoteObjectSignalsFailure(dictionary) {
                return true
            }
            if let array = value as? [Any] {
                for element in array {
                    if Task.isCancelled { return false }
                    if let dictionary = element as? [String: Any],
                       Self.remoteObjectSignalsFailure(dictionary) {
                        return true
                    }
                }
            }
        }
        let prefix = String(decoding: data.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let failurePrefixes = [
            "error", "failed", "failure", "fail", "timeout", "unavailable", "invalid", "unauthorized", "forbidden", "denied",
            "not found", "cancelled", "canceled",
        ]
        return failurePrefixes.contains { prefix.hasPrefix($0) || prefix.contains("\($0):") }
    }

    nonisolated private static func ndjsonSignalsFailure(_ data: Data) -> Bool {
        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .prefix(200)
        for line in lines {
            if Task.isCancelled { return false }
            let lineData = Data(line.utf8)
            if Self.responseSignalsFailure(lineData) { return true }
            guard let value = try? JSONSerialization.jsonObject(with: lineData) else { continue }
            if let dictionary = value as? [String: Any], Self.remoteObjectSignalsFailure(dictionary) {
                return true
            }
            if let array = value as? [Any] {
                for element in array {
                    if let dictionary = element as? [String: Any], Self.remoteObjectSignalsFailure(dictionary) {
                        return true
                    }
                }
            }
        }
        return false
    }

    nonisolated private static func safeRemoteStatus(_ value: Any?) -> String {
        let raw = (value as? String)?.trimmed.lowercased() ?? ""
        let allowed: Set<String> = [
            "created", "running", "pausing", "paused", "finished", "canceled", "cancelled", "failed",
        ]
        return allowed.contains(raw) ? raw : "unknown"
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func saveCredential(_ raw: String, account: PluginCredentialStore.Account) {
        let clean = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_096))
        guard !clean.isEmpty else { return }
        do {
            try credentials.save(clean, account: account)
            credentialNote = nil
            refreshCredentialState()
        } catch {
            credentialNote = error.localizedDescription
        }
    }

    private func removeCredential(_ account: PluginCredentialStore.Account) {
        do {
            try credentials.remove(account)
            credentialNote = nil
            refreshCredentialState()
        } catch {
            credentialNote = error.localizedDescription
        }
    }

    private func failure(_ reason: String) -> PluginExecutionResult {
        let safeReason = PluginAPIClient.sanitizeAndTruncate(reason, limit: 1_000)
        AppLog.plugin.error("Plugin execution failed: \(safeReason, privacy: .private)")
        return PluginExecutionResult(summary: "Plugin error: \(safeReason)", extracted: nil, succeeded: false)
    }
}
