//
//  SpeedAndStepsTests.swift
//  AutomatedAIBrowserTests
//
//  Measuring AI calls, requests that can be cached, thinking effort and
//  temperature per model, whole-page element lists, and benchmark defaults.
//

import Testing
import Foundation
@testable import AutomatedAIBrowser

struct SpeedAndStepsTests {

    // MARK: - Measuring every call

    @Test func usageAndFinishReasonAreRead() throws {
        let json = #"""
        {"choices":[{"message":{"content":"hi"},"finish_reason":"length"}],
         "usage":{"prompt_tokens":14200,"completion_tokens":310,
                  "prompt_tokens_details":{"cached_tokens":8000},
                  "completion_tokens_details":{"reasoning_tokens":120}}}
        """#
        let response = try JSONDecoder().decode(AIService.ChatResponse.self, from: Data(json.utf8))
        let record = response.record(model: "anthropic/claude-sonnet-5", seconds: 2)
        #expect(record.promptTokens == 14200)
        #expect(record.cachedTokens == 8000)
        #expect(record.reasoningTokens == 120)
        #expect(record.completionTokens == 310)
        #expect(record.wasTruncated)
    }

    @Test func aReplyWithoutUsageStillDecodes() throws {
        let json = #"{"choices":[{"message":{"content":"hi"}}]}"#
        let response = try JSONDecoder().decode(AIService.ChatResponse.self, from: Data(json.utf8))
        let record = response.record(model: "m", seconds: 1)
        #expect(record.promptTokens == 0)
        #expect(!record.wasTruncated)
    }

    @Test func callTotalsReadAsOneLine() {
        let records = [
            CallRecord(model: "a", promptTokens: 10_000, completionTokens: 200, reasoningTokens: 120, cachedTokens: 8_000, finishReason: "stop", seconds: 3),
            CallRecord(model: "a", promptTokens: 4_200, completionTokens: 110, reasoningTokens: 0, cachedTokens: 0, finishReason: "length", seconds: 2),
        ]
        #expect(CallTotals(records).line == "2 calls · 14.2k in (8.0k cached) · 310 out (120 thinking) · 1 cut off")
        #expect(CallTotals([]).line == "no AI calls")
    }

    @Test func theMeterReturnsOnlyWhatCameAfterTheMark() {
        let meter = CallMeter()
        meter.record(CallRecord(model: "a", promptTokens: 1, completionTokens: 1, reasoningTokens: 0, cachedTokens: 0, finishReason: nil, seconds: 0))
        let mark = meter.mark()
        meter.record(CallRecord(model: "b", promptTokens: 2, completionTokens: 1, reasoningTokens: 0, cachedTokens: 0, finishReason: nil, seconds: 0))
        #expect(meter.records(since: mark).map(\.model) == ["b"])
    }

    @Test func aStepSaysWhereItsTimeWent() {
        let start = Date(timeIntervalSince1970: 0)
        var timing = StepTiming(start: start)
        timing.lap("settle", now: start.addingTimeInterval(0.4))
        timing.lap("decide", now: start.addingTimeInterval(6.5))
        timing.lap("act", now: start.addingTimeInterval(7.7))
        let line = timing.line(calls: CallTotals([]))
        #expect(line == "settle 0.4s · decide 6.1s · act 1.2s")
    }

    // MARK: - Requests that can be cached

    @Test func theToolListIsTheSameEveryTurn() {
        let first = AIService.tools().map(\.function.name)
        let second = AIService.tools().map(\.function.name)
        #expect(first == second)
        #expect(Set(first).isSuperset(of: ["fill_from_dossier", "ask_user", "hand_over", "revise_plan", "rewind", "weigh_options"]))
        #expect(Set(first).count == first.count, "no tool is listed twice")
    }

    @Test func sharedFieldsAreExplainedOnceNotOnEveryTool() throws {
        let tool = try #require(AIService.tools().first)
        let data = try JSONEncoder().encode(tool)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Page readings are forgotten next turn"))
        #expect(AIService.systemPrompt.contains("SHARED FIELDS"))
    }

    private func body(model: String, effort: String?, profile: GatewayProfile) throws -> [String: Any] {
        let body = AIService.makeBody(
            model: model,
            system: "system",
            history: [],
            parts: [.text("page")],
            tools: [],
            maxTokens: AIService.decisionMaxTokens,
            temperature: 0.1,
            effort: effort,
            profile: profile
        )
        let data = try JSONEncoder().encode(body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func claudeIsNeverSentATemperature() throws {
        let claude = try body(model: "anthropic/claude-sonnet-5", effort: nil, profile: GatewayProfile())
        #expect(claude["temperature"] == nil)
        #expect(claude["max_tokens"] as? Int == 4_096)
        let gemini = try body(model: "google/gemini-3.5-flash", effort: nil, profile: GatewayProfile())
        #expect(gemini["temperature"] as? Double == 0.1)
    }

    @Test func effortIsSentOnlyInTheShapeTheGatewayAccepted() throws {
        var profile = GatewayProfile()
        let untested = try body(model: "anthropic/claude-sonnet-5", effort: "low", profile: profile)
        #expect(untested["reasoning"] == nil && untested["reasoning_effort"] == nil)

        profile.effortStyle = .reasoningObject
        let object = try body(model: "anthropic/claude-sonnet-5", effort: "low", profile: profile)
        #expect((object["reasoning"] as? [String: Any])?["effort"] as? String == "low")

        profile.effortStyle = .reasoningEffort
        let flat = try body(model: "anthropic/claude-sonnet-5", effort: "high", profile: profile)
        #expect(flat["reasoning_effort"] as? String == "high")

        let gemini = try body(model: "google/gemini-3.5-flash", effort: "high", profile: profile)
        #expect(gemini["reasoning_effort"] == nil)
    }

    @Test func theSystemPromptCarriesACacheMarkWhenTheGatewayHonoursIt() throws {
        var profile = GatewayProfile()
        let plain = try body(model: "anthropic/claude-sonnet-5", effort: nil, profile: profile)
        let plainSystem = try #require((plain["messages"] as? [[String: Any]])?.first)
        #expect(plainSystem["content"] as? String == "system")

        profile.cacheStyle = .contentPart
        let cached = try body(model: "anthropic/claude-sonnet-5", effort: nil, profile: profile)
        let system = try #require((cached["messages"] as? [[String: Any]])?.first)
        let part = try #require((system["content"] as? [[String: Any]])?.first)
        #expect((part["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
    }

    @Test func anUntestedGatewayGetsNoOptionalFields() {
        let profile = GatewayProfile()
        #expect(profile.effortStyle == .none)
        #expect(profile.cacheStyle == .none)
        #expect(profile.summary.hasPrefix("Not tested yet"))
    }

    // MARK: - Effort and temperature per step

    @Test func thinkingEffortFollowsTheStep() {
        #expect(AgentViewModel.effort(for: .routine, benchmark: false) == "low")
        #expect(AgentViewModel.effort(for: .routine, benchmark: true) == "medium")
        #expect(AgentViewModel.effort(for: .normal, benchmark: false) == "medium")
        #expect(AgentViewModel.effort(for: .hard, benchmark: false) == "high")
    }

    @Test func temperatureLoosensOnlyWhenStuck() {
        #expect(AgentViewModel.decisionTemperature(stagnantSteps: 0, isRepeating: false) == 0.1)
        #expect(AgentViewModel.decisionTemperature(stagnantSteps: 2, isRepeating: false) == 0.5)
        #expect(AgentViewModel.decisionTemperature(stagnantSteps: 0, isRepeating: true) == 0.5)
    }

    // MARK: - Fewer steps

    @Test func offScreenControlsAreListedAndSayTheyScrollThemselves() throws {
        let json = #"{"ok":true,"vw":390,"vh":760,"ab":3,"be":10,"els":[{"i":1,"k":"button","n":"Search","r":[10,40,80,30]},{"i":2,"k":"button","n":"Next page","r":[10,1400,80,30],"o":"b"}]}"#
        let observation = try #require(PageScanner.parse(json))
        let next = try #require(observation.element(withID: 2))
        #expect(next.offscreen == "below")
        #expect(next.mapLine == #"[2] button "Next page" (below — scrolls itself)"#)
        #expect(observation.visibleElements.map(\.id) == [1])
        #expect(observation.mapText.contains("never scroll just to reach one"))
    }

    @Test func aLongListOfOffScreenControlsDoesNotMakeThePageBusy() {
        var elements: [ScannedElement] = (1...5).map {
            ScannedElement(id: $0, kind: .link, name: "Link \($0)", states: [], valuePreview: nil, isEditable: false, x: 0, y: Double($0) * 40, width: 80, height: 30)
        }
        for id in 6...120 {
            var element = ScannedElement(id: id, kind: .link, name: "Story \(id)", states: [], valuePreview: nil, isEditable: false, x: 0, y: 2_000, width: 80, height: 30)
            element.offscreen = "below"
            elements.append(element)
        }
        let observation = PageObservation(
            elements: elements, viewportWidth: 390, viewportHeight: 760, scrollFraction: 0,
            documentHeightRatio: 8, elementsAbove: 0, elementsBelow: 0, unlistedVisibleCount: 0,
            overlayLikely: false, isPartial: false
        )
        let read = DifficultyScout.read(.init(isFirstStep: false, observation: observation))
        #expect(!read.reasons.contains { $0.contains("busy page") })
    }

    @Test func directAddressesAreAllowedAndVisibleAnswersFinish() {
        let prompt = AIService.systemPrompt
        #expect(prompt.contains("GETTING THERE FAST"))
        #expect(!prompt.contains("Do not compose deep URLs"))
        #expect(prompt.contains("call \"done\" with it now"))
    }

    @Test func movesThatLeaveThePageAreWaitedOnAfresh() {
        #expect(AgentViewModel.leavesThePage(AgentAction(type: "navigate")))
        #expect(AgentViewModel.leavesThePage(AgentAction(type: "back")))
        #expect(!AgentViewModel.leavesThePage(AgentAction(type: "tap_element")))
    }

    @Test func theStepBudgetIsWiderByDefault() {
        #expect(AppSettings.defaultMaxSteps == 25)
        #expect(AppSettings.stepRange == 5...50)
        #expect(AppSettings.benchmarkMinSteps >= 40)
    }
}
