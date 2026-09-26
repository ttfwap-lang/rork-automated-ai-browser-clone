import Foundation
import CryptoKit

/// One action decided by the model. All fields are optional except `type`;
/// which fields matter depends on the action kind.
nonisolated struct AgentAction: Codable, Equatable {
    /// One element-and-text pair of a one-shot form fill.
    nonisolated struct FormField: Codable, Equatable {
        let element: Int
        let text: String
    }

    /// One named value expected by a BrowserAct Bot or template.
    nonisolated struct PluginInput: Codable, Equatable, Sendable {
        let name: String
        let value: String
    }

    var type: String
    /// Badge number of the targeted element (element-targeted moves).
    var element: Int?
    /// Resolved descriptor of the targeted element, e.g. `button "Add to cart"`.
    /// Filled in by the app from the page observation — not by the model.
    var elementName: String?
    var x: Double?
    var y: Double?
    var text: String?
    var submit: Bool?
    var direction: String?
    var amount: Double?
    var url: String?
    var summary: String?
    var reason: String?
    /// Dropdown option text (select_option).
    var option: String?
    /// Desired toggle state (set_toggle).
    var on: Bool?
    /// Slider target as percent 0–100 (set_slider).
    var value: Double?
    /// Field/text pairs for the one-shot form fill (fill_form).
    var fields: [FormField]?
    /// Drag source element number (drag).
    var from: Int?
    /// Drag target element number (drag).
    var to: Int?
    /// Drag coordinate fallbacks, normalized 0–1000 (drag).
    var fromX: Double?
    var fromY: Double?
    var toX: Double?
    var toY: Double?
    /// Mission-plan task number this move serves, as reported by the model.
    var task: Int?
    /// Task numbers the model can SEE are finished on the current screen.
    var completedTasks: [Int]?
    /// Replacement tasks for the remainder of the plan (revise_plan).
    var tasks: [PlannedTask]?
    /// Checkpoint number to go back to (rewind).
    var bookmark: Int?

    // MARK: - Optional external plugins

    /// `browseract` or `crawl4ai`; nil for the built-in WebKit browser.
    var plugin: String?
    /// App-resolved service origin shown in the approval card. The model cannot
    /// supply or override this value.
    var approvalEndpoint: String?
    /// App-resolved request-shaping facts (configured IDs, implicit input mapping,
    /// waits, and artifact handling) shown only in the local approval UI.
    var approvalNotes: [String]?
    /// App-only execution snapshot. These fields prevent settings changed while an
    /// approval is open from silently changing the already-approved destination or
    /// credential scope.
    var approvalServiceKind: String?
    var resolvedTargetParameter: String?
    var resolvedProxyRegion: String?
    var resolvedWaitSeconds: Double?
    /// A provider-specific operation, validated again inside `PluginManager`.
    var operation: String?
    /// Provider task, Bot, template, recipe, job, or artifact identifier, depending on the operation.
    var identifier: String?
    /// Named values passed to a BrowserAct Bot or template.
    var inputParameters: [PluginInput]?
    /// URL list for a multi-page Crawl4AI request.
    var urls: [String]?
    /// Natural-language question or content filter query.
    var query: String?
    /// Crawl4AI markdown filter (`fit`, `raw`, `bm25`, or `llm`).
    var filter: String?
    /// Cloud scrape output format (`md`, `html`, or `both`).
    var format: String?
    /// Cloud structured-extraction instruction.
    var instruction: String?
    /// JSON Schema string for Cloud structured extraction.
    var jsonSchema: String?
    /// Optional JSON example object for Cloud structured extraction.
    var example: String?
    /// Optional Cloud proxy tier and two-letter country code.
    var proxy: String?
    var country: String?
    var parseAll: Bool?
    var parseLinks: Bool?
    var parseMedia: Bool?
    var parseMetadata: Bool?
    var parseTables: Bool?
    var rich: Bool?
    var deep: Bool?
    var bypassCache: Bool?
    /// Cursor used for paged Cloud scrape-job results.
    var after: Int?
    /// Optional server-side model provider override.
    var provider: String?
    /// BrowserAct/Crawl4AI filter, Crawl4AI cache revision, or Cloud estimate endpoint.
    var keyword: String?
    /// JavaScript snippets for Crawl4AI's optional `execute_js` endpoint.
    var scripts: [String]?
    /// JSON configuration accepted by a remote crawler/server.
    var configuration: String?
    /// How long a run or screenshot operation should wait, in seconds.
    var waitSeconds: Double?
    /// Whether Crawl4AI should wait for images before a screenshot.
    var waitForImages: Bool?
    /// Optional BrowserAct v3 list filters.
    var botType: String?
    var status: String?
    var createdFrom: String?
    var createdTo: String?
    /// Whether local link discovery leaves the current site.
    var sameOrigin: Bool?
    /// Whether Crawl4AI excludes links to other origins.
    var excludeExternalLinks: Bool?
    /// Crawl include/exclude glob patterns and breadth/depth controls.
    var includePatterns: [String]?
    var excludePatterns: [String]?
    var depth: Int?
    var maxPages: Int?
    var limit: Int?
    var page: Int?
    var temperature: Double?

    var kind: AgentActionKind {
        AgentActionKind(rawValue: type.lowercased()) ?? .unknown
    }

    /// Short human-readable parameter string for step cards and logs.
    var detailText: String {
        switch kind {
        case .tapElement, .longPress, .hover:
            return targetDescriptor
        case .typeInto:
            let quoted = "\"\(String((text ?? "").prefix(40)))\""
            let suffix = submit == true ? " + enter" : ""
            return "\(quoted) → \(targetDescriptor)\(suffix)"
        case .fillForm:
            let count = fields?.count ?? 0
            return "\(count) field\(count == 1 ? "" : "s")\(submit == true ? " + submit" : "")"
        case .fillFromDossier:
            return "from your dossier\(submit == true ? " + submit" : "")"
        case .selectOption:
            return "\"\(String((option ?? "?").prefix(32)))\" → \(targetDescriptor)"
        case .setToggle:
            return "\(targetDescriptor) → \(on == false ? "OFF" : "ON")"
        case .setSlider:
            return "\(targetDescriptor) → \(Int(value ?? 50))%"
        case .drag:
            let source = from.map { "[\($0)]" } ?? "(\(Int(fromX ?? 0)), \(Int(fromY ?? 0)))"
            let target = to.map { "[\($0)]" } ?? "(\(Int(toX ?? 0)), \(Int(toY ?? 0)))"
            return "\(source) → \(target)"
        case .swipe:
            let dir = direction ?? "left"
            return element.map { "\(dir) [\($0)]" } ?? dir
        case .tap:
            return "(\(Int(x ?? 0)), \(Int(y ?? 0)))"
        case .typeText:
            let quoted = "\"\(String((text ?? "").prefix(48)))\""
            return submit == true ? quoted + " + enter" : quoted
        case .scroll:
            return "\(direction ?? "down") \(Int(amount ?? 600))px"
        case .navigate:
            return url ?? ""
        case .extract:
            return "whole page"
        case .runPlugin:
            let provider = plugin ?? "plugin"
            let call = operation ?? "call"
            if let url = url?.trimmed, !url.isEmpty {
                return "\(provider) · \(call) · \(RecipeMove.shortAddress(url))"
            }
            // Provider IDs are shown in the local exact-request disclosure, not
            // in the durable step detail. Keeping them out of history prevents
            // an accidentally credential-shaped ID from being copied to disk.
            return "\(provider) · \(call)"
        case .pageOverview:
            return "up to 6 screens"
        case .wait:
            return "2s"
        case .back:
            return ""
        case .revisePlan:
            let count = tasks?.count ?? 0
            let plural = count == 1 ? "" : "s"
            return "\(count) task\(plural) ahead — \(reason ?? "the plan no longer fits")"
        case .done:
            return summary ?? ""
        case .fail:
            return reason ?? ""
        case .rewind:
            return "to checkpoint \(bookmark ?? 0) — \(reason ?? "this route is dead")"
        case .verify:
            return summary ?? ""
        case .headStart:
            return summary ?? ""
        case .replay:
            return summary ?? ""
        case .mistake:
            return summary ?? ""
        case .unknown:
            return type
        }
    }

    /// The move in plain words, with no element numbers — for the live panel,
    /// where the point is to read what the agent is doing at a glance rather than
    /// to audit it.
    var plainSentence: String {
        let target = (elementName ?? "").trimmed
        let named = target.isEmpty ? nil : target
        switch kind {
        case .tapElement:
            return named.map { "tap the \($0)" } ?? "tap a control"
        case .longPress:
            return named.map { "press and hold the \($0)" } ?? "press and hold"
        case .hover:
            return named.map { "hover over the \($0)" } ?? "hover"
        case .typeInto, .typeText:
            let where_ = named.map { " into the \($0)" } ?? ""
            let quoted = (text ?? "").isEmpty ? "" : " “\(String((text ?? "").prefix(28)))”"
            return "type\(quoted)\(where_)\(submit == true ? " and press enter" : "")"
        case .fillForm:
            let count = fields?.count ?? 0
            return "fill in \(count) field\(count == 1 ? "" : "s")\(submit == true ? " and submit" : "")"
        case .fillFromDossier:
            return "fill this form in from your dossier\(submit == true ? " and submit" : "")"
        case .selectOption:
            let option = (option ?? "").isEmpty ? "an option" : "“\(String((option ?? "").prefix(24)))”"
            return named.map { "choose \(option) from the \($0)" } ?? "choose \(option)"
        case .setToggle:
            return "turn the \(named ?? "switch") \(on == false ? "off" : "on")"
        case .setSlider:
            return "set the \(named ?? "slider") to \(Int(value ?? 50))%"
        case .drag:
            return "drag one thing onto another"
        case .swipe:
            return "swipe \(direction ?? "left")"
        case .tap:
            return "tap a spot on the page"
        case .scroll:
            return "scroll \(direction ?? "down")"
        case .navigate:
            return "open \(RecipeMove.shortAddress(url ?? ""))"
        case .back:
            return "go back"
        case .extract:
            return "read the whole page"
        case .runPlugin:
            let provider: String
            if plugin == BrowserPluginID.browserAct.rawValue {
                provider = "BrowserAct"
            } else if plugin == BrowserPluginID.crawl4AI.rawValue {
                provider = "Crawl4AI"
            } else {
                provider = "the external plugin"
            }
            let call = (operation ?? "run").replacingOccurrences(of: "_", with: " ")
            return "use \(provider) to \(call)"
        case .pageOverview:
            return "look at the whole page at once"
        case .wait:
            return "wait for the page"
        case .revisePlan:
            let count = tasks?.count ?? 0
            return "rewrite the plan — \(count) task\(count == 1 ? "" : "s") ahead"
        case .rewind:
            return "go back to checkpoint \(bookmark ?? 0)"
        case .done:
            return "call it done"
        case .fail:
            return "report that this cannot be done"
        case .verify, .headStart, .replay, .mistake, .unknown:
            return kind.label.lowercased()
        }
    }

    /// `[14] button "Add to cart"` when resolved, `[14]` otherwise.
    private var targetDescriptor: String {
        let number = "[\(element ?? 0)]"
        guard let elementName, !elementName.isEmpty else { return number }
        return "\(number) \(elementName)"
    }

    /// External calls can spend a paid service's credits, run JavaScript on a
    /// remote page, create tasks, or stop them. They therefore always stop for a
    /// person, even when the local run itself is in autopilot.
    var requiresUserApproval: Bool { kind == .runPlugin }

    /// A value-redacted approval line for external calls. It names the service,
    /// destination pages, request shape, and any remote follow-up the user is
    /// approving, but keeps values inside the exact local disclosure below.
    var externalApprovalSummary: String? {
        guard kind == .runPlugin else { return nil }
        let provider = plugin == BrowserPluginID.browserAct.rawValue ? "BrowserAct" : "Crawl4AI"
        var parts = ["External call to \(provider)"]
        if let plugin, !plugin.isEmpty { parts.append("plugin: \(String(plugin.prefix(64)))") }
        if let operation { parts.append("operation: \(String(operation.prefix(80)))") }
        if let endpoint = approvalEndpoint?.trimmed, !endpoint.isEmpty {
            parts.append("service: \(RecipeMove.shortAddress(endpoint))")
        }
        for note in approvalNotes ?? [] where !note.isEmpty {
            parts.append(String(note.prefix(140)))
        }

        var destinationValues: [String] = []
        if let pageURL = url?.trimmed, !pageURL.isEmpty { destinationValues.append(pageURL) }
        destinationValues.append(contentsOf: urls ?? [])
        var seenDestinations = Set<String>()
        let destinations = destinationValues.filter { seenDestinations.insert($0).inserted }
        if !destinations.isEmpty {
            let visible = destinations.prefix(3).map { RecipeMove.shortAddress($0) }
            let suffix = destinations.count > 3 ? " +\(destinations.count - 3) more" : ""
            parts.append("destinations: \(visible.joined(separator: ", "))\(suffix)")
            let queryCount = destinations.filter { URL(string: $0)?.query?.isEmpty == false }.count
            if queryCount > 0 {
                parts.append("\(queryCount) URL\(queryCount == 1 ? "" : "s") include values available in the exact-request disclosure")
            }
        }

        let inputNames = (inputParameters ?? []).map { $0.name }.filter { !$0.isEmpty }
        if !inputNames.isEmpty {
            parts.append("input fields: \(inputNames.joined(separator: ", ").prefix(120))")
        }
        if let scripts, !scripts.isEmpty {
            parts.append("JavaScript: \(scripts.count) snippet\(scripts.count == 1 ? "" : "s")")
        }
        if text?.trimmed.isEmpty == false { parts.append("inline content supplied") }
        if let rawConfiguration = configuration?.trimmed, !rawConfiguration.isEmpty {
            let parsedConfiguration = try? JSONSerialization.jsonObject(with: Data(rawConfiguration.utf8))
            let object = (parsedConfiguration as? [String: Any]) ?? [:]
            let keys = object.keys.sorted()
            if !keys.isEmpty { parts.append("config keys: \(keys.joined(separator: ", ").prefix(100))") }
            if let inputKeys = (object["input"] as? [String: Any])?.keys.sorted(), !inputKeys.isEmpty {
                parts.append("typed input fields: \(inputKeys.joined(separator: ", ").prefix(120))")
            }
        }
        if query?.trimmed.isEmpty == false { parts.append("question/filter supplied") }
        if let proxy = proxy?.trimmed, !proxy.isEmpty { parts.append("proxy: \(proxy)") }
        if let country = country?.trimmed, !country.isEmpty { parts.append("country: \(country)") }
        if bypassCache == true { parts.append("cache bypass requested") }
        if operation == "discover" {
            parts.append(sameOrigin == false
                ? "rendered links may leave the current site"
                : "rendered links stay on the current hostname")
        }
        if let maxPages {
            parts.append("remote crawl may follow links across up to \(maxPages) pages")
        } else if let depth {
            parts.append("remote crawl may follow links to depth \(depth)")
        }
        return parts.joined(separator: " · ")
    }

    /// Complete, bounded request arguments for the local approval disclosure.
    /// Every value that preflight can send is represented here; the normal
    /// per-field limits match the adapter's limits. The preview is local-only:
    /// it is never copied to run history, logs, memory, or a model prompt.
    var externalRequestPreview: String? {
        guard kind == .runPlugin else { return nil }
        let normalizedOperation = operation?.trimmed.lowercased()
        var lines: [String] = ["operation: \(normalizedOperation ?? "unknown")"]

        func bounded(_ value: String, _ limit: Int) -> String {
            guard value.count > limit else { return value }
            return String(value.prefix(limit)) + "…[\(value.count - limit) characters omitted by local preview]"
        }

        if let endpoint = approvalEndpoint?.trimmed, !endpoint.isEmpty {
            lines.append("service: \(bounded(endpoint, 2_048))")
        }
        if let serviceKind = approvalServiceKind?.trimmed, !serviceKind.isEmpty {
            lines.append("service_kind: \(serviceKind)")
        }
        for note in approvalNotes ?? [] where !note.isEmpty {
            lines.append("app-resolved: \(bounded(note, 1_000))")
        }
        if let target = resolvedTargetParameter?.trimmed, !target.isEmpty {
            lines.append("resolved_target_parameter: \(bounded(target, 200))")
        }
        if let region = resolvedProxyRegion?.trimmed, !region.isEmpty {
            lines.append("resolved_proxy_region: \(bounded(region, 64))")
        }
        if let wait = resolvedWaitSeconds {
            lines.append("resolved_wait_seconds: \(wait)")
        }
        if let identifier = identifier?.trimmed, !identifier.isEmpty {
            lines.append("identifier: \(bounded(identifier, 512))")
        }
        if let pageURL = url?.trimmed, !pageURL.isEmpty {
            lines.append("url: \(bounded(pageURL, 8_192))")
        }
        for candidate in urls ?? [] {
            lines.append("url: \(bounded(candidate, 8_192))")
        }
        for pair in inputParameters ?? [] {
            lines.append("input.\(bounded(pair.name, 200)): \(bounded(pair.value, 4_000))")
        }
        if let query = query?.trimmed, !query.isEmpty { lines.append("query: \(bounded(query, 4_000))") }
        if let instruction = instruction?.trimmed, !instruction.isEmpty { lines.append("instruction: \(bounded(instruction, 4_000))") }
        if let content = text?.trimmed, !content.isEmpty { lines.append("inline content: \(bounded(content, 200_000))") }
        for script in scripts ?? [] { lines.append("script: \(bounded(script, 20_000))") }
        if let config = configuration?.trimmed, !config.isEmpty { lines.append("configuration: \(bounded(config, 100_000))") }
        if let filter = filter?.trimmed, !filter.isEmpty { lines.append("filter: \(bounded(filter, 32))") }
        if let format = format?.trimmed, !format.isEmpty { lines.append("format: \(bounded(format, 16))") }
        if let schema = jsonSchema?.trimmed, !schema.isEmpty { lines.append("json_schema: \(bounded(schema, 100_000))") }
        if let sample = example?.trimmed, !sample.isEmpty { lines.append("example: \(bounded(sample, 100_000))") }
        if let proxy = proxy?.trimmed, !proxy.isEmpty { lines.append("proxy: \(bounded(proxy, 32))") }
        if let country = country?.trimmed, !country.isEmpty { lines.append("country: \(bounded(country, 8))") }
        if let provider = provider?.trimmed, !provider.isEmpty { lines.append("provider: \(bounded(provider, 500))") }
        if let keyword = keyword?.trimmed, !keyword.isEmpty { lines.append("keyword: \(bounded(keyword, 500))") }
        if let botType = botType?.trimmed, !botType.isEmpty { lines.append("bot_type: \(bounded(botType, 32))") }
        if let status = status?.trimmed, !status.isEmpty { lines.append("status: \(bounded(status, 32))") }
        if let createdFrom = createdFrom?.trimmed, !createdFrom.isEmpty { lines.append("created_from: \(bounded(createdFrom, 100))") }
        if let createdTo = createdTo?.trimmed, !createdTo.isEmpty { lines.append("created_to: \(bounded(createdTo, 100))") }
        for pattern in includePatterns ?? [] { lines.append("include_pattern: \(bounded(pattern, 300))") }
        for pattern in excludePatterns ?? [] { lines.append("exclude_pattern: \(bounded(pattern, 300))") }
        if let after { lines.append("after: \(after)") }
        if let depth { lines.append("depth: \(depth)") }
        if let maxPages { lines.append("max_pages: \(maxPages)") }
        if let limit { lines.append("limit: \(limit)") }
        if let page { lines.append("page: \(page)") }
        if let waitSeconds { lines.append("wait_seconds: \(waitSeconds)") }
        if let temperature { lines.append("temperature: \(temperature)") }
        if let sameOrigin { lines.append("same_origin: \(sameOrigin)") }
        if let excludeExternalLinks { lines.append("exclude_external_links: \(excludeExternalLinks)") }
        if let waitForImages { lines.append("wait_for_images: \(waitForImages)") }
        if let parseAll { lines.append("parse_all: \(parseAll)") }
        if let parseLinks { lines.append("parse_links: \(parseLinks)") }
        if let parseMedia { lines.append("parse_media: \(parseMedia)") }
        if let parseMetadata { lines.append("parse_metadata: \(parseMetadata)") }
        if let parseTables { lines.append("parse_tables: \(parseTables)") }
        if let rich { lines.append("rich: \(rich)") }
        if let deep { lines.append("deep: \(deep)") }
        if let bypassCache { lines.append("bypass_cache: \(bypassCache)") }

        // These are the app-injected values that are easy to miss in a raw
        // argument echo. Listing them makes the disclosure describe the request
        // that will actually be serialized.
        switch normalizedOperation {
        case "scrape", "batch", "scrape_job":
            lines.append("effective_format: \((format ?? "both").trimmed.lowercased())")
            lines.append("effective_parse: \(parseAll == true ? "all" : (parseLinks == true || parseMedia == true || parseMetadata == true || parseTables == true ? "selected" : "false"))")
            if let proxy = proxy?.trimmed.lowercased(), !proxy.isEmpty { lines.append("effective_proxy: \(proxy)") }
            if let country = country?.trimmed.lowercased(), !country.isEmpty { lines.append("effective_country: \(country)") }
        case "search":
            lines.append("effective_rich: \(rich == true)")
        case "answer":
            lines.append("effective_deep: \(deep != false)")
        case "markdown":
            lines.append("effective_filter: \(filter ?? "fit")")
            lines.append("effective_cache_revision: \(keyword ?? "0")")
        case "llm_job":
            lines.append("effective_cache: false")
        case "screenshot":
            // The approved snapshot is what runs, so the preview must name that
            // value rather than the raw argument.
            lines.append("effective_wait_seconds: \(resolvedWaitSeconds ?? waitSeconds ?? 2)")
        case "recipe_run":
            lines.append("effective_bypass_cache: \(bypassCache == true)")
        case "crawl", "stream", "discover", "crawl_job":
            lines.append("effective_browser_config: provided browser_config or the server default BrowserConfig")
            lines.append("effective_crawler_config: provided crawler_config or the server default CrawlerRunConfig")
            if depth != nil || maxPages != nil || !(includePatterns ?? []).isEmpty || !(excludePatterns ?? []).isEmpty {
                lines.append("effective_deep_crawl: BFSDeepCrawlStrategy with app-resolved depth/page/pattern bounds")
            }
            if operation != "crawl_job" {
                lines.append("effective_hooks: supplied declarative hooks or omitted")
            }
        case "estimate":
            lines.append("effective_endpoint: \((keyword ?? "scrape").trimmed.lowercased())")
        default:
            break
        }

        let result = lines.joined(separator: "\n")
        let previewLimit = 1_200_000
        return result.count > previewLimit
            ? String(result.prefix(previewLimit)) + "\n…[request preview capped; preflight limits the total accepted request size]"
            : result
    }

    /// Compact signature used to detect action repetition loops.
    var repetitionSignature: String {
        if kind == .runPlugin {
            let flags = [
                parseAll.map { "\($0)" } ?? "-",
                parseLinks.map { "\($0)" } ?? "-",
                parseMedia.map { "\($0)" } ?? "-",
                parseMetadata.map { "\($0)" } ?? "-",
                parseTables.map { "\($0)" } ?? "-",
                rich.map { "\($0)" } ?? "-",
                deep.map { "\($0)" } ?? "-",
                bypassCache.map { "\($0)" } ?? "-",
                waitForImages.map { "\($0)" } ?? "-",
                sameOrigin.map { "\($0)" } ?? "-",
                excludeExternalLinks.map { "\($0)" } ?? "-",
            ].joined(separator: ",")
            // Plugin arguments can contain user-supplied page content, and
            // `configuration` alone is allowed to reach 100 KB. This key is
            // recomputed for every candidate on every decision round, so bound
            // each field before hashing: a fixed prefix plus the true length
            // still separates genuinely different calls, and no raw argument
            // value is retained in memory.
            func bounded(_ value: String?, limit: Int = 512) -> String {
                guard let value, !value.isEmpty else { return "" }
                return value.count <= limit ? value : "\(value.prefix(limit))…#\(value.count)"
            }
            let canonical = [
                "run_plugin", bounded(plugin), bounded(operation), bounded(identifier),
                bounded(approvalEndpoint), bounded(approvalServiceKind),
                bounded(url), bounded((urls ?? []).joined(separator: ","), limit: 2_048),
                bounded((inputParameters ?? []).map { "\($0.name)=\($0.value)" }.joined(separator: ","), limit: 2_048),
                bounded(query), bounded(instruction), bounded(text), bounded(jsonSchema), bounded(example),
                bounded((scripts ?? []).joined(separator: ","), limit: 2_048), bounded(configuration, limit: 2_048),
                bounded(filter), bounded(format), bounded(provider), bounded(keyword), bounded(proxy), bounded(country),
                bounded(botType), bounded(status), bounded(createdFrom), bounded(createdTo),
                bounded((includePatterns ?? []).joined(separator: ","), limit: 2_048),
                bounded((excludePatterns ?? []).joined(separator: ","), limit: 2_048),
                "\(after ?? -1)|\(depth ?? -1)|\(maxPages ?? -1)|\(limit ?? -1)|\(page ?? -1)",
                "\(waitSeconds ?? -1)|\(temperature ?? -1)|\(flags)",
                bounded(resolvedTargetParameter), bounded(resolvedProxyRegion), "\(resolvedWaitSeconds ?? -1)",
            ].joined(separator: "|")
            // The digest keeps the repetition key usable without holding the
            // arguments themselves in memory.
            let digest = SHA256.hash(data: Data(canonical.utf8))
                .map { String(format: "%02x", Int($0)) }
                .joined()
            return "run_plugin|\(digest)"
        }
        let parts: [String] = [
            kind.rawValue,
            "\(element ?? -1)",
            "\(Int(x ?? -1))",
            "\(Int(y ?? -1))",
            text ?? "",
            direction ?? "",
            url ?? "",
            option ?? "",
            on.map(String.init) ?? "",
            "\(Int(value ?? -1))",
            "\(from ?? -1)",
            "\(to ?? -1)",
            "\(fields?.count ?? 0)",
            "\(bookmark ?? -1)",
            plugin ?? "",
            operation ?? "",
            identifier ?? "",
            query ?? "",
            filter ?? "",
            (urls ?? []).joined(separator: ","),
            (scripts ?? []).joined(separator: ","),
            (inputParameters ?? []).map(\.name).joined(separator: ","),
            configuration ?? "",
            proxy ?? "",
            country ?? "",
            "\(depth ?? -1)",
            "\(maxPages ?? -1)",
            "\(limit ?? -1)",
        ]
        return parts.joined(separator: "|")
    }
}
