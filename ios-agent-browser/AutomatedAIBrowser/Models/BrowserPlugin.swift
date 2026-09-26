import Foundation

/// Optional external capabilities that can be exposed to the agent. The browser
/// never loads third-party code: each plugin is a narrow, typed adapter over a
/// service's documented HTTP API.
nonisolated enum BrowserPluginID: String, CaseIterable, Identifiable, Sendable {
    case browserAct = "browseract"
    case crawl4AI = "crawl4ai"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .browserAct: "BrowserAct"
        case .crawl4AI: "Crawl4AI"
        }
    }

    var shortName: String {
        switch self {
        case .browserAct: "BrowserAct"
        case .crawl4AI: "Crawl4AI"
        }
    }

    var symbol: String {
        switch self {
        case .browserAct: "bolt.horizontal.circle.fill"
        case .crawl4AI: "wand.and.stars"
        }
    }

    var summary: String {
        switch self {
        case .browserAct:
            "Run published BrowserAct Bots and official templates in remote browser sessions, then discover inputs, inspect, resume, cancel, and monitor their tasks."
        case .crawl4AI:
            "Crawl and extract through self-hosted Crawl4AI or Crawl4AI Cloud: Markdown/HTML, structured data, search, answers, jobs, recipes, links/media, screenshots, PDFs, and server-gated JavaScript."
        }
    }

    var operationNames: [String] {
        switch self {
        case .browserAct: BrowserActOperation.allCases.map(\.rawValue)
        case .crawl4AI: Crawl4AIOperation.allCases.map(\.rawValue)
        }
    }
}

/// Every operation in BrowserAct's current v3 Bot API.
nonisolated enum BrowserActOperation: String, CaseIterable, Sendable, Hashable {
    case listBots = "list_bots"
    case getBot = "get_bot"
    case listTemplates = "list_templates"
    case getTemplate = "get_template"
    case listRegions = "list_regions"
    case runBot = "run_bot"
    case runTemplate = "run_template"
    case getTask = "get_task"
    case getStatus = "get_status"
    case resumeTask = "resume_task"
    case cancelTask = "cancel_task"
    case listTasks = "list_tasks"
}

/// Crawl4AI's self-hosted Docker/MCP data tools and Cloud REST tools. The plugin
/// exposes both surfaces through one bounded model tool; unavailable operations
/// are rejected by `PluginManager` according to the configured service kind.
nonisolated enum Crawl4AIOperation: String, CaseIterable, Sendable, Hashable {
    // Self-hosted Docker / MCP
    case crawl
    case discover
    case stream
    case markdown
    case html
    case screenshot
    case pdf
    case executeJS = "execute_js"
    case ask
    case schema
    case hooks
    case mcpSchema = "mcp_schema"
    case validateConfig = "validate_config"
    case health
    case crawlJob = "crawl_job"
    case crawlJobStatus = "crawl_job_status"
    case llmJob = "llm_job"
    case llmJobStatus = "llm_job_status"
    case artifact

    // Crawl4AI Cloud
    case scrape
    case structuredExtract = "structured_extract"
    case search
    case answer
    case batch
    case scrapeJob = "scrape_job"
    case scrapeJobStatus = "scrape_job_status"
    case scrapeJobResults = "scrape_job_results"
    case scrapeJobRetry = "scrape_job_retry"
    case recipes
    case recipeRun = "recipe_run"
    case recipeHealth = "recipe_health"
    case prices
    case balance
    case estimate

    var serviceKind: Crawl4AIServiceKind {
        switch self {
        case .scrape, .structuredExtract, .search, .answer, .batch,
             .scrapeJob, .scrapeJobStatus, .scrapeJobResults, .scrapeJobRetry,
             .recipes, .recipeRun, .recipeHealth, .prices, .balance, .estimate:
            .cloud
        default:
            .server
        }
    }
}

nonisolated enum Crawl4AIServiceKind: String, CaseIterable, Identifiable, Sendable {
    case server = "server"
    case cloud = "cloud"

    var id: String { rawValue }
    var name: String { self == .server ? "Self-hosted server" : "Crawl4AI Cloud" }
}

/// A plugin response is split into a short line for run history and a bounded
/// payload for the agent's next turn. Raw plugin output is never persisted.
nonisolated struct PluginExecutionResult: Sendable {
    let summary: String
    let extracted: String?
    /// Whether the approved remote operation completed successfully. A provider
    /// error is still useful evidence for the next model turn, but it must not
    /// advance a mission checklist or be recorded as a successful move.
    let succeeded: Bool
    /// Inline bytes for a plugin screenshot. Data is bounded by the adapter and
    /// exists only until the next decision consumes it.
    let imageData: Data?

    init(summary: String, extracted: String?, succeeded: Bool = true, imageData: Data? = nil) {
        self.summary = summary
        self.extracted = extracted
        self.succeeded = succeeded
        self.imageData = imageData
    }
}
