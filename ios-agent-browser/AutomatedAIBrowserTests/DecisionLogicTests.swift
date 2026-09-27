//
//  DecisionLogicTests.swift
//  AutomatedAIBrowserTests
//
//  How the agent reads pages, remembers moves, understands the goal, and
//  decides when to spend on the frontier model.
//

import Testing
import UIKit
@testable import AutomatedAIBrowser

struct DecisionLogicTests {

    private func page(_ elements: [ScannedElement]) -> PageObservation {
        PageObservation(
            elements: elements,
            viewportWidth: 390,
            viewportHeight: 760,
            scrollFraction: 0,
            documentHeightRatio: 1,
            elementsAbove: 0,
            elementsBelow: 0,
            unlistedVisibleCount: 0,
            overlayLikely: false,
            isPartial: false
        )
    }

    private func target(_ id: Int, _ kind: ScannedElement.Kind = .button, _ name: String = "Go") -> ScannedElement {
        ScannedElement(
            id: id, kind: kind, name: name, states: [], valuePreview: nil,
            isEditable: kind == .field, x: 0, y: Double(id) * 40, width: 80, height: 30
        )
    }

    // MARK: - Reading words, not substrings

    @Test func wordingMatchesWholeWordsOnly() {
        #expect(Wording.containsPhrase("Book now", "ok") == false)
        #expect(Wording.containsPhrase("OK, got it", "ok"))
        #expect(Wording.containsPhrase("Continue to payment", "pay", allowInflection: true))
        #expect(Wording.containsPhrase("PayPal", "pay", allowInflection: true) == false)
        #expect(Wording.containsPhrase("Sender address", "send", allowInflection: true) == false)
        #expect(Wording.containsPhrase("Place your order", "place order") == false)
        #expect(Wording.containsPhrase("Place orders", "place order", allowInflection: true))
    }

    @Test func dismissalsAreRecognisedWithoutSwallowingOtherButtons() {
        #expect(OnDeviceGate.isDismissal("OK"))
        #expect(OnDeviceGate.isDismissal("Got it!"))
        #expect(OnDeviceGate.isDismissal("Reject all"))
        #expect(OnDeviceGate.isDismissal("Book now") == false)
        #expect(OnDeviceGate.isDismissal("Log in with Facebook") == false)
        #expect(OnDeviceGate.isDismissal("Continue to payment") == false)
        #expect(OnDeviceGate.isDismissal("Disclosure") == false)
    }

    @Test func irreversibleNamesAreReadOnWholeWords() {
        #expect(OnDeviceGate.isIrreversible("Place order"))
        #expect(OnDeviceGate.isIrreversible("Proceed to payment"))
        #expect(OnDeviceGate.isIrreversible("Delete account"))
        #expect(OnDeviceGate.isIrreversible("PayPal") == false)
        #expect(OnDeviceGate.isIrreversible("Sender details") == false)
        #expect(OnDeviceGate.isIrreversible("Display options") == false)
    }

    @Test func pageTextInAResultCannotMakeAMoveLookFailed() {
        #expect(!ReactionWatch.readsAsFailure(#"tapped [3] button "Report an error" · page reacted (4 changes)"#))
        #expect(!ReactionWatch.readsAsFailure(#"typed "missing dog" into [2] field "Search" · the field now holds "missing dog""#))
        #expect(!ReactionWatch.readsAsFailure("asked for https://shop.test/error-pages · landed on shop.test/error-pages"))
        #expect(ReactionWatch.readsAsFailure(#"tapped [3] button "Great" · no visible reaction — this site may need real finger input"#))
        #expect(ReactionWatch.shouldAttachVerdict(to: #"tapped [3] button "Missing items""#))
        #expect(!ReactionWatch.readsAsNoReaction(#"tapped [3] button "no visible reaction""#))
    }

    // MARK: - Remembering the control, not its badge

    @Test func aBarredMoveFollowsTheControlNotItsBadgeNumber() {
        let url = "https://shop.test/cart"
        let before = page([target(1, .button, "Next"), target(2, .button, "Delete")])
        // After a scroll the same Delete button wears a different number, and
        // number 2 now belongs to something else entirely.
        let after = page([target(1, .button, "Delete"), target(2, .button, "Help")])

        var flagged = AgentAction(type: "tap_element")
        flagged.element = 2
        flagged.targetKey = before.elements[1].targetKey(in: before, urlString: url)
        var sameControl = AgentAction(type: "tap_element")
        sameControl.element = 1
        sameControl.targetKey = after.elements[0].targetKey(in: after, urlString: url)
        var sameNumber = AgentAction(type: "tap_element")
        sameNumber.element = 2
        sameNumber.targetKey = after.elements[1].targetKey(in: after, urlString: url)

        let barred: Set<String> = [flagged.repetitionSignature]
        #expect(barred.contains(sameControl.repetitionSignature))
        #expect(!barred.contains(sameNumber.repetitionSignature))
    }

    @Test func theSameControlOnAnotherPageIsNotTheSameMove() {
        let observation = page([target(1, .button, "Apply")])
        let here = observation.elements[0].targetKey(in: observation, urlString: "https://a.test/filters")
        let there = observation.elements[0].targetKey(in: observation, urlString: "https://a.test/checkout")
        let nextPage = observation.elements[0].targetKey(in: observation, urlString: "https://a.test/filters?page=2")
        #expect(here != there)
        #expect(here == nextPage)
    }

    @Test func lookAlikesAreToldApartByTheirContainer() {
        var sony = target(1, .button, "Add to cart")
        sony.context = "Sony WH-1000XM5"
        var bose = target(2, .button, "Add to cart")
        bose.context = "Bose QC Ultra"
        let observation = page([sony, bose])
        #expect(sony.targetKey(in: observation, urlString: "") != bose.targetKey(in: observation, urlString: ""))
        #expect(sony.mapLine.contains(#"(in: "Sony WH-1000XM5")"#))

        let bare = page([target(1, .button, "Add to cart"), target(2, .button, "Add to cart")])
        #expect(bare.elements[0].targetKey(in: bare, urlString: "") != bare.elements[1].targetKey(in: bare, urlString: ""))
    }

    @Test func theMapNamesFieldTypesAndLinkDestinations() {
        var email = target(7, .field, "Email")
        email.inputType = "email"
        var more = target(8, .link, "Read more")
        more.linkHint = "/news/42"
        #expect(email.mapLine.contains("type: email"))
        #expect(more.mapLine.hasSuffix("\u{2192} /news/42"))
        #expect(target(9).mapLine == #"[9] button "Go""#)
    }

    // MARK: - Scoring and escalation

    @Test func scoringSeesTheRealNameOfTheTargetItIsJudging() {
        var draft = AgentAction(type: "tap_element")
        draft.element = 1 // no name: exactly how a weigh_options draft arrives
        let task = MissionTask(number: 1, title: "Read the cheapest fare", doneWhen: "a price is visible", state: .current)
        let scored = CandidateScorer.score(
            [MoveCandidate(action: draft, rationale: "go ahead", confidence: 0.8)],
            in: CandidateScorer.Context(observation: page([target(1, .button, "Place order")]), currentTask: task)
        )
        #expect(scored[0].note.contains("irreversible"))
        #expect(scored[0].score < 0.8)
        #expect(scored[0].action.elementName == #"button "Place order""#)
        #expect(scored[0].action.targetKey != nil)
    }

    @Test func scoringFavoursCandidatesThatUseTheGoalsSpecifics() {
        var fourGuests = AgentAction(type: "select_option")
        fourGuests.element = 1
        fourGuests.option = "4 guests"
        var twoGuests = AgentAction(type: "select_option")
        twoGuests.element = 1
        twoGuests.option = "2 guests"
        let scored = CandidateScorer.score(
            [
                MoveCandidate(action: twoGuests, rationale: "a default", confidence: 0.5),
                MoveCandidate(action: fourGuests, rationale: "party size", confidence: 0.5),
            ],
            in: CandidateScorer.Context(observation: page([target(1, .dropdown, "Party size")]), goalDetails: ["4"])
        )
        #expect(scored[0].action.option == "4 guests")
    }

    @Test func aCommittingMoveFromACheaperModelIsEscalated() {
        let observation = page([target(1, .button, "Place order"), target(2, .field, "Search"), target(3, .field, "Message")])
        var order = AgentAction(type: "tap_element")
        order.element = 1
        var search = AgentAction(type: "type_into")
        search.element = 2
        search.text = "shoes"
        search.submit = true
        var message = AgentAction(type: "type_into")
        message.element = 3
        message.text = "hello"
        message.submit = true

        #expect(ModelRouter.escalationForCommittingMove(order, decidedOn: .fast, strategy: .auto, in: observation)?.choice == .precise)
        #expect(ModelRouter.escalationForCommittingMove(order, decidedOn: .onDevice, strategy: .auto, in: observation)?.choice == .precise)
        #expect(ModelRouter.escalationForCommittingMove(order, decidedOn: .precise, strategy: .auto, in: observation) == nil)
        #expect(ModelRouter.escalationForCommittingMove(order, decidedOn: .fast, strategy: .alwaysFast, in: observation) == nil)
        // Enter in a search box is how search works, not a commitment.
        #expect(ModelRouter.escalationForCommittingMove(search, decidedOn: .fast, strategy: .auto, in: observation) == nil)
        #expect(ModelRouter.escalationForCommittingMove(message, decidedOn: .fast, strategy: .auto, in: observation) != nil)
    }

    @Test func anOrdinaryPageIsNotBusyAndARiskyButtonDoesNotMakeItHard() {
        let items = (1...20).map { target($0, .link, "Item \($0)") }
        let read = DifficultyScout.read(.init(
            isFirstStep: false,
            observation: page(items + [target(21, .button, "Buy now")])
        ))
        #expect(read.difficulty == .routine)
        #expect(read.isIrreversible)
    }

    @Test func aResultEchoingAnErrorLabelDoesNotRaiseDifficulty() {
        let read = DifficultyScout.read(.init(
            isFirstStep: false,
            observation: page([target(1)]),
            lastResult: #"tapped [4] button "Couldn't find it? Report an error" · page reacted (3 changes)"#
        ))
        #expect(read.difficulty == .routine)
    }

    // MARK: - Understanding the goal

    @Test func theGoalsSpecificsAreExtracted() {
        let details = GoalDetails.extract("Book a table for 4 at Nopa on Friday under $120 via opentable.com")
        #expect(details.contains("4"))
        #expect(details.contains("Nopa"))
        #expect(details.contains("Friday"))
        #expect(details.contains("$120"))
        #expect(details.contains("opentable.com"))
        #expect(!details.contains("120"), "the more specific form wins")
        #expect(!details.contains("Book"), "a sentence's first word is not a name")
    }

    @Test func multiWordNamesStayTogether() {
        let details = GoalDetails.extract("find hotels near Golden Gate Park, San Francisco")
        #expect(details.contains("Golden Gate Park"))
        #expect(details.contains("San Francisco"))
    }

    @Test func aRefinementThatDropsASpecificIsRefused() {
        let original = "Book a table for 4 at Nopa on Friday"
        #expect(GoalRefiner.parse("MISSION: Book a table at Nopa on Friday\nWANTS: action", original: original) == nil)
        #expect(GoalRefiner.parse("MISSION: Book a table for 4 at Nopa this Friday\nWANTS: action", original: original) != nil)
        #expect(GoalDetails.briefingLine([]) == nil)
    }

    @Test func aGoalTypedInCapitalsIsNotReadAsOneLongName() {
        #expect(GoalDetails.properNouns(in: "FIND CHEAP FLIGHTS TO PARIS IN MAY").isEmpty)
        #expect(GoalDetails.properNouns(in: "find cheap flights to Paris in May") == ["Paris", "May"])
    }

    // MARK: - What a run teaches

    @Test func wallsAreReadOnWholeWords() {
        #expect(LessonDistiller.readsAsWall("403 Forbidden"))
        #expect(LessonDistiller.readsAsWall("the site runs bot detection"))
        #expect(LessonDistiller.readsAsWall("the price is $1403") == false)
        #expect(LessonDistiller.readsAsWall("the Humane Society page has no listings") == false)
    }

    @Test func onlyAControlThatIgnoredThePressIsRecordedAsDead() {
        let ignored = RecipeDistiller.Move(kind: .tapElement, result: "tapped [3] · \(ReactionWatch.noReactionPhrase)")
        let missed = RecipeDistiller.Move(kind: .tapElement, result: "element 3 is no longer on the page — the page changed; look again before acting")
        let dropped = RecipeDistiller.Move(kind: .typeInto, result: #"typed "x" into [2] · the field did not take the text — it is still empty"#)
        #expect(LessonDistiller.controlIgnored(ignored))
        #expect(!LessonDistiller.controlIgnored(missed), "a re-drawn page says nothing about the control")
        #expect(LessonDistiller.controlIgnored(dropped))
    }

    // MARK: - Tools: notes and questions

    @Test func notedFactsRideAlongWithAnyMove() {
        let decision = AIService.decision(
            fromToolNamed: "navigate",
            argumentsJSON: #"{"reasoning":"next store","url":"https://b.test","note_facts":[{"fact":"Store A sells it for $348","quote":"$348.00"},{"fact":"","quote":"x"}]}"#
        )
        #expect(decision?.action.notedFacts?.count == 1)
        #expect(decision?.action.notedFacts?.first?.quote == "$348.00")
        #expect(decision?.action.notedFacts?.first?.urlString == nil, "provenance is the app's to set")
        #expect(AIService.tools(hasPlan: false).allSatisfy { $0.function.parameters.properties["note_facts"] != nil })
    }

    @Test func aNoteNeedsBothAFactAndAQuote() throws {
        #expect(NotedFact.make(fact: "  ", quote: "x") == nil)
        #expect(NotedFact.make(fact: "Price", quote: nil) == nil)
        var fact = try #require(NotedFact.make(fact: "Store A: $348", quote: "$348.00"))
        fact.urlString = "https://a.test/item/9"
        #expect(fact.ledgerLine.contains("a.test/item/9"))
        #expect(fact.ledgerLine.contains("$348.00"))
    }

    @Test func askUserIsOfferedOnlyWhileQuestionsRemain() {
        #expect(AIService.tools(hasPlan: false, canAskUser: true).contains { $0.function.name == "ask_user" })
        #expect(!AIService.tools(hasPlan: false).contains { $0.function.name == "ask_user" })
        let decision = AIService.decision(
            fromToolNamed: "ask_user",
            argumentsJSON: #"{"reasoning":"two sizes","question":"Which size?","choices":["M","L",""]}"#
        )
        #expect(decision?.action.kind == .askUser)
        #expect(decision?.action.question == "Which size?")
        #expect(decision?.action.choices == ["M", "L"])
        #expect(AgentActionKind.askUser.isPageAction == false)
        #expect(AgentActionKind.askUser.isModelCallable)
    }

    @Test func legacyJSONCannotSupplyAppResolvedFields() {
        let decision = AIService.parseDecision(
            from: #"{"reasoning":"x","action":{"type":"tap_element","element":3,"elementName":"button \"Safe\"","targetKey":"forged"}}"#
        )
        #expect(decision?.action.element == 3)
        #expect(decision?.action.elementName == nil)
        #expect(decision?.action.targetKey == nil)
    }

    // MARK: - Conversation history

    @Test func earlierMovesReplayAsRealToolCalls() throws {
        var action = AgentAction(type: "type_into")
        action.element = 4
        action.text = "lisbon"
        action.submit = true
        let json = try #require(AIService.transcriptArguments(for: action, reasoning: "search for it"))
        #expect(json.contains(#""element":4"#))
        #expect(json.contains(#""reasoning":"search for it""#))
        #expect(json.contains(#""submit":true"#))
        // Only tools that are on offer every turn are replayed.
        #expect(AIService.transcriptArguments(for: AgentAction(type: "run_plugin"), reasoning: "") == nil)
        #expect(AIService.transcriptArguments(for: AgentAction(type: "rewind"), reasoning: "") == nil)
        #expect(AIService.transcriptArguments(for: AgentAction(type: "ask_user"), reasoning: "") == nil)
    }

    @Test func aReplayedToolCallEncodesAsAnAssistantTurn() throws {
        let message = AIService.ChatMessage(
            role: "assistant",
            content: nil,
            toolCalls: [AIService.OutgoingToolCall(id: "call_1", type: "function", function: .init(name: "back", arguments: "{}"))]
        )
        let data = try JSONEncoder().encode(message)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["content"] == nil, "no content key rather than an empty one")
        #expect((object["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == "call_1")

        let result = AIService.ChatMessage(role: "tool", content: .string("went back"), toolCallID: "call_1")
        let resultObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        #expect(resultObject["tool_call_id"] as? String == "call_1")
    }

    // MARK: - Settling and sight

    @Test func aPageIsSettledOnlyWhenQuietWithNothingPending() {
        #expect(ReactionWatch.isSettled(ReactionWatch.parseQuiet(#"{"ok":true,"since":600,"inflight":0}"#)))
        #expect(!ReactionWatch.isSettled(ReactionWatch.parseQuiet(#"{"ok":true,"since":600,"inflight":2}"#)))
        #expect(!ReactionWatch.isSettled(ReactionWatch.parseQuiet(#"{"ok":true,"since":100,"inflight":0}"#)))
        #expect(!ReactionWatch.parseQuiet("js error: timed out").ok)
    }

    @Test func aTickingPageSettlesButARenderingOneDoesNot() {
        // One isolated change a moment ago: a clock or ticker, not a render.
        #expect(ReactionWatch.isSettled(ReactionWatch.parseQuiet(#"{"ok":true,"since":200,"inflight":0,"bursts":1}"#)))
        #expect(!ReactionWatch.isSettled(ReactionWatch.parseQuiet(#"{"ok":true,"since":200,"inflight":0,"bursts":3}"#)))
        #expect(!ReactionWatch.isSettled(ReactionWatch.parseQuiet(#"{"ok":true,"since":200,"inflight":1,"bursts":1}"#)))
    }

    @Test func theAgentsOwnBookkeepingIsNotAReaction() {
        // The scanner re-numbers every control with data-rork-agent; counted,
        // that churn inflated the idle baseline and erased real reactions.
        #expect(ReactionWatch.sortFunction.contains("'data-rork-'"))
    }

    @Test func theWatcherKnowsWhichElementWasTargeted() {
        #expect(ReactionWatch.startScript(targetID: 14).contains("var TARGET = 14;"))
        #expect(ReactionWatch.startScript(targetID: nil).contains("var TARGET = null;"))
    }

    @Test @MainActor func uploadsAreSentAtOnePixelPerPoint() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        }
        let scaled = AgentViewModel.atOnePixelPerPoint(image)
        #expect(scaled.scale == 1)
        #expect(scaled.cgImage?.width == 100)
        #expect(scaled.cgImage?.height == 50)
    }
}
