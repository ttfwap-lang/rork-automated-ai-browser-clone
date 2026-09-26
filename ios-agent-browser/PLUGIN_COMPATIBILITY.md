# BrowserAct and Crawl4AI compatibility plugins

The iOS app keeps its native `WKWebView` as the default browser. Two optional, server-side plugins add capabilities that are unsafe or impractical to embed in the app:

- **BrowserAct v3** runs published remote Bots and official templates in BrowserAct's managed browser environment.
- **Crawl4AI** connects either to a hardened self-hosted Docker server or to Crawl4AI Cloud for extraction, crawling, jobs, search, answers, and recipes.

No Python runtime, Playwright runtime, MCP server, or third-party code is bundled into the iOS app. The adapters call documented HTTPS APIs and are disabled until the user saves a key.

## Safety contract

- API keys and tokens are stored only in the iOS Keychain (`WhenUnlockedThisDeviceOnly`). There is no plaintext fallback.
- Crawl4AI Cloud and self-hosted tokens use separate Keychain accounts, so switching service kinds never sends a Cloud key to a self-hosted host.
- Non-secret settings use `UserDefaults`.
- The model sees a plugin tool only when the plugin is enabled, keyed, and correctly configured.
- Crawl4AI's tool schema exposes only operations for the selected service kind.
- Every model-requested external call stops for approval, even in autopilot. The Settings connection-test buttons are separate, explicit user-initiated probes.
- The approval card names the provider, service, credential scope, app-resolved Bot/template IDs, request-shaping defaults, and destinations. Those values and the credential scope are snapshotted before approval, so changing settings while the card is open cannot redirect the call. The poll/settle wait is frozen the same way: the snapshot folds in any model-supplied request, the card always states the number that will run, and execution reads the snapshot rather than the raw argument. A collapsed local disclosure shows the complete bounded argument list (the adapter rejects requests over 1 MB of combined argument characters), including full destination strings, scripts, typed configuration, and injected defaults; that preview is never written to run history or logs.
- Credential-shaped fields (`password`, `api_key`, `token`, `cookie`, `session`, `authorization`, signatures, and similar) are rejected before a remote request, including percent/entity-obfuscated spellings. The decoding probe covers `=`, whitespace, and comma entities as well as `:` and `/`, so `password&#61;…` and `Bearer&#32;…` are caught. That rejection is cancellation-independent, so pressing Stop surfaces a cancelled call rather than a false credential refusal. BrowserAct credentials belong in its hosted Bot configuration; plugin calls do not export local WebKit cookies. Page destinations reject obvious private/reserved literals and malformed hostname forms; the configured remote Crawl4AI/BrowserAct service must enforce DNS/redirect egress policy.
- A preflight refusal is an app-authored rule rather than remote output, so the model is told which rule stopped the call instead of seeing silence, and the refused call is barred for the rest of the run. Refusal text is sanitized before it is shown because it can quote a model-supplied field name, and it is marked so that only app rules — never plugin output — can be surfaced from a plugin step.
- Remote output is untrusted, stripped of large binary/raw-markup fields, cookies/headers, live-session URLs, signed download URLs, and URL query values (including URLs embedded in text, including mixed percent/HTML-entity encodings); it is bounded (6k–60k characters) and supplied to the model for one turn. Percent/entity decoding is used as a detection probe only, so a benign escape such as `100%25` reaches the model as the server sent it and the decoded form is adopted only when redaction actually fires. JSON object keys are server-controlled text, so they are bounded and redacted too, and a key that redaction had to touch is replaced by a placeholder rather than echoed, because the remainder of a partial match can still be a secret. API responses are read through a hard byte ceiling before an unbounded in-memory response can be materialized, and artifacts are rejected before persistence.
- Supplied `configuration`, `json_schema`, and `example` payloads are checked for structural depth from the raw bytes before `JSONSerialization` is asked to parse them, because a model can be steered into emitting tens of thousands of nested brackets through page text.
- Authenticated plugin calls and credential-free artifact downloads never follow HTTP redirects; artifact URLs must be HTTPS and contain no embedded credentials.
- Plugin calls are never distilled into local route memory or unattended replays. Raw plugin output, request arguments, action fields, and plugin step results are excluded from persisted run steps; only bounded, explicitly untrusted evidence is kept in memory for the next decision or the independent check.
- Cloud residential proxies, direct answers, and paid extraction still require an approved plugin call.
- Remote screenshots/PDFs and up to four BrowserAct output/download files are fetched immediately into protected app Documents storage before temporary URLs expire. BrowserAct CDN downloads never receive the BrowserAct API key, reject private/reserved literal targets, and do not follow redirects; a Crawl4AI screenshot is also attached to the next model turn as untrusted evidence. Rendering and compaction are cancellation-aware.

## Residual risks

These are known and deliberately not solved in the app; the remote service boundary is the mitigation.

- **DNS rebinding.** Artifact hosts are resolved before the request and again afterwards, but `URLSession` performs its own resolution in between, so a short-TTL attacker-controlled name can point at a loopback or private address for the actual connection. This needs a valid TLS certificate for the hostname, so the practical exposure is limited, but it cannot be closed without a pinned-IP transport. Remote egress policy is mandatory.
- **Uncancellable name resolution.** `getaddrinfo` cannot be interrupted. A stalled resolver can block past the caller's timeout, and a multi-file BrowserAct result can chain several of these lookups, so a step may overrun its budget. Cancellation is requested, not guaranteed.
- **Fully non-cancellable side effects.** Once a remote run, job, resume, cancel, recipe, or batch is accepted by the provider, the app cannot undo it. That is why each of those is an individually approved, irreversible action.
- **Validation cost on the main actor.** The preflight that must finish before the approval card can appear recompiles its regular expressions per call and runs on the main actor; a `scrape_job` with many URLs makes that pause noticeable. Caching the compiled expressions is a known optimisation, not a correctness issue.
- **Pre-existing plugin steps stay out of the run summary.** By design, plugin steps are excluded from `partialRunSummary` and persisted history, so a run whose only meaningful work was plugin calls can report that no moves completed. This is the isolation requirement, not an oversight.

## BrowserAct v3 operations

| Tool operation | BrowserAct endpoint | Support |
|---|---|---|
| `list_bots` | `GET /v3/bots` | Bot type, keyword, page, limit |
| `get_bot` | `GET /v3/bots/{bot_id}` | Input/output schemas |
| `list_templates` | `GET /v3/bots/templates` | Keyword, page, limit |
| `get_template` | `GET /v3/bots/templates/{template_id}` | Input schema |
| `list_regions` | `GET /v3/bots/regions` | Proxy-region discovery |
| `run_bot` | `POST /v3/bots/{bot_id}/runs` | v3 `input` object; optional bounded wait |
| `run_template` | `POST /v3/bots/templates/{template_id}/runs` | v3 input and optional `proxy_region` |
| `get_status` | `GET /v3/bots/runs/{task_id}/status` | Lightweight status |
| `get_task` | `GET /v3/bots/runs/{task_id}` | Output, steps, credits, errors; signed output files are fetched and redacted |
| `resume_task` | `POST /v3/bots/runs/{task_id}/resume` | Paused tasks only |
| `cancel_task` | `POST /v3/bots/runs/{task_id}/cancel` | Irreversible remote action |
| `list_tasks` | `GET /v3/bots/runs` | Bot/name/status/date filters and pagination |

The legacy v2 Workflow API is intentionally not used. BrowserAct's current OpenAPI v3 contract uses `bot_id`, `task_id`, an `input` object, and `POST` resume/cancel routes.

The desktop-oriented BrowserAct Agent CLI, Chrome profile import, CDP attachment, and Skill Forge are not iOS-compatible runtime dependencies. Published Bots are the supported cloud integration surface.

## Crawl4AI self-hosted server operations

Put a self-hosted server behind a trusted HTTPS reverse proxy. The iOS app intentionally has no cleartext-HTTP exception.

| Tool operation | Server route | Support |
|---|---|---|
| `crawl` | `POST /crawl` | Up to 100 URLs, browser/crawler config, declarative hooks |
| `discover` | local WebKit link discovery + `POST /crawl` | Rendered links are frozen and shown before approval; same-origin mode also blocks remote deep-crawl escapes |
| `stream` | `POST /crawl/stream` | Bounded NDJSON normalization |
| `markdown` | `POST /md` | `fit`, `raw`, `bm25`, and `llm` filters |
| `html` | `POST /html` | Sanitized/preprocessed HTML |
| `screenshot` | `POST /screenshot` | Full-page capture; downloaded artifact |
| `pdf` | `POST /pdf` | PDF artifact; downloaded file |
| `execute_js` | `POST /execute_js` | Only when the server explicitly enables it |
| `ask` | `GET /llm/{url}` | Page-grounded answer |
| `crawl_job` | `POST /crawl/job` | Asynchronous crawl with browser/crawler configuration; declarative hooks are rejected for this payload |
| `crawl_job_status` | `GET /crawl/job/{task_id}` | Job state/result |
| `llm_job` | `POST /llm/job` | Asynchronous structured LLM extraction |
| `llm_job_status` | `GET /llm/job/{task_id}` | Job state/result |
| `artifact` | `GET /artifacts/{artifact_id}` | Authenticated binary download into the app; screenshot/PDF results disclose their opaque artifact ID |
| `schema` | `GET /schema` | Browser/crawler config schemas |
| `hooks` | `GET /hooks/info` | Declarative hook catalog |
| `mcp_schema` | `GET /mcp/schema` | Published MCP tool/resource schema |
| `validate_config` | `POST /config/dump` | Server-side untrusted config validation |
| `health` | `GET /health` | Version/health check |

Crawl4AI v0.9 intentionally rejects several request-supplied browser powers, including arbitrary JavaScript, proxy configuration, profile paths, and dynamic deep-crawl strategy on hardened deployments. The adapter passes model-supplied config to the server for validation and reports rejection honestly; it does not pretend a denied server capability is available.

## Crawl4AI Cloud operations

| Tool operation | Cloud route | Support |
|---|---|---|
| `scrape` | `POST /scrape` | Markdown/HTML/both, proxy, country, parsed links/media/metadata/tables |
| `structured_extract` | `POST /extract` | URL or inline content + instruction and/or JSON Schema |
| `search` | `GET /search` | Ranked results and optional rich block |
| `answer` | `GET /answer` | Experimental grounded direct answer |
| `batch` | `POST /scrape/batch` | Up to 50 streamed URLs |
| `scrape_job` | `POST /scrape/jobs` | Up to 10,000 background URLs |
| `scrape_job_status` | `GET /scrape/jobs/{id}` | Job counts/status |
| `scrape_job_results` | `GET /scrape/jobs/{id}/results` | Paged NDJSON via `after` cursor |
| `scrape_job_retry` | `POST /scrape/jobs/{id}/retry` | Failed URLs only |
| `recipes` | `GET /recipes` | Recipe/input/output catalog |
| `recipe_run` | `POST /recipes/{name}` | Typed recipe inputs and optional cache bypass |
| `recipe_health` | `GET /recipes/health` | Regional recipe health |
| `prices` | `GET /v1/prices` | Current Cloud credit price table |
| `balance` | `GET /v1/billing/balance` | Read-only balance |
| `estimate` | `POST /v1/estimate` | Pre-call cost estimate for supported scrape/search/answer/extract/batch/job/recipe targets; the target fields are sent with the estimate |

Billing mutations such as top-up, recharge, and spend-cap changes are intentionally not model-callable.

## Current upstream references

- BrowserAct OpenAPI v3: <https://docs.browseract.com/openapi_3.json>
- BrowserAct MCP (separate from the app's direct REST adapter): <https://docs.browseract.com/integrations/mcp.md>
- Crawl4AI repository and Docker server: <https://github.com/unclecode/crawl4ai>
- Crawl4AI Docker MCP bridge: <https://github.com/unclecode/crawl4ai/blob/main/deploy/docker/mcp_bridge.py>
- Crawl4AI Cloud API: <https://crawl4ai.com/llms.txt>
