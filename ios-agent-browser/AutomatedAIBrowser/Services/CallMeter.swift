import Foundation

/// One AI call as the gateway reported it.
nonisolated struct CallRecord: Equatable, Sendable {
    let model: String
    let promptTokens: Int
    let completionTokens: Int
    /// Hidden thinking the model spent before answering.
    let reasoningTokens: Int
    /// Prompt tokens served from the provider's cache.
    let cachedTokens: Int
    let finishReason: String?
    let seconds: TimeInterval

    /// True when the reply was cut off by the output cap.
    var wasTruncated: Bool {
        finishReason == "length" || finishReason == "max_tokens"
    }
}

/// Totals over a set of calls — one step, or a whole run.
nonisolated struct CallTotals: Equatable, Sendable {
    let calls: Int
    let promptTokens: Int
    let completionTokens: Int
    let reasoningTokens: Int
    let cachedTokens: Int
    let truncated: Int
    let seconds: TimeInterval

    init(_ records: [CallRecord]) {
        calls = records.count
        promptTokens = records.map(\.promptTokens).reduce(0, +)
        completionTokens = records.map(\.completionTokens).reduce(0, +)
        reasoningTokens = records.map(\.reasoningTokens).reduce(0, +)
        cachedTokens = records.map(\.cachedTokens).reduce(0, +)
        truncated = records.filter(\.wasTruncated).count
        seconds = records.map(\.seconds).reduce(0, +)
    }

    /// `2 calls · 14.2k in (8.0k cached) · 310 out (120 thinking) · 1 cut off`
    var line: String {
        guard calls > 0 else { return "no AI calls" }
        var parts = ["\(calls) call\(calls == 1 ? "" : "s")"]
        var input = "\(Self.compact(promptTokens)) in"
        if cachedTokens > 0 { input += " (\(Self.compact(cachedTokens)) cached)" }
        parts.append(input)
        var output = "\(Self.compact(completionTokens)) out"
        if reasoningTokens > 0 { output += " (\(Self.compact(reasoningTokens)) thinking)" }
        parts.append(output)
        if truncated > 0 { parts.append("\(truncated) cut off") }
        return parts.joined(separator: " · ")
    }

    static func compact(_ tokens: Int) -> String {
        tokens >= 1_000 ? String(format: "%.1fk", Double(tokens) / 1_000) : "\(tokens)"
    }
}

/// Every AI call the app makes, recorded where it is sent, so a step or a run
/// can say exactly what it cost and where the time went. Without this, hidden
/// thinking, cache misses and cut-off replies are invisible.
nonisolated final class CallMeter: @unchecked Sendable {
    static let shared = CallMeter()

    private let lock = NSLock()
    private var records: [CallRecord] = []
    /// Only the recent past is ever read; older records are dropped.
    private static let capacity = 2_000
    private var dropped = 0

    func record(_ record: CallRecord) {
        lock.lock()
        defer { lock.unlock() }
        records.append(record)
        if records.count > Self.capacity {
            let excess = records.count - Self.capacity
            records.removeFirst(excess)
            dropped += excess
        }
    }

    /// A position to measure from.
    func mark() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return dropped + records.count
    }

    /// Everything recorded since `mark`.
    func records(since mark: Int) -> [CallRecord] {
        lock.lock()
        defer { lock.unlock() }
        let start = max(0, mark - dropped)
        guard start < records.count else { return [] }
        return Array(records[start...])
    }
}
