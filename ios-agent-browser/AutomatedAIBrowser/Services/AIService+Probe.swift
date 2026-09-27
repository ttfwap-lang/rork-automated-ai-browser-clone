import Foundation

/// Finds out, with real calls, what the AI gateway passes through to Claude.
///
/// The app speaks an OpenAI-style request to the Rork proxy, which forwards it
/// to a gateway, which forwards it to the provider. Whether a thinking-effort
/// field or a prompt-cache marker survives that trip cannot be read from here,
/// so it is measured once and saved as a `GatewayProfile`. Each check is one
/// small call; the cache check sends the same long prompt twice.
extension AIService {

    nonisolated struct ProbeReport: Sendable {
        var profile: GatewayProfile
        var lines: [String]
    }

    /// Runs every check against the precise model and returns what was found.
    /// Nothing is saved here; the caller decides.
    func probeGateway() async -> ProbeReport {
        let model = ModelChoice.precise.modelID
        var profile = GatewayProfile()
        var lines: [String] = []

        guard Self.endpoint() != nil else {
            return ProbeReport(profile: profile, lines: ["AI isn't configured for this build, so nothing could be tested."])
        }

        // 1. Baseline: exactly what the app sends today.
        let baseline = await probeCall(model: model, extra: [:])
        guard baseline.ok else {
            lines.append("Baseline call failed (\(baseline.detail)). Nothing else was tested; optional fields stay off.")
            return ProbeReport(profile: profile, lines: lines)
        }
        lines.append("Baseline: ok in \(Self.seconds(baseline.seconds)) · \(baseline.usageLine)")

        // 2. Temperature. Claude Sonnet 5 rejects it; the app never sends it to
        //    Claude either way. Recorded so the report can say what happens.
        let withTemperature = await probeCall(model: model, extra: ["temperature": 0.2])
        profile.claudeAcceptsTemperature = withTemperature.ok
        lines.append(withTemperature.ok
            ? "Temperature 0.2: accepted (the gateway probably strips it — Claude ignores it). Still never sent."
            : "Temperature 0.2: rejected (\(withTemperature.detail)). Never sent to Claude.")

        // 3. Thinking effort, in the two shapes OpenAI-style gateways use.
        let objectStyle = await probeCall(model: model, extra: ["reasoning": ["effort": "low"]])
        if objectStyle.ok {
            profile.effortStyle = .reasoningObject
            lines.append("Thinking effort as \"reasoning\": {\"effort\"}: accepted · \(objectStyle.usageLine)")
        } else {
            lines.append("Thinking effort as \"reasoning\": {\"effort\"}: rejected (\(objectStyle.detail))")
            let flatStyle = await probeCall(model: model, extra: ["reasoning_effort": "low"])
            if flatStyle.ok {
                profile.effortStyle = .reasoningEffort
                lines.append("Thinking effort as \"reasoning_effort\": accepted · \(flatStyle.usageLine)")
            } else {
                lines.append("Thinking effort as \"reasoning_effort\": rejected (\(flatStyle.detail)). Effort stays off.")
            }
        }
        if profile.effortStyle != .none {
            lines.append("Note: accepted means not refused. Compare the thinking tokens above with the baseline to see whether it took effect.")
        }

        // 4. Prompt caching: the real system prompt (well over Claude's
        //    1,024-token minimum) marked cacheable, sent twice.
        let cached: [String: Any] = ["type": "text", "text": Self.systemPrompt, "cache_control": ["type": "ephemeral"]]
        let first = await probeCall(model: model, extra: [:], systemContent: [cached])
        if first.ok {
            let second = await probeCall(model: model, extra: [:], systemContent: [cached])
            if second.ok, second.cachedTokens > 0 {
                profile.cacheStyle = .contentPart
                lines.append("Prompt caching: works — the repeat call read \(second.cachedTokens) tokens from cache and took \(Self.seconds(second.seconds)) (first \(Self.seconds(first.seconds))).")
            } else if second.ok {
                lines.append("Prompt caching: marker accepted but the repeat call reported no cached tokens. Left off.")
            } else {
                lines.append("Prompt caching: repeat call failed (\(second.detail)). Left off.")
            }
        } else {
            lines.append("Prompt caching: marker rejected (\(first.detail)). Left off.")
        }

        profile.probedAt = Date()
        return ProbeReport(profile: profile, lines: lines)
    }

    // MARK: - One probe call

    private nonisolated struct ProbeResult {
        var ok: Bool
        var detail: String
        var seconds: TimeInterval
        var cachedTokens: Int = 0
        var usageLine: String = ""
    }

    /// One small forced tool call, with `extra` merged into the body. Raw JSON so
    /// any field can be tried without touching the app's own request type.
    private func probeCall(
        model: String,
        extra: [String: Any],
        systemContent: Any = "You are testing a connection. Call the reply tool."
    ) async -> ProbeResult {
        guard let endpoint = Self.endpoint() else {
            return ProbeResult(ok: false, detail: "not configured", seconds: 0)
        }
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemContent],
            ["role": "user", "content": "Call the reply tool with the word ready."],
        ]
        let parameters: [String: Any] = [
            "type": "object",
            "properties": ["word": ["type": "string"]],
            "required": ["word"],
        ]
        let function: [String: Any] = [
            "name": "reply",
            "description": "Reply with one word.",
            "parameters": parameters,
        ]
        let tools: [[String: Any]] = [["type": "function", "function": function]]
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1_024,
            "tool_choice": "required",
            "messages": messages,
            "tools": tools,
        ]
        for (field, value) in extra { body[field] = value }

        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(endpoint.key)", forHTTPHeaderField: "Authorization")
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return ProbeResult(ok: false, detail: "could not build the request", seconds: 0)
        }
        request.httpBody = data

        let start = Date()
        do {
            let (reply, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(start)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let snippet = String(decoding: reply.prefix(160), as: UTF8.self)
                    .replacingOccurrences(of: "\n", with: " ")
                return ProbeResult(ok: false, detail: "HTTP \(status): \(snippet)", seconds: elapsed)
            }
            guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: reply) else {
                return ProbeResult(ok: false, detail: "reply could not be read", seconds: elapsed)
            }
            let record = decoded.record(model: model, seconds: elapsed)
            return ProbeResult(
                ok: true,
                detail: "ok",
                seconds: elapsed,
                cachedTokens: record.cachedTokens,
                usageLine: CallTotals([record]).line
            )
        } catch {
            return ProbeResult(ok: false, detail: error.localizedDescription, seconds: Date().timeIntervalSince(start))
        }
    }

    private nonisolated static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1fs", value)
    }
}
