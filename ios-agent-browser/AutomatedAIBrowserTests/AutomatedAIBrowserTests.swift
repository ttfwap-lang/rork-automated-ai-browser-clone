//
//  AutomatedAIBrowserTests.swift
//  AutomatedAIBrowserTests
//
//  Created by Rork on July 7, 2026.
//

import Testing
import UIKit
@testable import AutomatedAIBrowser

struct AutomatedAIBrowserTests {

    // MARK: - Tool-call decision parsing

    @Test func tapElementToolCallParses() {
        let decision = AIService.decision(
            fromToolNamed: "tap_element",
            argumentsJSON: #"{"reasoning":"Press the cart button.","element":14}"#
        )
        #expect(decision?.action.kind == .tapElement)
        #expect(decision?.action.element == 14)
        #expect(decision?.reasoning == "Press the cart button.")
    }

    @Test func typeIntoToolCallParses() {
        let decision = AIService.decision(
            fromToolNamed: "type_into",
            argumentsJSON: #"{"reasoning":"Fill the email field.","element":7,"text":"a@b.com","submit":true}"#
        )
        #expect(decision?.action.kind == .typeInto)
        #expect(decision?.action.element == 7)
        #expect(decision?.action.text == "a@b.com")
        #expect(decision?.action.submit == true)
    }

    @Test func coordinateTapStillParsesAsLastResort() {
        let decision = AIService.decision(
            fromToolNamed: "tap",
            argumentsJSON: #"{"reasoning":"No badge on the map canvas.","x":512,"y":300}"#
        )
        #expect(decision?.action.kind == .tap)
        #expect(decision?.action.x == 512)
        #expect(decision?.action.y == 300)
    }

    @Test func unknownToolIsRejected() {
        #expect(AIService.decision(fromToolNamed: "self_destruct", argumentsJSON: "{}") == nil)
    }

    // MARK: - Pair 2 tool-call parsing (pro hands + whole-page sight)

    @Test func selectOptionToolCallParses() {
        let decision = AIService.decision(
            fromToolNamed: "select_option",
            argumentsJSON: #"{"reasoning":"Pick the size.","element":12,"option":"Large"}"#
        )
        #expect(decision?.action.kind == .selectOption)
        #expect(decision?.action.element == 12)
        #expect(decision?.action.option == "Large")
    }

    @Test func setToggleToolCallParses() {
        let decision = AIService.decision(
            fromToolNamed: "set_toggle",
            argumentsJSON: #"{"reasoning":"Enable notifications.","element":22,"on":true}"#
        )
        #expect(decision?.action.kind == .setToggle)
        #expect(decision?.action.element == 22)
        #expect(decision?.action.on == true)
    }

    @Test func setSliderToolCallParses() {
        let decision = AIService.decision(
            fromToolNamed: "set_slider",
            argumentsJSON: #"{"reasoning":"Raise volume.","element":18,"value":70}"#
        )
        #expect(decision?.action.kind == .setSlider)
        #expect(decision?.action.value == 70)
    }

    @Test func fillFormToolCallParsesFieldList() {
        let decision = AIService.decision(
            fromToolNamed: "fill_form",
            argumentsJSON: #"{"reasoning":"Fill the sign-up form.","fields":[{"element":7,"text":"Jane"},{"element":9,"text":"Doe"}],"submit":true}"#
        )
        #expect(decision?.action.kind == .fillForm)
        #expect(decision?.action.fields?.count == 2)
        #expect(decision?.action.fields?.first?.element == 7)
        #expect(decision?.action.fields?.first?.text == "Jane")
        #expect(decision?.action.submit == true)
    }

    @Test func dragToolCallParsesElementsAndCoordinateFallback() {
        let byElement = AIService.decision(
            fromToolNamed: "drag",
            argumentsJSON: #"{"reasoning":"Reorder the list.","from":3,"to":9}"#
        )
        #expect(byElement?.action.kind == .drag)
        #expect(byElement?.action.from == 3)
        #expect(byElement?.action.to == 9)

        let byCoords = AIService.decision(
            fromToolNamed: "drag",
            argumentsJSON: #"{"reasoning":"Slide the handle.","from_x":100,"from_y":200,"to_x":800,"to_y":200}"#
        )
        #expect(byCoords?.action.fromX == 100)
        #expect(byCoords?.action.toX == 800)
    }

    @Test func gestureAndSightToolCallsParse() {
        #expect(AIService.decision(fromToolNamed: "long_press", argumentsJSON: #"{"reasoning":"Hold the card.","element":5}"#)?.action.kind == .longPress)
        #expect(AIService.decision(fromToolNamed: "hover", argumentsJSON: #"{"reasoning":"Wake the menu.","element":4}"#)?.action.kind == .hover)
        let swipe = AIService.decision(fromToolNamed: "swipe", argumentsJSON: #"{"reasoning":"Next slide.","direction":"left","element":6}"#)
        #expect(swipe?.action.kind == .swipe)
        #expect(swipe?.action.direction == "left")
        #expect(AIService.decision(fromToolNamed: "page_overview", argumentsJSON: #"{"reasoning":"See the whole page."}"#)?.action.kind == .pageOverview)
    }

    // MARK: - Scanner payload parsing

    @Test func scanPayloadParsesIntoObservation() {
        let raw = #"{"ok":true,"vw":390,"vh":760,"sf":0.5,"dh":4.2,"ab":6,"be":42,"more":3,"ov":true,"partial":false,"els":[{"i":1,"k":"button","n":"Accept all","s":[],"v":"","e":false,"r":[10,20,120,44]},{"i":2,"k":"field","n":"Email","s":["empty","required"],"v":"","e":true,"r":[10,90,200,44]},{"i":3,"k":"weird","n":"","s":[],"v":"","e":false,"r":[10,150,50,50]}]}"#
        let observation = PageScanner.parse(raw)
        #expect(observation != nil)
        #expect(observation?.elements.count == 3)
        #expect(observation?.element(withID: 2)?.kind == .field)
        #expect(observation?.element(withID: 3)?.kind == .other)

        let map = observation?.mapText ?? ""
        #expect(map.contains(#"[1] button "Accept all""#))
        #expect(map.contains("(empty, required)"))
        #expect(map.contains("42 interactive elements below"))
        #expect(map.contains("overlay") || map.contains("dialog"))
        #expect(map.contains("+3 more"))
    }

    @Test func failedOrBlockedScanReturnsNil() {
        #expect(PageScanner.parse(#"{"ok":false,"why":"page not ready"}"#) == nil)
        #expect(PageScanner.parse("js error: script blocked") == nil)
        #expect(PageScanner.parse("") == nil)
    }

    @Test func filledFieldShowsValuePreviewInMap() {
        let raw = #"{"ok":true,"vw":390,"vh":760,"sf":0,"dh":1.0,"ab":0,"be":0,"more":0,"ov":false,"partial":false,"els":[{"i":1,"k":"field","n":"Search","s":["filled","focused"],"v":"running shoes","e":true,"r":[0,0,200,44]}]}"#
        let map = PageScanner.parse(raw)?.mapText ?? ""
        #expect(map.contains(#"filled: "running shoes""#))
        #expect(map.contains("focused"))
        #expect(map.contains("whole page fits on screen"))
    }

    // MARK: - Step display

    @Test func detailTextNamesTargetedElements() {
        var action = AgentAction(type: "tap_element")
        action.element = 14
        action.elementName = #"button "Add to cart""#
        #expect(action.detailText == #"[14] button "Add to cart""#)
    }

    @Test func typeIntoDetailTextShowsTextAndTarget() {
        var action = AgentAction(type: "type_into")
        action.element = 7
        action.elementName = #"field "Email""#
        action.text = "a@b.com"
        action.submit = true
        #expect(action.detailText.contains(#""a@b.com""#))
        #expect(action.detailText.contains("[7]"))
        #expect(action.detailText.contains("+ enter"))
    }

    @Test func repetitionSignatureSeparatesElementTargets() {
        var first = AgentAction(type: "tap_element")
        first.element = 3
        var second = AgentAction(type: "tap_element")
        second.element = 9
        #expect(first.repetitionSignature != second.repetitionSignature)
    }

    @Test func newActionKindsDescribeThemselves() {
        var slider = AgentAction(type: "set_slider")
        slider.element = 18
        slider.elementName = #"other "Volume""#
        slider.value = 70
        #expect(slider.detailText == #"[18] other "Volume" → 70%"#)

        var fill = AgentAction(type: "fill_form")
        fill.fields = [
            AgentAction.FormField(element: 7, text: "Jane"),
            AgentAction.FormField(element: 9, text: "Doe"),
            AgentAction.FormField(element: 11, text: "jane@d.com"),
        ]
        fill.submit = true
        #expect(fill.detailText == "3 fields + submit")

        var drag = AgentAction(type: "drag")
        drag.from = 3
        drag.to = 9
        #expect(drag.detailText == "[3] → [9]")

        var toggle = AgentAction(type: "set_toggle")
        toggle.element = 22
        toggle.on = false
        #expect(toggle.detailText.contains("OFF"))
    }

    // MARK: - Overview slice math

    @Test func overviewPlanCoversWholePageExactly() {
        let plan = OverviewPlanner.plan(documentHeight: 4000, viewportHeight: 800)
        #expect(plan != nil)
        #expect(plan?.offsets == [0, 800, 1600, 2400, 3200])
        #expect(plan?.lastSliceCropFraction == 0)
        #expect(plan?.coveredFraction == 1)
        #expect(plan?.coverageNote.contains("whole page") == true)
    }

    @Test func overviewPlanCapsVeryLongPages() {
        let plan = OverviewPlanner.plan(documentHeight: 8000, viewportHeight: 800)
        #expect(plan?.offsets.count == 6)
        #expect(plan?.totalScreens == 10)
        #expect((plan?.coveredFraction ?? 0) < 0.99)
        #expect(plan?.coverageNote.contains("first 6") == true)
    }

    @Test func overviewPlanCropsOverlappingLastSlice() {
        let plan = OverviewPlanner.plan(documentHeight: 2000, viewportHeight: 800)
        #expect(plan?.offsets == [0, 800, 1200])
        #expect(abs((plan?.lastSliceCropFraction ?? 0) - 0.5) < 0.001)
        #expect(plan?.coveredFraction == 1)
    }

    @Test func overviewPlanSkipsSingleScreenPages() {
        #expect(OverviewPlanner.plan(documentHeight: 800, viewportHeight: 800) == nil)
        #expect(OverviewPlanner.plan(documentHeight: 820, viewportHeight: 800) == nil)
    }

    // MARK: - Reaction verdicts

    @Test func reactionVerdictWording() {
        #expect(ReactionWatch.format(mutations: 0, urlChanged: false, newInteractive: 0).text.contains("no visible reaction"))
        let reacted = ReactionWatch.format(mutations: 14, urlChanged: false, newInteractive: 3).text
        #expect(reacted.contains("page reacted"))
        #expect(reacted.contains("14 changes"))
        #expect(reacted.contains("3 new interactive elements"))
        #expect(ReactionWatch.format(mutations: 0, urlChanged: true, newInteractive: 0).text.contains("address changed"))
    }

    @Test func reactionVerdictParsesEndPayloadAndNavigationFallback() {
        let parsed = ReactionWatch.verdict(
            fromRaw: #"{"ok":true,"muts":6,"added":4,"urlChanged":false,"newInteractive":2}"#,
            pageNavigated: false
        )
        #expect(parsed.text.contains("6 changes"))
        let navigated = ReactionWatch.verdict(fromRaw: "js error: frame gone", pageNavigated: true)
        #expect(navigated.text.contains("navigated"))
    }

    // MARK: - Embedded panel map lines

    @Test func panelElementsAreMarkedInTheMap() {
        var element = ScannedElement(
            id: 41, kind: .button, name: "Play", states: [], valuePreview: nil,
            isEditable: false, x: 30, y: 300, width: 60, height: 40
        )
        element.panelLabel = "youtube.com"
        #expect(element.mapLine == #"[41] button "Play" (in embedded panel: youtube.com)"#)

        let observation = PageObservation(
            elements: [element],
            viewportWidth: 390,
            viewportHeight: 760,
            scrollFraction: 0,
            documentHeightRatio: 1,
            elementsAbove: 0,
            elementsBelow: 0,
            unlistedVisibleCount: 0,
            overlayLikely: false,
            isPartial: false,
            blockedPanelCount: 1
        )
        let map = observation.mapText
        #expect(map.contains("in embedded panel: youtube.com"))
        #expect(map.contains("embedded widgets"))
        #expect(map.contains("1 embedded panel on screen couldn't be scanned"))
    }

    // MARK: - Badge drawing

    @Test @MainActor func annotatedSnapshotKeepsImageSize() {
        let size = CGSize(width: 200, height: 400)
        let base = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let observation = PageObservation(
            elements: [
                ScannedElement(id: 1, kind: .button, name: "Go", states: [], valuePreview: nil, isEditable: false, x: 20, y: 40, width: 80, height: 30),
                ScannedElement(id: 2, kind: .field, name: "Email", states: ["empty"], valuePreview: nil, isEditable: true, x: 20, y: 90, width: 120, height: 30),
            ],
            viewportWidth: 200,
            viewportHeight: 400,
            scrollFraction: 0,
            documentHeightRatio: 1,
            elementsAbove: 0,
            elementsBelow: 0,
            unlistedVisibleCount: 0,
            overlayLikely: false,
            isPartial: false
        )
        let annotated = SnapshotAnnotator.annotate(base, with: observation)
        #expect(annotated.size == size)
    }

    // MARK: - Pair 3: mission plan parsing

    private func samplePlan() -> MissionPlan {
        MissionPlan.make(
            from: [
                PlannedTask(title: "Open the flight search", doneWhen: "a search form is on screen", hint: "go straight to the search URL"),
                PlannedTask(title: "Search for those dates", doneWhen: "a results list with prices is on screen"),
                PlannedTask(title: "Read the cheapest fare", doneWhen: "a price is visible next to the cheapest option"),
            ],
            successStatement: "the cheapest fare for those dates is visible on screen",
            answerShape: "a price"
        )!
    }

    @Test func planNumbersTasksAndStartsOnTheFirst() {
        let plan = samplePlan()
        #expect(plan.tasks.map(\.number) == [1, 2, 3])
        #expect(plan.currentTask?.number == 1)
        #expect(plan.tasks[1].state == .pending)
        #expect(plan.answerShape == "a price")
        #expect(plan.progress == 0)
    }

    @Test func planFillsMissingFinishTestsAndDropsBlankTasks() {
        let plan = MissionPlan.make(
            from: [PlannedTask(title: "  "), PlannedTask(title: "Scroll to the bottom")],
            successStatement: "   ",
            answerShape: nil
        )
        #expect(plan?.tasks.count == 1)
        #expect(plan?.tasks.first?.doneWhen.isEmpty == false)
        #expect(plan?.successStatement == "the goal is achieved")
        #expect(MissionPlan.make(from: [], successStatement: "x", answerShape: nil) == nil)
    }

    @Test func planCapsTaskCount() {
        let drafts = (1...12).map { PlannedTask(title: "Task \($0)", doneWhen: "done \($0)") }
        let plan = MissionPlan.make(from: drafts, successStatement: "s", answerShape: nil)
        #expect(plan?.tasks.count == MissionPlan.maxTasks)
    }

    @Test func fallbackPlanIsOneTaskAndMarkedAsSuch() {
        let plan = MissionPlan.fallback(goal: "find the price")
        #expect(plan.tasks.count == 1)
        #expect(plan.isFallback)
        #expect(plan.currentTask?.number == 1)
        #expect(plan.briefingText.contains("planning was unavailable"))
    }

    // MARK: - Pair 3: checklist ticking and skip logic

    @Test func reportedEvidenceTicksTasksAndAdvancesTheCurrentOne() {
        var plan = samplePlan()
        let ticked = plan.apply(claimedCurrent: 1, completed: [1])
        #expect(ticked == 1)
        #expect(plan.tasks[0].state == .done)
        #expect(plan.currentTask?.number == 2)
        #expect(plan.doneCount == 1)
        #expect(abs(plan.progress - 1.0 / 3.0) < 0.001)
    }

    @Test func tickingTheSameTaskTwiceDoesNotDoubleCount() {
        var plan = samplePlan()
        #expect(plan.apply(claimedCurrent: 1, completed: [1]) == 1)
        #expect(plan.apply(claimedCurrent: 2, completed: [1]) == 0)
        #expect(plan.doneCount == 1)
    }

    @Test func jumpingAheadMarksSteppedOverTasksSkippedNotDone() {
        var plan = samplePlan()
        plan.apply(claimedCurrent: 3, completed: [])
        #expect(plan.tasks[0].state == .skipped)
        #expect(plan.tasks[1].state == .skipped)
        #expect(plan.tasks[0].skipReason?.isEmpty == false)
        #expect(plan.currentTask?.number == 3)
        #expect(plan.doneCount == 0)
        #expect(plan.skippedCount == 2)
        #expect(plan.briefingText.contains("[skipped]"))
    }

    @Test func unknownTaskNumbersAreIgnored() {
        var plan = samplePlan()
        #expect(plan.apply(claimedCurrent: 99, completed: [42]) == 0)
        #expect(plan.currentTask?.number == 1)
    }

    @Test func untickingSendsTheAgentBackToTheLastFinishedTask() {
        var plan = samplePlan()
        plan.apply(claimedCurrent: 3, completed: [1, 2, 3])
        #expect(plan.currentTask == nil)
        plan.untickLatest()
        #expect(plan.currentTask?.number == 3)
        #expect(plan.doneCount == 2)
    }

    // MARK: - Pair 3: re-planning

    @Test func revisionKeepsFinishedTasksAndContinuesNumbering() {
        var plan = samplePlan()
        plan.apply(claimedCurrent: 1, completed: [1])
        plan.revise(with: [
            PlannedTask(title: "Use the site's own filter panel", doneWhen: "only May dates are listed"),
            PlannedTask(title: "Read the cheapest fare", doneWhen: "a price is visible"),
        ])
        #expect(plan.tasks.count == 3)
        #expect(plan.tasks[0].state == .done)
        #expect(plan.tasks.map(\.number) == [1, 4, 5])
        #expect(plan.currentTask?.number == 4)
        #expect(plan.revisions == 1)
        #expect(plan.canRevise)
    }

    @Test func revisionsAreCappedPerMission() {
        var plan = samplePlan()
        plan.revise(with: [PlannedTask(title: "A", doneWhen: "a")])
        plan.revise(with: [PlannedTask(title: "B", doneWhen: "b")])
        #expect(plan.revisions == MissionPlan.maxRevisions)
        #expect(plan.canRevise == false)
    }

    @Test func revisePlanToolCallParses() {
        let decision = AIService.decision(
            fromToolNamed: "revise_plan",
            argumentsJSON: #"{"reasoning":"The site has no filter panel.","reason":"no filter panel exists","task":2,"completed_tasks":[1],"tasks":[{"title":"Sort by price instead","done_when":"the list is ordered cheapest first"}]}"#
        )
        #expect(decision?.action.kind == .revisePlan)
        #expect(decision?.action.tasks?.count == 1)
        #expect(decision?.action.tasks?.first?.doneWhen == "the list is ordered cheapest first")
        #expect(decision?.action.task == 2)
        #expect(decision?.action.completedTasks == [1])
        #expect(decision?.action.detailText.contains("no filter panel exists") == true)
    }

    @Test func stepsReportProgressAgainstThePlan() {
        let decision = AIService.decision(
            fromToolNamed: "tap_element",
            argumentsJSON: #"{"reasoning":"Open the cheapest fare.","element":9,"task":3,"completed_tasks":[1,2]}"#
        )
        #expect(decision?.action.task == 3)
        #expect(decision?.action.completedTasks == [1, 2])
    }

    @Test func theAppsOwnCheckEntryIsNotCallableByTheModel() {
        #expect(AIService.decision(fromToolNamed: "independent_check", argumentsJSON: "{}") == nil)
        #expect(AgentActionKind.verify.isModelCallable == false)
        #expect(AgentActionKind.revisePlan.isModelCallable)
        #expect(AgentActionKind.revisePlan.isPageAction == false)
        #expect(AgentActionKind.tapElement.isPageAction)
    }

    // MARK: - Pair 3: the briefing the doer reads

    @Test func briefingLeadsWithTheCurrentTaskAndItsFinishTest() {
        var plan = samplePlan()
        plan.apply(claimedCurrent: 1, completed: [1])
        let briefing = plan.briefingText
        #expect(briefing.contains("MISSION PLAN — 1 of 3 tasks done"))
        #expect(briefing.contains("1. [x] Open the flight search"))
        #expect(briefing.contains("YOUR CURRENT TASK: 2."))
        #expect(briefing.contains("a results list with prices is on screen"))
        #expect(briefing.contains("SUCCESS MEANS:"))
        #expect(briefing.contains("ANSWER SHAPE: a price"))
        #expect(briefing.contains("completed_tasks"))
    }

    @Test func briefingAsksForADecisionOnceEverythingIsSettled() {
        var plan = samplePlan()
        plan.apply(claimedCurrent: 3, completed: [1, 2, 3])
        #expect(plan.briefingText.contains("EVERY TASK IS SETTLED"))
    }

    // MARK: - Pair 3: verdicts and honest outcomes

    @Test func rejectedVerdictFallsBackToEvidenceAsPushback() {
        let withObjection = VerificationResult(verdict: .rejected, evidence: "the cart badge reads 0", objection: "the cart still shows zero items")
        #expect(withObjection.pushback == "the cart still shows zero items")

        let withoutObjection = VerificationResult(verdict: .unclear, evidence: "the page was still loading")
        #expect(withoutObjection.pushback == "the page was still loading")

        let bare = VerificationResult(verdict: .unclear, evidence: "")
        #expect(bare.pushback.isEmpty == false)
    }

    @Test func unconfirmedIsItsOwnOutcomeAndNeverReadsAsCompleted() {
        #expect(RunOutcome.unconfirmed.rawValue == "unconfirmed")
        #expect(RunOutcome.unconfirmed.label == "DONE, NOT CONFIRMED")
        #expect(RunOutcome.unconfirmed.icon != RunOutcome.completed.icon)
    }

    // MARK: - Pair 3: history compatibility

    @Test func runsSavedBeforeMissionPlanningStillDecode() throws {
        let legacy = #"""
        [{"id":"6E8B0F7E-6A3A-4C6E-9E2E-0C1A2B3C4D5E","goal":"find the price","date":0,"outcome":"completed","summary":"done","steps":[{"id":"7E8B0F7E-6A3A-4C6E-9E2E-0C1A2B3C4D5E","index":1,"actionType":"tap_element","actionDetail":"[1]","reasoning":"tap","statusRaw":"executed"}]}]
        """#
        let runs = try JSONDecoder().decode([AgentRun].self, from: Data(legacy.utf8))
        #expect(runs.count == 1)
        #expect(runs[0].plan == nil)
        #expect(runs[0].verdict == nil)
        #expect(runs[0].browserStepCount == 1)
        #expect(runs[0].steps[0].taskTitle == nil)
        #expect(runs[0].routingSplit == nil)
        #expect(runs[0].rewinds == nil)
        #expect(runs[0].steps[0].model == nil)
    }

    @Test func newRunsRoundTripThePlanAndVerdict() throws {
        var plan = samplePlan()
        plan.apply(claimedCurrent: 2, completed: [1])
        let run = AgentRun(
            id: UUID(),
            goal: "find the price",
            date: Date(timeIntervalSince1970: 0),
            outcome: .unconfirmed,
            summary: "claim not confirmed",
            steps: [],
            plan: plan,
            verdictRaw: VerificationVerdict.rejected.rawValue
        )
        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(AgentRun.self, from: data)
        #expect(decoded.plan?.tasks.count == 3)
        #expect(decoded.plan?.doneCount == 1)
        #expect(decoded.plan?.currentTask?.number == 2)
        #expect(decoded.verdict == .rejected)
        #expect(decoded.outcome == .unconfirmed)
    }

    // MARK: - Pair 4: the difficulty read

    private func page(
        _ elements: [ScannedElement],
        overlay: Bool = false,
        partial: Bool = false,
        blockedPanels: Int = 0
    ) -> PageObservation {
        PageObservation(
            elements: elements,
            viewportWidth: 390,
            viewportHeight: 760,
            scrollFraction: 0,
            documentHeightRatio: 1,
            elementsAbove: 0,
            elementsBelow: 0,
            unlistedVisibleCount: 0,
            overlayLikely: overlay,
            isPartial: partial,
            blockedPanelCount: blockedPanels
        )
    }

    private func target(_ id: Int, _ kind: ScannedElement.Kind = .button, _ name: String = "Go", states: [String] = []) -> ScannedElement {
        ScannedElement(
            id: id, kind: kind, name: name, states: states, valuePreview: nil,
            isEditable: false, x: 0, y: Double(id) * 40, width: 80, height: 30
        )
    }

    @Test func aSimpleCleanPageIsRoutine() {
        let read = DifficultyScout.read(.init(
            isFirstStep: false,
            observation: page([target(1), target(2, .link, "Next")])
        ))
        #expect(read.difficulty == .routine)
        #expect(read.isFlyingBlind == false)
        #expect(read.isIrreversible == false)
    }

    @Test func aFailedPageScanIsAlwaysHardAndFlagsFlyingBlind() {
        let read = DifficultyScout.read(.init(isFirstStep: false, observation: nil))
        #expect(read.difficulty == .hard)
        #expect(read.isFlyingBlind)
    }

    @Test func noReactionPlusRepetitionMakesAStepHard() {
        let read = DifficultyScout.read(.init(
            isFirstStep: false,
            observation: page([target(1)]),
            lastResult: "tapped <button> · no visible reaction",
            isRepeating: true
        ))
        #expect(read.difficulty == .hard)
        #expect(read.reasons.contains { $0.contains("no reaction") })
        #expect(read.briefingNote?.contains("HARD") == true)
    }

    @Test func aRejectedClaimAndAStuckTaskRaiseTheRead() {
        let read = DifficultyScout.read(.init(
            isFirstStep: false,
            observation: page([target(1)]),
            taskStuckCount: 4,
            hasObjection: true
        ))
        #expect(read.difficulty == .hard)
    }

    @Test func anOverlayAloneIsNormalNotHard() {
        let read = DifficultyScout.read(.init(
            isFirstStep: false,
            observation: page([target(1)], overlay: true)
        ))
        #expect(read.difficulty == .normal)
        #expect(read.briefingNote == nil)
    }

    @Test func lookAlikeTargetsAreNoticed() {
        let read = DifficultyScout.read(.init(
            isFirstStep: false,
            observation: page((1...4).map { target($0, .link, "Details") })
        ))
        #expect(read.reasons.contains { $0.contains("look the same") })
    }

    @Test func irreversibleMovesOnScreenAreFlagged() {
        let read = DifficultyScout.read(.init(
            isFirstStep: false,
            observation: page([target(1, .button, "Place order"), target(2)])
        ))
        #expect(read.isIrreversible)
        #expect(read.reasons.contains { $0.contains("irreversible") })
    }

    // MARK: - Pair 4: model routing

    private func routed(
        _ read: DifficultyRead,
        strategy: ModelStrategy = .auto,
        preferred: ModelChoice = .precise,
        isFirstStep: Bool = false,
        mustEscalate: Bool = false
    ) -> ModelRouter.Route {
        ModelRouter.route(.init(
            strategy: strategy,
            preferred: preferred,
            read: read,
            isFirstStep: isFirstStep,
            mustEscalate: mustEscalate
        ))
    }

    @Test func routineStepsGoToTheFastModelEvenForPreciseUsers() {
        let route = routed(.routine, preferred: .precise)
        #expect(route.choice == .fast)
        #expect(route.isForced == false)
    }

    @Test func everyForcedFrontierRuleHolds() {
        let routine = DifficultyRead.routine
        let firstStep = routed(routine, preferred: .fast, isFirstStep: true)
        #expect(firstStep.choice == .precise)
        #expect(firstStep.isForced)

        let blind = DifficultyRead(difficulty: .routine, reasons: [], isIrreversible: false, isFlyingBlind: true)
        #expect(routed(blind, preferred: .fast).choice == .precise)

        let risky = DifficultyRead(difficulty: .routine, reasons: [], isIrreversible: true, isFlyingBlind: false)
        #expect(routed(risky, preferred: .fast).choice == .precise)

        #expect(routed(routine, preferred: .fast, mustEscalate: true).choice == .precise)

        let hard = DifficultyRead(difficulty: .hard, reasons: [], isIrreversible: false, isFlyingBlind: false)
        #expect(routed(hard, preferred: .fast).choice == .precise)
    }

    @Test func normalStepsFollowYourPreference() {
        let normal = DifficultyRead(difficulty: .normal, reasons: ["busy page"], isIrreversible: false, isFlyingBlind: false)
        #expect(routed(normal, preferred: .fast).choice == .fast)
        #expect(routed(normal, preferred: .precise).choice == .precise)
    }

    @Test func explicitStrategiesOverrideTheRead() {
        let worst = DifficultyRead(difficulty: .hard, reasons: [], isIrreversible: true, isFlyingBlind: true)
        #expect(routed(worst, strategy: .alwaysFast, isFirstStep: true).choice == .fast)
        #expect(routed(.routine, strategy: .alwaysPrecise).choice == .precise)
    }

    // MARK: - Pair 4: weighing options

    @Test func weighOptionsParsesAShortlist() {
        let turn = AIService.turn(
            fromToolNamed: "weigh_options",
            argumentsJSON: #"{"reasoning":"Two links look right.","task":2,"candidates":[{"move":"tap_element","element":5,"rationale":"the first result","confidence":70},{"move":"scroll","direction":"down","rationale":"look for a filter","confidence":40}]}"#
        )
        var note: String?
        var candidates: [MoveCandidate] = []
        if case .shortlist(let reasoning, let list)? = turn {
            note = reasoning
            candidates = list
        }
        #expect(note == "Two links look right.")
        #expect(candidates.count == 2)
        #expect(candidates[0].action.kind == .tapElement)
        #expect(candidates[0].action.task == 2)
        #expect(abs(candidates[0].confidence - 0.7) < 0.001)
        #expect(candidates[1].action.direction == "down")
    }

    @Test func shortlistDropsTerminalMovesAndAcceptsFractionalConfidence() {
        let turn = AIService.turn(
            fromToolNamed: "weigh_options",
            argumentsJSON: #"{"reasoning":"x","candidates":[{"move":"done","rationale":"finish","confidence":90},{"move":"tap_element","element":3,"rationale":"press it","confidence":0.8}]}"#
        )
        var candidates: [MoveCandidate] = []
        if case .shortlist(_, let list)? = turn { candidates = list }
        #expect(candidates.count == 1)
        #expect(candidates[0].action.kind == .tapElement)
        #expect(abs(candidates[0].confidence - 0.8) < 0.001)
    }

    @Test func anEmptyShortlistIsRejectedSoTheAppCanRetry() {
        #expect(AIService.shortlist(fromArgumentsJSON: #"{"candidates":[]}"#) == nil)
        #expect(AIService.shortlist(fromArgumentsJSON: "not json") == nil)
    }

    @Test func singleMoveTurnsStillComeBackAsMoves() {
        let turn = AIService.turn(fromToolNamed: "scroll", argumentsJSON: #"{"reasoning":"look lower","direction":"down"}"#)
        var kind: AgentActionKind?
        if case .move(let decision)? = turn { kind = decision.action.kind }
        #expect(kind == .scroll)
    }

    // MARK: - Pair 4: scoring the shortlist

    @Test func scoringPrefersMovesThatStillExistOnThePage() {
        var stale = AgentAction(type: "tap_element")
        stale.element = 99
        var live = AgentAction(type: "tap_element")
        live.element = 1
        let scored = CandidateScorer.score(
            [
                MoveCandidate(action: stale, rationale: "gone", confidence: 0.9),
                MoveCandidate(action: live, rationale: "here", confidence: 0.6),
            ],
            in: CandidateScorer.Context(observation: page([target(1)]))
        )
        #expect(scored.first?.action.element == 1)
        #expect(scored.last?.note.contains("not on this screen") == true)
    }

    @Test func scoringPenalisesDisabledTargets() {
        var action = AgentAction(type: "tap_element")
        action.element = 1
        let scored = CandidateScorer.score(
            [MoveCandidate(action: action, rationale: "press it", confidence: 0.9)],
            in: CandidateScorer.Context(observation: page([target(1, .button, "Continue", states: ["disabled"])]))
        )
        #expect(scored[0].note.contains("disabled"))
        #expect(scored[0].score < 0.9)
    }

    @Test func scoringRemembersMovesThatAlreadyFailed() {
        var action = AgentAction(type: "tap_element")
        action.element = 1
        let scored = CandidateScorer.score(
            [MoveCandidate(action: action, rationale: "again", confidence: 0.9)],
            in: CandidateScorer.Context(
                observation: page([target(1)]),
                failedSignatures: [action.repetitionSignature]
            )
        )
        #expect(scored[0].score < 0.5)
        #expect(scored[0].note.contains("already failed"))
    }

    @Test func scoringKeepsTheModelsOrderOnTies() {
        var first = AgentAction(type: "scroll")
        first.direction = "down"
        var second = AgentAction(type: "scroll")
        second.direction = "up"
        let scored = CandidateScorer.score(
            [
                MoveCandidate(action: first, rationale: "a", confidence: 0.5),
                MoveCandidate(action: second, rationale: "b", confidence: 0.5),
            ],
            in: CandidateScorer.Context(observation: page([target(1)]))
        )
        #expect(scored[0].rationale == "a")
        #expect(scored[0].score == scored[1].score)
    }

    @Test func scoringPenalisesIrreversibleMovesTheTaskDidNotAskFor() {
        var buy = AgentAction(type: "tap_element")
        buy.element = 1
        buy.elementName = #"button "Buy now""#
        let task = MissionTask(number: 1, title: "Read the cheapest fare", doneWhen: "a price is visible", state: .current)
        let scored = CandidateScorer.score(
            [MoveCandidate(action: buy, rationale: "purchase it", confidence: 0.8)],
            in: CandidateScorer.Context(observation: page([target(1)]), currentTask: task)
        )
        #expect(scored[0].note.contains("irreversible"))
        #expect(scored[0].score < 0.8)
    }

    @Test func scoringRewardsCandidatesThatServeTheCurrentTask() {
        var action = AgentAction(type: "navigate")
        action.url = "https://example.test/flights?sort=price"
        let task = MissionTask(number: 2, title: "Sort flights by price", doneWhen: "cheapest first", state: .current)
        let scored = CandidateScorer.score(
            [MoveCandidate(action: action, rationale: "go straight to the sorted list", confidence: 0.5)],
            in: CandidateScorer.Context(observation: page([target(1)]), currentTask: task)
        )
        #expect(scored[0].score > 0.5)
        #expect(scored[0].note.contains("fits the current task"))
    }

    // MARK: - Pair 4: checkpoints and rewind

    @Test func rewindToolCallParses() {
        let decision = AIService.decision(
            fromToolNamed: "rewind",
            argumentsJSON: #"{"reasoning":"This route is dead.","bookmark":2,"reason":"the filter panel does not exist"}"#
        )
        #expect(decision?.action.kind == .rewind)
        #expect(decision?.action.bookmark == 2)
        #expect(decision?.action.detailText.contains("checkpoint 2") == true)
        #expect(AgentActionKind.rewind.isPageAction == false)
        #expect(AgentActionKind.rewind.isModelCallable)
    }

    @Test func bookmarksTrackWhatHasBeenTriedFromThem() {
        var bookmark = PageBookmark(number: 1, label: "results", urlString: "https://x.test", scrollY: 120, thumbnail: nil)
        #expect(bookmark.hasUntriedRoute)
        #expect(bookmark.triedLine.contains("nothing tried"))
        bookmark.tried = ["TAP filters → no visible reaction", "SELECT sort → wrong options", "SCROLL down → nothing new"]
        #expect(bookmark.hasUntriedRoute == false)
        #expect(bookmark.triedLine.contains("no visible reaction"))
        #expect(PageBookmark.capacity == 5)
    }

    @Test func bookmarkNumbersSurviveTheRingBufferDroppingOldOnes() {
        var kept: [PageBookmark] = []
        for number in 1...7 {
            kept.append(PageBookmark(number: number, label: "page \(number)", urlString: "https://x.test/\(number)", scrollY: 0, thumbnail: nil))
            if kept.count > PageBookmark.capacity {
                kept.removeFirst(kept.count - PageBookmark.capacity)
            }
        }
        #expect(kept.count == PageBookmark.capacity)
        #expect(kept.map(\.number) == [3, 4, 5, 6, 7])
    }

    // MARK: - Pair 4: honest accounting

    @Test func routingSplitReadsHonestly() {
        let routed = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: [],
            fastSteps: 7,
            preciseSteps: 4
        )
        #expect(routed.routingSplit == "7 fast, 4 precise")

        let unrouted = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: []
        )
        #expect(unrouted.routingSplit == nil)
    }

    // MARK: - Hardening: the reaction check on the everyday moves

    @Test func aVerdictIsNeverTackedOntoAMoveThatNeverRan() {
        let stale = "element 4 is no longer on the page — the page changed; look again before acting"
        #expect(ReactionWatch.combine(stale, "no visible reaction") == stale)
        #expect(ReactionWatch.shouldAttachVerdict(to: "tap error: boom") == false)
        #expect(ReactionWatch.shouldAttachVerdict(to: "type_into was missing its element number") == false)
        #expect(ReactionWatch.shouldAttachVerdict(to: "[7] already ON — no action taken") == false)
        #expect(ReactionWatch.shouldAttachVerdict(to: #"tapped [3] button "Search""#))
        #expect(ReactionWatch.combine("tapped [3]", "") == "tapped [3]")
        #expect(ReactionWatch.combine("tapped [3]", "page reacted (14 changes)") == "tapped [3] · page reacted (14 changes)")
    }

    @Test func everyHonestFailureWordingEscalatesTheNextStep() {
        #expect(ReactionWatch.readsAsFailure("tapped [3] · no visible reaction — this site may need real finger input"))
        #expect(ReactionWatch.readsAsFailure("scrolled down 600px · the page did not move — you may be at the end of the page"))
        #expect(ReactionWatch.readsAsFailure(#"typed "jane" into [7] · the field did not take the text — it is still empty"#))
        #expect(ReactionWatch.readsAsFailure("went back · the address did not change — that move went nowhere"))
        #expect(ReactionWatch.readsAsFailure("couldn't go back — there is no earlier page to return to"))
        #expect(ReactionWatch.readsAsFailure("tapped [3] · page reacted (14 changes)") == false)
        #expect(ReactionWatch.readsAsFailure(#"typed "jane" into [7] · the field now holds "jane""#) == false)
        #expect(ReactionWatch.readsAsFailure("scrolled down 600px · the page moved 600px") == false)
    }

    @Test func scrollIsJudgedByMovementNotByPageChanges() {
        let moved = ReactionWatch.scrollVerdict(movedBy: 612, watcher: "no visible reaction — this site may need real finger input")
        #expect(moved.text == "the page moved 612px")

        let lazyLoaded = ReactionWatch.scrollVerdict(movedBy: 0, watcher: "page reacted (24 changes)")
        #expect(lazyLoaded.text.contains("did not move but page reacted"))
        #expect(ReactionWatch.readsAsFailure(lazyLoaded.text) == false)

        let stuck = ReactionWatch.scrollVerdict(movedBy: 2, watcher: "no visible reaction — this site may need real finger input")
        #expect(stuck.text.contains("end of the page"))
        #expect(ReactionWatch.readsAsFailure(stuck.text))
    }

    @Test func typingIsJudgedByWhatTheFieldHolds() {
        let took = ReactionWatch.typingVerdict(typed: "running shoes", fieldValue: "running shoes", watcher: "no visible reaction", submitted: false)
        #expect(took.text == #"the field now holds "running shoes""#)
        #expect(ReactionWatch.readsAsFailure(took.text) == false)

        let refused = ReactionWatch.typingVerdict(typed: "running shoes", fieldValue: "", watcher: "no visible reaction", submitted: false)
        #expect(refused.text.contains("did not take the text"))

        let reformatted = ReactionWatch.typingVerdict(typed: "4155551234", fieldValue: "(415) 555-1234", watcher: "no visible reaction", submitted: false)
        #expect(reformatted.text.contains("reformatted"))
        #expect(ReactionWatch.readsAsFailure(reformatted.text) == false)

        let submitted = ReactionWatch.typingVerdict(typed: "shoes", fieldValue: "shoes", watcher: "page reacted (address changed, 40 changes)", submitted: true)
        #expect(submitted.text.contains("after submit: page reacted"))

        let navigatedAway = ReactionWatch.typingVerdict(typed: "shoes", fieldValue: nil, watcher: "the page navigated to a new address", submitted: true)
        #expect(navigatedAway.text == "the page navigated to a new address")

        let vanished = ReactionWatch.typingVerdict(typed: "shoes", fieldValue: nil, watcher: "no visible reaction", submitted: false)
        #expect(vanished.text.contains("no longer on the page"))
    }

    @Test func goingBackAndOpeningAddressesNeedTheAddressToMove() {
        let moved = ReactionWatch.addressVerdict(before: "https://a.test/1", after: "https://www.b.test/2")
        #expect(moved.text == "landed on b.test/2")
        #expect(ReactionWatch.readsAsFailure(moved.text) == false)

        let stuck = ReactionWatch.addressVerdict(before: "https://a.test/1", after: "https://a.test/1")
        #expect(stuck.text.contains("went nowhere"))
        #expect(ReactionWatch.readsAsFailure(stuck.text))

        let blank = ReactionWatch.addressVerdict(before: "https://a.test/1", after: "")
        #expect(blank.text.contains("did not load"))
        #expect(ReactionWatch.shortAddress("https://www.example.test/" + String(repeating: "x", count: 90)).count <= 60)
    }

    // MARK: - Hardening: honest cost accounting

    @Test func theTallyCountsEveryCallYouPaidFor() {
        let run = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: [],
            fastSteps: 8,
            preciseSteps: 5,
            planningCalls: 1,
            checkCalls: 1
        )
        #expect(run.totalCalls == 13)
        #expect(run.callBreakdown == "13 calls — 11 steps, 1 plan, 1 check")
        #expect(run.routingSplit == "8 fast, 5 precise")
    }

    @Test func theBreakdownOmitsPartsThatNeverHappened() {
        let noPlanning = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .failed,
            summary: "s",
            steps: [],
            fastSteps: 3,
            preciseSteps: 0
        )
        #expect(noPlanning.callBreakdown == "3 calls — 3 steps")

        let legacy = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: []
        )
        #expect(legacy.totalCalls == nil)
        #expect(legacy.callBreakdown == nil)
    }

    @Test func callCountsRoundTripThroughSavedHistory() throws {
        let run = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: [],
            fastSteps: 4,
            preciseSteps: 2,
            planningCalls: 1,
            checkCalls: 2
        )
        let decoded = try JSONDecoder().decode(AgentRun.self, from: JSONEncoder().encode(run))
        #expect(decoded.planningCalls == 1)
        #expect(decoded.checkCalls == 2)
        #expect(decoded.callBreakdown == "6 calls — 3 steps, 1 plan, 2 checks")
    }

    // MARK: - Hardening: the check is not a step

    @Test func theCheckEntryNeverBorrowsAStepNumber() {
        let move = AgentStep(
            index: 7,
            action: AgentAction(type: "tap_element"),
            reasoning: "",
            result: nil,
            status: .executed,
            snapshot: nil,
            pageMap: nil
        )
        #expect(move.displayNumber == "07")
        #expect(move.isCheckEntry == false)

        let check = AgentStep(
            index: 0,
            action: AgentAction(type: AgentActionKind.verify.rawValue),
            reasoning: "",
            result: nil,
            status: .terminal,
            snapshot: nil,
            pageMap: nil
        )
        #expect(check.isCheckEntry)
        #expect(check.displayNumber == "✓")
    }

    @Test func savedCheckEntriesShowATickEvenOnOlderRuns() {
        let legacyCheck = PersistedStep(
            id: UUID(),
            index: 9,
            actionType: AgentActionKind.verify.rawValue,
            actionDetail: "CONFIRMED",
            reasoning: "the price is on screen",
            result: nil,
            statusRaw: "terminal",
            thumbnailFile: nil
        )
        #expect(legacyCheck.displayNumber == "✓")

        let move = PersistedStep(
            id: UUID(),
            index: 9,
            actionType: "scroll",
            actionDetail: "down 600px",
            reasoning: "look lower",
            result: "scrolled down",
            statusRaw: "executed",
            thumbnailFile: nil
        )
        #expect(move.displayNumber == "09")
    }

    @Test func stepsRememberWhichModelDecidedThem() throws {
        let step = PersistedStep(
            id: UUID(),
            index: 1,
            actionType: "scroll",
            actionDetail: "down 600px",
            reasoning: "look lower",
            result: "scrolled down",
            statusRaw: "executed",
            thumbnailFile: nil,
            modelRaw: ModelChoice.fast.rawValue,
            difficultyRaw: StepDifficulty.routine.rawValue,
            weighedCount: 3
        )
        let decoded = try JSONDecoder().decode(PersistedStep.self, from: JSONEncoder().encode(step))
        #expect(decoded.model == .fast)
        #expect(decoded.difficulty == .routine)
        #expect(decoded.weighedCount == 3)
    }

    // MARK: - Pair 5 helpers

    private func element(
        _ id: Int,
        _ kind: ScannedElement.Kind,
        _ name: String,
        x: Double = 20,
        y: Double = 100,
        width: Double = 80,
        height: Double = 40
    ) -> ScannedElement {
        ScannedElement(
            id: id,
            kind: kind,
            name: name,
            states: [],
            valuePreview: nil,
            isEditable: kind == .field,
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    private func observation(_ elements: [ScannedElement]) -> PageObservation {
        PageObservation(
            elements: elements,
            viewportWidth: 390,
            viewportHeight: 844,
            scrollFraction: 0,
            documentHeightRatio: 2,
            elementsAbove: 0,
            elementsBelow: 0,
            unlistedVisibleCount: 0,
            overlayLikely: false,
            isPartial: false
        )
    }

    private func fingerprint(_ name: String, kind: ScannedElement.Kind = .button) -> ElementFingerprint {
        ElementFingerprint(name: name, kind: kind, neighbourhood: [], approxX: 0.5, approxY: 0.3)
    }

    private func tapMove(_ name: String, committing: Bool = false) -> RecipeMove {
        RecipeMove(
            action: AgentActionKind.tapElement.rawValue,
            target: fingerprint(name),
            isCommitting: committing
        )
    }

    private func scrollMove() -> RecipeMove {
        RecipeMove(action: AgentActionKind.scroll.rawValue, direction: "down", amount: 600)
    }

    private func recipe(
        host: String = "shop.test",
        intent: String,
        title: String = "Route",
        moves: [RecipeMove] = [],
        helped: Int = 0,
        strays: Int = 0
    ) -> SiteRecipe {
        SiteRecipe(
            host: host,
            intent: intent,
            title: title,
            moves: moves,
            stepCount: 5,
            helpedCount: helped,
            strayCount: strays
        )
    }

    private func read(
        _ difficulty: StepDifficulty,
        irreversible: Bool = false,
        blind: Bool = false
    ) -> DifficultyRead {
        DifficultyRead(
            difficulty: difficulty,
            reasons: ["a test moment"],
            isIrreversible: irreversible,
            isFlyingBlind: blind
        )
    }

    // MARK: - Stage A: the free tier's four honest states

    @Test func everyUnavailableReasonGetsItsOwnPlainExplanation() {
        #expect(OnDeviceState.ready.isReady)
        for state in OnDeviceState.allCases where state != .ready {
            #expect(state.isReady == false)
            #expect(state.label.isEmpty == false)
            #expect(state.caption.isEmpty == false)
        }
        // Conflating the reasons is what makes these features feel broken, so
        // every state must read differently.
        #expect(Set(OnDeviceState.allCases.map(\.caption)).count == OnDeviceState.allCases.count)
    }

    @Test func aFreeAnswerThatDidNotArriveAlwaysExplainsItself() {
        #expect(OnDeviceAnswer.answered("TAP 3").text == "TAP 3")
        #expect(OnDeviceAnswer.answered("TAP 3").handoffNote == nil)
        #expect(OnDeviceAnswer.timedOut.text == nil)
        #expect(OnDeviceAnswer.timedOut.handoffNote?.contains("too long") == true)
        #expect(OnDeviceAnswer.refused("declined on safety grounds").handoffNote == "declined on safety grounds")
        #expect(OnDeviceAnswer.unavailable(.notEnabled).handoffNote?.contains("apple intelligence") == true)
        #expect(OnDeviceAnswer.failed("boom").handoffNote == "boom")
    }

    @Test func aSafetyRefusalIsTreatedAsAHesitationNotAFailure() {
        let refusal = OnDeviceModel.classify(NSError(domain: "guardrailViolation", code: 1))
        #expect(refusal == .refused("your iPhone's model declined this one on safety grounds"))

        let tooLong = OnDeviceModel.classify(NSError(domain: "exceededContextWindowSize", code: 2))
        #expect(tooLong == .failed("the request was too long for your iPhone's model"))

        let downloading = OnDeviceModel.classify(NSError(domain: "modelNotReady", code: 3))
        #expect(downloading == .unavailable(.downloading))

        let unknown = OnDeviceModel.classify(NSError(domain: "somethingElse", code: 4))
        #expect(unknown == .failed("your iPhone's model couldn't answer"))
    }

    // MARK: - Stage B: nothing the free tier says runs unchecked

    @Test func theGateRejectsEveryMoveTheFreeTierMayNotMake() {
        let page = observation([element(1, .button, "Search")])
        let forbidden: [AgentActionKind] = [
            .typeInto, .fillForm, .selectOption, .setToggle, .setSlider, .drag,
            .longPress, .hover, .swipe, .tap, .typeText, .navigate, .extract,
            .pageOverview, .revisePlan, .rewind, .done, .fail,
        ]
        for kind in forbidden {
            let ruling = OnDeviceGate.review(AgentAction(type: kind.rawValue), against: page)
            #expect(ruling.isAllowed == false, "\(kind.rawValue) must never be a free move")
        }
        #expect(OnDeviceGate.allowedKinds == [.scroll, .wait, .back, .tapElement])
    }

    @Test func aFreeTapNeedsARealReachableClearlyLabelledTarget() {
        let page = observation([
            element(1, .button, "Search"),
            element(2, .button, ""),
            element(3, .field, "Email"),
            element(4, .button, "Offscreen", x: 900, y: 40),
        ])
        func tap(_ id: Int?, against page: PageObservation?) -> OnDeviceGate.Ruling {
            var action = AgentAction(type: AgentActionKind.tapElement.rawValue)
            action.element = id
            return OnDeviceGate.review(action, against: page)
        }
        #expect(tap(1, against: page).action?.element == 1)
        #expect(tap(nil, against: page).isAllowed == false)
        #expect(tap(77, against: page).isAllowed == false)
        #expect(tap(2, against: page).isAllowed == false)
        #expect(tap(3, against: page).isAllowed == false)
        #expect(tap(4, against: page).isAllowed == false)
        // With no page scan there is nothing to check the answer against.
        #expect(tap(1, against: nil).isAllowed == false)
    }

    @Test func theFreeTierIsNeverAllowedAnIrreversibleTap() {
        let page = observation([
            element(1, .button, "Place order"),
            element(2, .button, "Delete account"),
            element(3, .button, "Accept all cookies"),
        ])
        func tap(_ id: Int) -> OnDeviceGate.Ruling {
            var action = AgentAction(type: AgentActionKind.tapElement.rawValue)
            action.element = id
            return OnDeviceGate.review(action, against: page)
        }
        #expect(tap(1).isAllowed == false)
        #expect(tap(2).isAllowed == false)
        // Clearing a cookie wall is exactly what the free tier is for.
        #expect(tap(3).isAllowed)
        #expect(OnDeviceGate.isDismissal("Accept all cookies"))
        #expect(OnDeviceGate.isDismissal("Place order") == false)
    }

    @Test func aFreeScrollIsNormalizedIntoSafeBounds() {
        func scroll(_ direction: String, _ amount: Double?) -> AgentAction? {
            var action = AgentAction(type: AgentActionKind.scroll.rawValue)
            action.direction = direction
            action.amount = amount
            return OnDeviceGate.review(action, against: observation([])).action
        }
        #expect(scroll("down", 600)?.amount == 600)
        #expect(scroll("down", 99_999)?.amount == 2_000)
        #expect(scroll("up", 1)?.amount == 100)
        #expect(scroll("sideways", 600) == nil)
        #expect(OnDeviceGate.review(AgentAction(type: "wait"), against: nil).isAllowed)
        #expect(OnDeviceGate.review(AgentAction(type: "back"), against: nil).isAllowed)
    }

    // MARK: - Stage C: the tiny move set, strictly parsed

    @Test func theFreeAnswerParserAcceptsOnlyThePermittedForms() {
        #expect(OnDeviceDecider.parse("TAP 7")?.action.element == 7)
        #expect(OnDeviceDecider.parse("tap 7 | it is the search button")?.action.element == 7)
        #expect(OnDeviceDecider.parse("MOVE: TAP 7")?.action.element == 7)
        #expect(OnDeviceDecider.parse("SCROLL DOWN")?.action.amount == 600)
        #expect(OnDeviceDecider.parse("SCROLL DOWN 900")?.action.amount == 900)
        #expect(OnDeviceDecider.parse("SCROLL UP 300")?.action.direction == "up")
        #expect(OnDeviceDecider.parse("BACK")?.action.kind == .back)
        #expect(OnDeviceDecider.parse("WAIT")?.action.kind == .wait)
        #expect(OnDeviceDecider.parse("TAP 7 | because it searches")?.reasoning == "because it searches")
        #expect(OnDeviceDecider.parse("WAIT")?.reasoning.isEmpty == false)
    }

    @Test func aHesitantOrRamblingFreeAnswerGoesToTheCloud() {
        // Passing is always allowed and never wrong.
        #expect(OnDeviceDecider.parse("PASS") == nil)
        #expect(OnDeviceDecider.parse("PASS | not sure") == nil)
        #expect(OnDeviceDecider.parse("") == nil)
        // The strict first-line match doubles as the ramble detector.
        #expect(OnDeviceDecider.parse("Sure! I think you should tap the search button.") == nil)
        #expect(OnDeviceDecider.parse("TAP") == nil)
        #expect(OnDeviceDecider.parse("TAP seven") == nil)
        #expect(OnDeviceDecider.parse("TAP 3 4") == nil)
        #expect(OnDeviceDecider.parse("BUY 3") == nil)
        #expect(OnDeviceDecider.parse("SCROLL SIDEWAYS") == nil)
        #expect(OnDeviceDecider.parse("TAP 1\nTAP 2\nTAP 3\nTAP 4") == nil)
    }

    @Test func theFreeTierOnlyEverGetsRoutineSteps() {
        func choice(_ difficulty: StepDifficulty, freeReady: Bool) -> ModelChoice {
            ModelRouter.route(ModelRouter.Inputs(
                strategy: .auto,
                preferred: .precise,
                read: read(difficulty),
                isFirstStep: false,
                mustEscalate: false,
                onDeviceReady: freeReady
            )).choice
        }
        #expect(choice(.routine, freeReady: true) == .onDevice)
        #expect(choice(.routine, freeReady: false) == .fast)
        #expect(choice(.normal, freeReady: true) == .precise)
        #expect(choice(.hard, freeReady: true) == .precise)
    }

    @Test func aForcedFrontierRuleAlwaysBeatsTheFreeTier() {
        func choice(
            isFirstStep: Bool = false,
            mustEscalate: Bool = false,
            irreversible: Bool = false,
            blind: Bool = false
        ) -> ModelChoice {
            ModelRouter.route(ModelRouter.Inputs(
                strategy: .auto,
                preferred: .fast,
                read: read(.routine, irreversible: irreversible, blind: blind),
                isFirstStep: isFirstStep,
                mustEscalate: mustEscalate,
                onDeviceReady: true
            )).choice
        }
        #expect(choice(isFirstStep: true) == .precise)
        #expect(choice(mustEscalate: true) == .precise)
        #expect(choice(irreversible: true) == .precise)
        #expect(choice(blind: true) == .precise)
        #expect(choice() == .onDevice)
    }

    @Test func switchingTheFreeTierOffRestoresTodaysBehaviorExactly() {
        let inputs = ModelRouter.Inputs(
            strategy: .auto,
            preferred: .precise,
            read: read(.routine),
            isFirstStep: false,
            mustEscalate: false,
            onDeviceReady: true
        )
        #expect(ModelRouter.route(inputs).choice == .onDevice)
        // The step falls back here when a free answer is rejected.
        #expect(ModelRouter.cloudRoute(inputs).choice == .fast)

        let always = ModelRouter.Inputs(
            strategy: .alwaysFast,
            preferred: .precise,
            read: read(.routine),
            isFirstStep: false,
            mustEscalate: false,
            onDeviceReady: true
        )
        #expect(ModelRouter.route(always).choice == .fast)
    }

    @Test func theFreeTierIsNeverOfferedAsAPreferredCloudModel() {
        #expect(ModelChoice.cloudCases == [.precise, .fast])
        #expect(ModelChoice.cloudCases.contains(.onDevice) == false)
        #expect(ModelChoice.onDevice.isCloud == false)
        #expect(ModelChoice.precise.isCloud)
        #expect(ModelChoice.onDevice.shortLabel == "FREE")
    }

    @Test func aGoalRewriteThatDriftedIsRefused() {
        let original = "find the cheapest flight to Lisbon in March"
        let good = GoalRefiner.parse(
            "MISSION: Find the cheapest Lisbon flight in March\nWANTS: a price",
            original: original
        )
        #expect(good?.answerShape == "a price")
        #expect(good?.briefingLine.contains("READ AS:") == true)
        // A rewrite about something else entirely is worse than no rewrite.
        #expect(GoalRefiner.parse("MISSION: Order a pizza\nWANTS: action", original: original) == nil)
        #expect(GoalRefiner.parse("Sure, here you go!", original: original) == nil)
        // "action" is not an answer shape worth handing the planner.
        let doing = GoalRefiner.parse(
            "MISSION: Cancel the Lisbon booking\nWANTS: action",
            original: "cancel my Lisbon booking"
        )
        #expect(doing?.answerShape == nil)
        #expect(doing?.missionLine == "Cancel the Lisbon booking")
    }

    // MARK: - Stage D: finding a remembered element again

    @Test func aRememberedElementIsFoundByNameAndKindNotByPosition() {
        let page = observation([
            element(1, .button, "Search", x: 20, y: 700),
            element(2, .button, "Filter", x: 200, y: 700),
        ])
        // Remembered near the top; the live one has moved to the bottom.
        let remembered = ElementFingerprint(
            name: "Search",
            kind: .button,
            neighbourhood: ["Filter"],
            approxX: 0.15,
            approxY: 0.05
        )
        #expect(remembered.score(against: page.elements[0], in: page) > 0)
        #expect(remembered.score(against: page.elements[1], in: page) == 0)
    }

    @Test func aRenamedOrRetypedElementIsNeverMistakenForTheRememberedOne() {
        let page = observation([element(1, .link, "Search"), element(2, .button, "Searching")])
        let remembered = fingerprint("Search")
        #expect(remembered.score(against: page.elements[0], in: page) == 0)
        #expect(remembered.score(against: page.elements[1], in: page) == 0)
        #expect(ElementFingerprint.make(for: page.elements[1], in: page).name == "Searching")
    }

    @Test func aFingerprintPrefersTheTargetWhereItWasRemembered() {
        let page = observation([
            element(1, .button, "Next", x: 10, y: 10, width: 60, height: 30),
            element(2, .button, "Back", x: 90, y: 10, width: 60, height: 30),
            element(3, .button, "Next", x: 10, y: 700, width: 60, height: 30),
        ])
        let remembered = ElementFingerprint(
            name: "Next",
            kind: .button,
            neighbourhood: ["Back"],
            approxX: 0.1,
            approxY: 0.02
        )
        let top = remembered.score(against: page.elements[0], in: page)
        let bottom = remembered.score(against: page.elements[2], in: page)
        #expect(top > bottom)

        let made = ElementFingerprint.make(for: page.elements[0], in: page)
        #expect(made.neighbourhood.contains("Back"))
        #expect(made.approxY < 0.1)
    }

    // MARK: - Stage F: recall by site AND by intent

    @Test func aMemoryIsOnlyRecalledForTheSameKindOfGoal() {
        let vault = [recipe(intent: "find a product price", moves: [tapMove("Search")])]
        #expect(RecipeMatcher.best(for: "find the price of the blue chair", host: "shop.test", in: vault) != nil)
        // A different kind of goal on the same site is not a match.
        #expect(RecipeMatcher.best(for: "check the delivery estimate", host: "shop.test", in: vault) == nil)
        // Nor is the same kind of goal on a different site.
        #expect(RecipeMatcher.best(for: "find the price of the blue chair", host: "other.test", in: vault) == nil)
    }

    @Test func aCancelGoalNeverMatchesAFindRecipe() {
        let vault = [recipe(intent: "find a subscription price", moves: [tapMove("Search")])]
        // Same site, overlapping words, opposite meaning. This is the match that
        // must never happen.
        #expect(RecipeMatcher.best(for: "cancel my subscription", host: "shop.test", in: vault) == nil)
        #expect(RecipeMatcher.conflicts(["cancel", "order"], ["order"]))
        #expect(RecipeMatcher.conflicts(["price"], ["price", "product"]) == false)
    }

    @Test func anAmbiguousMatchIsNotUsedAtAll() {
        let vault = [
            recipe(intent: "track a delivery", title: "Delivery", moves: [tapMove("Orders")]),
            recipe(intent: "track a parcel", title: "Parcel", moves: [tapMove("Orders")]),
        ]
        // The goal sits between two recipes; half-remembering is worse than
        // reading the page fresh.
        #expect(RecipeMatcher.best(for: "track something for me", host: "shop.test", in: vault) == nil)
    }

    @Test func aSiteNamedInTheGoalIsRecalledEvenFromASearchPage() {
        let vault = [
            recipe(host: "amazon.co.uk", intent: "check a delivery date", title: "Delivery", moves: [tapMove("Orders")])
        ]
        let hosts = RecipeMatcher.candidateHosts(
            goal: "check my amazon delivery date",
            urlString: "https://duckduckgo.com/",
            in: vault
        )
        #expect(hosts.contains("amazon.co.uk"))
        #expect(hosts.contains("duckduckgo.com"))
        #expect(RecipeMatcher.primaryLabel("amazon.co.uk") == "amazon")
        #expect(RecipeMatcher.primaryLabel("shop.example.com") == "example")
        #expect(RecipeMatcher.normalizedHost("https://www.Shop.test/x") == "shop.test")

        let match = RecipeMatcher.best(
            for: "check my amazon delivery date",
            urlString: "https://duckduckgo.com/",
            in: vault
        )
        #expect(match?.recipe.host == "amazon.co.uk")
        #expect(match?.reason.contains("Delivery") == true)
    }

    @Test func aRetiredRecipeIsNeverRecalled() {
        let vault = [
            recipe(intent: "find a product price", moves: [tapMove("Search")], strays: SiteRecipe.strayLimit)
        ]
        #expect(vault[0].isRetired)
        #expect(RecipeMatcher.best(for: "find the price of a chair", host: "shop.test", in: vault) == nil)
    }

    @Test func theBriefingTellsTheAgentToTrustThePageOverTheMemory() {
        let learned = recipe(
            intent: "find a price",
            title: "Price check",
            moves: [tapMove("Search"), scrollMove()]
        )
        let briefing = learned.briefingText
        #expect(briefing.contains("PROVEN ROUTE"))
        #expect(briefing.contains("Search"))
        #expect(briefing.contains("trust the page"))
    }

    // MARK: - Stage G: the head start earns every replayed move

    @Test func theHeadStartNeverReplaysMoreThanThreeOpeningMoves() {
        let long = recipe(intent: "find a price", moves: [
            tapMove("Accept"), scrollMove(), tapMove("Search"), tapMove("Filter"), tapMove("Sort"),
        ])
        #expect(HeadStart.maxMoves == 3)
        #expect(HeadStart.plan(from: long)?.moves.count == 3)
    }

    @Test func theHeadStartStopsBeforeAnythingThatCommits() {
        let commits = recipe(intent: "buy a thing", moves: [
            tapMove("Search"), tapMove("Place order", committing: true), scrollMove(),
        ])
        let plan = HeadStart.plan(from: commits)
        #expect(plan?.moves.count == 1)
        #expect(plan?.moves.first?.target?.name == "Search")

        // A recipe whose very first move commits is not worth replaying at all.
        let immediate = recipe(intent: "buy a thing", moves: [tapMove("Pay now", committing: true)])
        #expect(HeadStart.plan(from: immediate) == nil)

        let retired = recipe(intent: "find a price", moves: [tapMove("Search")], strays: 2)
        #expect(HeadStart.plan(from: retired) == nil)
    }

    @Test func aRememberedAddressCarryingATypedQueryIsNeverReplayed() {
        let bare = RecipeMove(action: AgentActionKind.navigate.rawValue, urlString: "https://shop.test/deals")
        let carriesAValue = RecipeMove(
            action: AgentActionKind.navigate.rawValue,
            urlString: "https://shop.test/search?q=running+shoes"
        )
        #expect(bare.isSafeToReplay)
        #expect(carriesAValue.isSafeToReplay == false)
        #expect(bare.plainLine == "open shop.test/deals")

        // Typing is never replayed, because it would need a remembered value.
        let typing = RecipeMove(
            action: AgentActionKind.typeInto.rawValue,
            target: fingerprint("Search", kind: .field),
            valueKind: "what you're looking for"
        )
        #expect(typing.isSafeToReplay == false)
        #expect(typing.plainLine.contains("what you're looking for"))
    }

    @Test func aReplayThatCannotFindItsTargetHandsOverHonestly() {
        let page = observation([element(1, .button, "Sign in"), element(2, .link, "Help")])
        guard case .mismatch(let why) = HeadStart.resolve(tapMove("Search"), in: page) else {
            Issue.record("a target that is gone must never resolve")
            return
        }
        #expect(why.contains("Search"))
        #expect(why.contains("not on this page"))

        let line = HeadStart.handoverLine(atMove: 2, reason: why)
        #expect(line.hasPrefix("the remembered route stopped matching at move 2"))
        #expect(line.hasSuffix("carrying on by looking"))

        // No page scan means the memory cannot be confirmed either.
        #expect(HeadStart.resolve(tapMove("Search"), in: nil).action == nil)
    }

    @Test func aReplayFindsItsTargetEvenWhenTheBadgeNumberChanged() {
        let page = observation([element(9, .button, "Search", x: 100, y: 200)])
        #expect(HeadStart.resolve(tapMove("Search"), in: page).action?.element == 9)
        // A target that has become irreversible since is refused outright.
        let risky = observation([element(3, .button, "Place order")])
        #expect(HeadStart.resolve(tapMove("Place order"), in: risky).action == nil)
    }

    @Test func aReplayIsJudgedOnWhetherThePageReactedAsRemembered() {
        #expect(HeadStart.heldUp(expected: "the page reacted", actual: "tapped [3] · page reacted (12 changes)") == nil)
        #expect(HeadStart.heldUp(expected: nil, actual: "tapped [3] · page reacted (2 changes)") == nil)
        // A move that got nowhere ends the replay whatever was expected.
        #expect(HeadStart.heldUp(
            expected: nil,
            actual: "tapped [3] · no visible reaction — this site may need real finger input"
        ) != nil)
        // The address was supposed to change and did not.
        #expect(HeadStart.heldUp(expected: "the address changed", actual: "tapped [3] · page reacted (4 changes)") != nil)
        #expect(HeadStart.heldUp(expected: "the address changed", actual: "asked for x · landed on shop.test/deals") == nil)
    }

    @Test func aHeadStartEntryIsNeverNumberedLikeAStep() {
        var action = AgentAction(type: AgentActionKind.headStart.rawValue)
        action.summary = "replay 3 known opening moves"
        let entry = AgentStep(
            index: 0,
            action: action,
            reasoning: "",
            result: nil,
            status: .executed,
            snapshot: nil,
            pageMap: nil
        )
        #expect(entry.isHeadStartEntry)
        #expect(entry.isCheckEntry == false)
        #expect(entry.displayNumber == "»")
        #expect(entry.action.detailText == "replay 3 known opening moves")
        // The model can never call it, and it is not a page move.
        #expect(AgentActionKind.headStart.isModelCallable == false)
        #expect(AgentActionKind.headStart.isPageAction == false)

        let saved = PersistedStep(
            id: UUID(),
            index: 4,
            actionType: AgentActionKind.headStart.rawValue,
            actionDetail: "replayed 2 moves",
            reasoning: "",
            result: nil,
            statusRaw: "executed",
            thumbnailFile: nil
        )
        #expect(saved.displayNumber == "»")
    }

    @Test func aReplayedMoveCarriesNoModelChipBecauseNoModelDecidedIt() throws {
        let saved = PersistedStep(
            id: UUID(),
            index: 2,
            actionType: "tap_element",
            actionDetail: "[3]",
            reasoning: "replayed from a route that worked before",
            result: "tapped [3] · page reacted (7 changes)",
            statusRaw: "executed",
            thumbnailFile: nil,
            wasReplayed: true
        )
        let decoded = try JSONDecoder().decode(PersistedStep.self, from: JSONEncoder().encode(saved))
        #expect(decoded.model == nil)
        #expect(decoded.wasReplayed == true)
        #expect(decoded.displayNumber == "02")
    }

    // MARK: - Stage E: what a memory is allowed to contain

    @Test func aRecipeNeverStoresAnythingTheUserTyped() throws {
        let secret = "jane.doe@example.com"
        let moves = [
            RecipeDistiller.Move(
                kind: .typeInto,
                fingerprint: fingerprint("Email", kind: .field),
                result: "typed \"\(secret)\" into [7] · the field now holds \"\(secret)\"",
                valueKind: "your details"
            ),
            RecipeDistiller.Move(
                kind: .navigate,
                result: "asked for x · landed on shop.test/search",
                urlString: "https://shop.test/search?q=\(secret)"
            ),
        ]
        let route = RecipeDistiller.route(from: moves)
        let stored = String(data: try JSONEncoder().encode(route), encoding: .utf8) ?? ""

        #expect(route.count == 2)
        #expect(stored.isEmpty == false)
        #expect(stored.contains(secret) == false)
        #expect(stored.contains("example.com") == false)
        #expect(stored.contains("jane") == false)
        // The field is remembered; what went in it is not.
        #expect(route[0].target?.name == "Email")
        #expect(route[0].valueKind == "your details")
        // An address carrying a typed query is not stored as an address at all.
        #expect(route[1].urlString == nil)
    }

    @Test func onlyTheMovesThatWorkedBecomePartOfTheRoute() {
        let moves = [
            RecipeDistiller.Move(
                kind: .tapElement,
                fingerprint: fingerprint("Accept"),
                result: "tapped [1] · page reacted (9 changes)"
            ),
            RecipeDistiller.Move(
                kind: .tapElement,
                fingerprint: fingerprint("Ghost"),
                result: "tapped [2] · no visible reaction — this site may need real finger input"
            ),
            RecipeDistiller.Move(
                kind: .scroll,
                result: "scrolled down 600px · the page moved 600px",
                direction: "down",
                amount: 600
            ),
            RecipeDistiller.Move(kind: .done, result: "no-op"),
        ]
        let route = RecipeDistiller.route(from: moves)
        #expect(route.count == 2)
        #expect(route.first?.target?.name == "Accept")
        #expect(route.first?.expectedReaction == "the page reacted")
        #expect(route.last?.expectedReaction == "the page scrolled")
        #expect(route.contains { $0.target?.name == "Ghost" } == false)

        // A trap the run actually hit is remembered as a caution.
        let traps = RecipeDistiller.mechanicalTraps(from: moves)
        #expect(traps.contains { $0.contains("Accept") })
        #expect(traps.contains { $0.contains("Ghost") })
    }

    @Test func aCommittingMoveIsMarkedSoItIsNeverReplayed() {
        #expect(RecipeDistiller.isCommitting(RecipeDistiller.Move(
            kind: .typeInto,
            fingerprint: fingerprint("Search", kind: .field),
            submitted: true
        )))
        #expect(RecipeDistiller.isCommitting(RecipeDistiller.Move(kind: .fillForm)))
        #expect(RecipeDistiller.isCommitting(RecipeDistiller.Move(
            kind: .tapElement,
            fingerprint: fingerprint("Place order")
        )))
        #expect(RecipeDistiller.isCommitting(RecipeDistiller.Move(
            kind: .tapElement,
            fingerprint: fingerprint("Search")
        )) == false)

        #expect(RecipeDistiller.storableAddress(RecipeDistiller.Move(
            kind: .navigate,
            urlString: "https://shop.test/deals"
        )) == "https://shop.test/deals")
        #expect(RecipeDistiller.storableAddress(RecipeDistiller.Move(
            kind: .navigate,
            urlString: "https://shop.test/s?q=shoes"
        )) == nil)
    }

    @Test func theLabelParserRefusesAnythingButTheThreeLines() {
        let good = RecipeDistiller.parseLabel(
            "INTENT: find a product price\nTITLE: Price check\nTRAPS: a cookie banner; a slow filter"
        )
        #expect(good?.intent == "find a product price")
        #expect(good?.title == "Price check")
        #expect(good?.traps.count == 2)

        let clean = RecipeDistiller.parseLabel("INTENT: track a parcel\nTITLE: Parcel\nTRAPS: none")
        #expect(clean?.traps.isEmpty == true)

        #expect(RecipeDistiller.parseLabel("Sure! Here is the label you asked for.") == nil)
        #expect(RecipeDistiller.parseLabel("TITLE: Price check") == nil)
        #expect(RecipeDistiller.parseLabel("INTENT: \nTITLE: Price check") == nil)
    }

    @Test func aMemoryIsStillWrittenWhenNoModelCanLabelIt() throws {
        let label = RecipeDistiller.fallbackLabel(goal: "find the price of the blue chair", host: "shop.test")
        #expect(label.intent.isEmpty == false)
        #expect(label.title.isEmpty == false)

        let built = RecipeDistiller.make(
            host: "shop.test",
            label: label,
            moves: [RecipeDistiller.Move(
                kind: .tapElement,
                fingerprint: fingerprint("Search"),
                result: "tapped [1] · page reacted (5 changes)"
            )],
            plan: nil,
            verdictEvidence: "the price £129 is on screen",
            stepCount: 4
        )
        #expect(built?.checks.contains("the price £129 is on screen") == true)
        #expect(built?.stepCount == 4)

        // A mechanical label still has to be matchable next time.
        let stored = try #require(built)
        #expect(RecipeMatcher.best(
            for: "find the price of the blue chair",
            host: "shop.test",
            in: [stored]
        ) != nil)
    }

    @Test func thereIsNothingToRememberWithoutAUsableRoute() {
        let label = RecipeDistiller.Label(intent: "find a price", title: "Price", traps: [])
        // No moves at all.
        #expect(RecipeDistiller.make(
            host: "shop.test",
            label: label,
            moves: [],
            plan: nil,
            verdictEvidence: nil,
            stepCount: 0
        ) == nil)
        // No site to attach it to.
        #expect(RecipeDistiller.make(
            host: "",
            label: label,
            moves: [RecipeDistiller.Move(kind: .tapElement, fingerprint: fingerprint("Search"), result: "ok")],
            plan: nil,
            verdictEvidence: nil,
            stepCount: 1
        ) == nil)
        // Every move failed, so nothing was proven.
        #expect(RecipeDistiller.make(
            host: "shop.test",
            label: label,
            moves: [RecipeDistiller.Move(
                kind: .tapElement,
                fingerprint: fingerprint("Search"),
                result: "tapped [1] · no visible reaction — this site may need real finger input"
            )],
            plan: nil,
            verdictEvidence: nil,
            stepCount: 1
        ) == nil)
    }

    // MARK: - Stage H: the vault keeps itself honest

    @Test func aRecipeThatGoesStaleTwiceRetiresItself() {
        var learned = recipe(intent: "find a price", moves: [tapMove("Search")])
        #expect(learned.isRetired == false)
        learned.strayCount = 1
        #expect(learned.isRetired == false)
        learned.strayCount = 2
        #expect(learned.isRetired)
        #expect(SiteRecipe.strayLimit == 2)
    }

    @Test func aRecipeThatKeepsWorkingIsPreferredOverALessProvenOne() {
        let proven = recipe(intent: "find a price", helped: 5)
        let fresh = recipe(intent: "find a price")
        let shaky = recipe(intent: "find a price", helped: 0, strays: 1)
        #expect(proven.confidence > fresh.confidence)
        #expect(fresh.confidence > shaky.confidence)
        #expect(proven.recordLine.contains("helped 5 times"))
        #expect(fresh.recordLine.contains("not used yet"))
        #expect(shaky.recordLine.contains("went stale"))
    }

    // MARK: - Stage J: the accounting stays truthful

    @Test func theThreeWaySplitIsTruthfulAboutWhatWasPaidFor() {
        let run = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: [],
            fastSteps: 4,
            preciseSteps: 3,
            planningCalls: 1,
            checkCalls: 1,
            memoryCalls: 1,
            freeSteps: 5
        )
        #expect(run.routingSplit == "5 free, 4 fast, 3 precise")
        // Free work is not a paid call and must never inflate the cost.
        #expect(run.totalCalls == 7)
        #expect(run.callBreakdown == "7 calls — 4 steps, 1 plan, 1 check, 1 memory · plus 5 free on your iPhone")
    }

    @Test func theRunHistoryRecordsWhetherTheMemoryHeldUp() {
        func run(memory: String?, replayed: Int?, held: Bool?) -> AgentRun {
            AgentRun(
                id: UUID(),
                goal: "g",
                date: Date(timeIntervalSince1970: 0),
                outcome: .completed,
                summary: "s",
                steps: [],
                memoryUsed: memory,
                replayedMoves: replayed,
                headStartHeld: held
            )
        }
        #expect(run(memory: nil, replayed: nil, held: nil).memoryLine == nil)
        #expect(run(memory: "Price check", replayed: 0, held: nil).memoryLine == "Price check — recalled, nothing replayed")
        #expect(run(memory: "Price check", replayed: 3, held: true).memoryLine == "Price check — 3 opening moves replayed")
        #expect(run(memory: "Price check", replayed: 1, held: false).memoryLine
                == "Price check — 1 opening move replayed, then the site had changed")
    }

    @Test func runsSavedBeforeAnyOfThisStillReadExactlyAsBefore() throws {
        let old = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: [],
            fastSteps: 2,
            preciseSteps: 1
        )
        let decoded = try JSONDecoder().decode(AgentRun.self, from: JSONEncoder().encode(old))
        #expect(decoded.freeSteps == nil)
        #expect(decoded.memoryCalls == nil)
        #expect(decoded.memoryLine == nil)
        #expect(decoded.headStartHeld == nil)
        // No free work, so the split and breakdown read as they always did.
        #expect(decoded.routingSplit == "2 fast, 1 precise")
        #expect(decoded.callBreakdown == "3 calls — 3 steps")
    }

    @Test func learnedRoutesSurviveBeingSavedAndReloaded() throws {
        let saved = recipe(
            intent: "find a product price",
            title: "Price check",
            moves: [tapMove("Search"), scrollMove()],
            helped: 2
        )
        let decoded = try JSONDecoder().decode(SiteRecipe.self, from: JSONEncoder().encode(saved))
        #expect(decoded.id == saved.id)
        #expect(decoded.intent == "find a product price")
        #expect(decoded.moves.count == 2)
        #expect(decoded.moves.first?.target?.name == "Search")
        #expect(decoded.helpedCount == 2)
        #expect(decoded.confidence == saved.confidence)
        #expect(decoded.routeLines.count == 2)
    }

    // MARK: - Pair 6 helpers

    private func typeIntoMove(
        _ name: String,
        valueKind: String = "what you're looking for",
        submits: Bool = false,
        committing: Bool = false
    ) -> RecipeMove {
        RecipeMove(
            action: AgentActionKind.typeInto.rawValue,
            target: fingerprint(name, kind: .field),
            isCommitting: committing,
            valueKind: valueKind,
            submits: submits
        )
    }

    private func ranMove(
        _ kind: AgentActionKind,
        _ name: String? = nil,
        result: String = "the page reacted",
        submitted: Bool = false,
        valueKind: String? = nil
    ) -> RecipeDistiller.Move {
        RecipeDistiller.Move(
            kind: kind,
            fingerprint: name.map { fingerprint($0, kind: kind == .typeInto ? .field : .button) },
            result: result,
            submitted: submitted,
            valueKind: valueKind
        )
    }

    private func caution(
        _ kind: LessonKind,
        subject: String? = nil,
        sightings: Int = 1,
        misses: Int = 0,
        lastSeen: Date = Date()
    ) -> SiteLesson {
        SiteLesson(
            host: "shop.test",
            kind: kind,
            caution: kind.mechanicalCaution(subject: subject),
            subject: subject,
            sightings: sightings,
            misses: misses,
            lastSeen: lastSeen
        )
    }

    // MARK: - Pair 6, item 11: lessons are about kinds of failure, not bad days

    @Test func aWallIsRecordedAsAGateLesson() {
        let drafts = LessonDistiller.read(LessonDistiller.Evidence(
            moves: [],
            outcome: .failed,
            failReason: "the site wants you to sign in before it shows the price"
        ))
        #expect(drafts.contains { $0.kind == .gate })
    }

    @Test func aControlThatDidNothingBecomesACautionNamingIt() {
        let drafts = LessonDistiller.read(LessonDistiller.Evidence(
            moves: [ranMove(.tapElement, "Apply filter", result: "tapped it · \(ReactionWatch.noReactionPhrase)")],
            outcome: .failed
        ))
        let lesson = drafts.first { $0.kind == .deadControl }
        #expect(lesson?.subject == "Apply filter")
        #expect(lesson?.caution.contains("Apply filter") == true)
    }

    @Test func aFieldThatDropsWhatWasTypedIsItsOwnKindOfLesson() {
        let drafts = LessonDistiller.read(LessonDistiller.Evidence(
            moves: [ranMove(.typeInto, "Postcode", result: "the field did not take the text")],
            outcome: .failed
        ))
        #expect(drafts.contains { $0.kind == .typingIgnored && $0.subject == "Postcode" })
    }

    @Test func aBannerThatHadToBeClearedIsRememberedAsATrap() {
        let drafts = LessonDistiller.read(LessonDistiller.Evidence(
            moves: [ranMove(.tapElement, "Accept all", result: "the page reacted")],
            outcome: .failed
        ))
        #expect(drafts.contains { $0.kind == .overlay && $0.subject == "Accept all" })
    }

    @Test func aRejectedClaimTeachesThatThisPageLooksDoneWhenItIsNot() {
        let drafts = LessonDistiller.read(LessonDistiller.Evidence(
            moves: [],
            outcome: .unconfirmed,
            verdict: .rejected
        ))
        #expect(drafts.contains { $0.kind == .falseClaim })
    }

    @Test func theSameFailureTwiceInOneRunIsStillOneLesson() {
        let dead = "tapped it · \(ReactionWatch.noReactionPhrase)"
        let drafts = LessonDistiller.read(LessonDistiller.Evidence(
            moves: [
                ranMove(.tapElement, "Apply", result: dead),
                ranMove(.tapElement, "Apply", result: dead),
            ],
            outcome: .failed
        ))
        #expect(drafts.filter { $0.kind == .deadControl }.count == 1)
    }

    @Test func oneRunNeverLearnsMoreThanAHandfulOfThings() {
        let dead = ReactionWatch.noReactionPhrase
        let drafts = LessonDistiller.read(LessonDistiller.Evidence(
            moves: [
                ranMove(.tapElement, "Accept all"),
                ranMove(.tapElement, "One", result: dead),
                ranMove(.tapElement, "Two", result: dead),
                ranMove(.typeInto, "Three", result: dead),
            ],
            outcome: .unconfirmed,
            verdict: .rejected,
            hitStepLimit: true
        ))
        #expect(drafts.count <= LessonDistiller.maxDrafts)
    }

    @Test func aCautionIsDroppedWhenARouteThatStillWorksWalksStraightThroughIt() {
        let proven = recipe(intent: "find a price", moves: [tapMove("Apply filter")], helped: 3)
        #expect(LessonBook.isContradicted(caution(.deadControl, subject: "Apply filter"), by: [proven]))
        // Something got through, so "you cannot get through" is out of date.
        #expect(LessonBook.isContradicted(caution(.gate), by: [proven]))
    }

    @Test func aCautionAboutSomethingElseSurvivesAProvenRoute() {
        let proven = recipe(intent: "find a price", moves: [tapMove("Search")], helped: 3)
        #expect(!LessonBook.isContradicted(caution(.deadControl, subject: "Apply filter"), by: [proven]))
        #expect(!LessonBook.isContradicted(caution(.overlay, subject: "Accept all"), by: [proven]))
    }

    @Test func anUnprovenRouteContradictsNothing() {
        let unproven = recipe(intent: "find a price", moves: [tapMove("Apply filter")], helped: 0)
        #expect(!LessonBook.isContradicted(caution(.deadControl, subject: "Apply filter"), by: [unproven]))
    }

    @Test func twoMissesRetireACautionSoItStopsBeingHandedOver() {
        #expect(!caution(.overlay, misses: 1).isRetired)
        #expect(caution(.overlay, misses: SiteLesson.missLimit).isRetired)
    }

    @Test func aCautionNothingHasConfirmedForAMonthGoesStale() {
        #expect(caution(.slow, lastSeen: Date(timeIntervalSinceNow: -SiteLesson.staleAfter - 60)).isStale())
        #expect(!caution(.slow).isStale())
    }

    @Test func aCautionSeenAgainAndAgainOutweighsOneSeenOnce() {
        #expect(caution(.overlay, sightings: 5).weight > caution(.overlay, sightings: 1).weight)
        #expect(caution(.overlay, sightings: 1).weight > caution(.overlay, sightings: 1, misses: 1).weight)
    }

    @Test func aRewordedCautionIsRejectedWhenItDropsTheControlItNames() {
        let draft = LessonDistiller.make(.deadControl, subject: "Apply filter")
        #expect(LessonDistiller.parseCaution("CAUTION: pressing “Apply filter” does nothing here", original: draft) != nil)
        #expect(LessonDistiller.parseCaution("CAUTION: that button does nothing here", original: draft) == nil)
        #expect(LessonDistiller.parseCaution("Sure! Here you go.", original: draft) == nil)
    }

    // MARK: - Pair 6, item 12: replays that repair themselves

    @Test func aStepThatStillMatchesNeedsNoRepair() {
        let page = observation([element(4, .field, "Search")])
        #expect(StepHealer.repair(for: fingerprint("Search", kind: .field), in: page) == .exact(4))
    }

    @Test func aRenamedControlIsMatchedWithoutAskingAnyone() {
        let page = observation([element(9, .button, "Search products")])
        guard case .relaxed(let id, let note) = StepHealer.repair(for: fingerprint("Search"), in: page) else {
            #expect(Bool(false), "a renamed control should heal for free")
            return
        }
        #expect(id == 9)
        #expect(note.contains("Search products"))
    }

    @Test func aPageThatMovedEverythingAsksForJudgementFromRealElementsOnly() {
        let page = observation([
            element(3, .button, "Search bar"),
            element(4, .button, "Basket"),
        ])
        let target = ElementFingerprint(
            name: "Search",
            kind: .button,
            neighbourhood: ["Account", "Menu", "Offers"],
            approxX: 0.9,
            approxY: 0.9
        )
        guard case .needsJudgement(let candidates) = StepHealer.repair(for: target, in: page) else {
            #expect(Bool(false), "an unclear page should ask rather than guess")
            return
        }
        #expect(!candidates.isEmpty)
        // The whole guardrail: every candidate is genuinely on the page.
        #expect(candidates.allSatisfy { page.element(withID: $0.id) != nil })
    }

    @Test func whenNothingCouldBeItTheReplayStopsInsteadOfPressingSomething() {
        let page = observation([element(2, .button, "Basket")])
        guard case .impossible(let why) = StepHealer.repair(for: fingerprint("Search", kind: .field), in: page) else {
            #expect(Bool(false), "nothing resembling the target must stop the replay")
            return
        }
        #expect(why.contains("Search"))
    }

    @Test func aRepairIsNeverAttemptedWithoutAPageScan() {
        guard case .impossible = StepHealer.repair(for: fingerprint("Search"), in: nil) else {
            #expect(Bool(false), "no scan means no repair")
            return
        }
    }

    @Test func labelsThatSharePurposeScoreHigherThanLabelsThatMerelyLookAlike() {
        #expect(StepHealer.nameAffinity("Search", "Search") == 1)
        #expect(StepHealer.nameAffinity("Search products", "Search") > StepHealer.minimumNameAffinity)
        #expect(StepHealer.nameAffinity("Basket", "Search") < StepHealer.minimumNameAffinity)
    }

    @Test func aFreeRepairAnswerIsThrownAwayUnlessItNamesSomethingOnTheShortlist() {
        let allowed = [
            StepHealer.Candidate(id: 7, descriptor: "button “Find”", closeness: 0.5),
            StepHealer.Candidate(id: 8, descriptor: "button “Filter”", closeness: 0.3),
        ]
        #expect(OnDeviceRepairer.parse("PICK: 7", allowed: allowed) == 7)
        #expect(OnDeviceRepairer.parse("PICK: none", allowed: allowed) == nil)
        #expect(OnDeviceRepairer.parse("PICK: 42", allowed: allowed) == nil)
        #expect(OnDeviceRepairer.parse("I think it is 7", allowed: allowed) == nil)
    }

    @Test func whatYouTypedBecomesABlankTheReplayAsksForNextTime() {
        guard let routine = RoutineBuilder.make(
            goal: "find the price of red trainers on shop.test",
            host: "shop.test",
            title: "Price check",
            moves: [typeIntoMove("Search"), tapMove("Sort")],
            typedValues: [0: "red trainers"]
        ) else {
            #expect(Bool(false), "a route with a typed value should still save")
            return
        }
        #expect(routine.blanks.count == 1)
        #expect(routine.blanks.first?.moveIndex == 0)
        #expect(routine.needsInput)
        // The value is gone; the question is what survives.
        #expect(!routine.goalTemplate.localizedCaseInsensitiveContains("red trainers"))
        #expect(routine.goalTemplate.contains(routine.blanks[0].token))
    }

    @Test func nothingATypedValueTouchedSurvivesBeingSavedToDisk() throws {
        guard let routine = RoutineBuilder.make(
            goal: "order 2 flat whites for collection",
            host: "coffee.test",
            title: "Morning order",
            moves: [typeIntoMove("Order note"), tapMove("Collect")],
            typedValues: [0: "flat whites"]
        ) else {
            #expect(Bool(false), "a route should save")
            return
        }
        let json = String(decoding: try JSONEncoder().encode(routine), as: UTF8.self)
        #expect(!json.localizedCaseInsensitiveContains("flat whites"))
    }

    @Test func fillingTheBlankInProducesTheGoalItWillRun() {
        guard let routine = RoutineBuilder.make(
            goal: "find the price of red trainers",
            host: "shop.test",
            title: "Price check",
            moves: [typeIntoMove("Search")],
            typedValues: [0: "red trainers"]
        ), let blank = routine.blanks.first else {
            #expect(Bool(false), "a route should save with its blank")
            return
        }
        #expect(!routine.isReadyToRun(with: [:]))
        #expect(routine.isReadyToRun(with: [blank.id: "blue chairs"]))
        #expect(routine.goal(filling: [blank.id: "blue chairs"]) == "find the price of blue chairs")
        #expect(routine.value(forMoveAt: 0, from: [blank.id: "blue chairs"]) == "blue chairs")
    }

    @Test func aBlankIsAppendedWhenTheValueNeverAppearedInTheGoal() {
        guard let routine = RoutineBuilder.make(
            goal: "check my delivery",
            host: "shop.test",
            title: "Delivery",
            moves: [typeIntoMove("Order number", valueKind: "your order number")],
            typedValues: [0: "A-1029"]
        ), let blank = routine.blanks.first else {
            #expect(Bool(false), "a route should save with its blank")
            return
        }
        #expect(routine.goalTemplate.contains(blank.token))
        #expect(!routine.goalTemplate.contains("A-1029"))
    }

    @Test func twoFieldsAskingForTheSameThingGetTheirOwnBlanks() {
        let blanks = RoutineBuilder.blanks(for: [typeIntoMove("From"), typeIntoMove("To")])
        #expect(blanks.count == 2)
        #expect(blanks[0].label != blanks[1].label)
        #expect(blanks[0].token != blanks[1].token)
    }

    @Test func aFormFillIsNeverGivenABlankBecauseItNeedsMoreThanOneValue() {
        let form = RecipeMove(
            action: AgentActionKind.fillForm.rawValue,
            isCommitting: true,
            valueKind: "your details"
        )
        #expect(RoutineBuilder.blanks(for: [form]).isEmpty)
    }

    @Test func pressingEnterInASearchBoxIsNotTreatedAsACommitment() {
        let search = ranMove(.typeInto, "Search", submitted: true)
        let payment = ranMove(.typeInto, "Card number", submitted: true)
        #expect(!RecipeDistiller.isCommitting(search))
        #expect(RecipeDistiller.isCommitting(payment))
    }

    @Test func aMoveThatCommitsIsNeverReplayedUnattended() {
        #expect(typeIntoMove("Search").isReplayableInRoutine)
        #expect(!typeIntoMove("Card number", committing: true).isReplayableInRoutine)
        #expect(tapMove("Open filters").isReplayableInRoutine)
        #expect(!tapMove("Place order", committing: true).isReplayableInRoutine)
    }

    @Test func aSavedRouteRemembersWhetherItPressedEnter() {
        let route = RecipeDistiller.route(from: [
            ranMove(.typeInto, "Search", submitted: true, valueKind: "what you're looking for")
        ])
        #expect(route.first?.submits == true)
        #expect(route.first?.isCommitting == false)
    }

    @Test func theRouteAndItsBlanksStillLineUpWhenAFailedMoveWasDropped() {
        let moves = [
            ranMove(.typeInto, "Search", valueKind: "what you're looking for"),
            ranMove(.tapElement, "Apply", result: ReactionWatch.noReactionPhrase),
            ranMove(.tapElement, "Sort"),
        ]
        #expect(RecipeDistiller.keptIndices(from: moves) == [0, 2])
        let route = RecipeDistiller.route(from: moves)
        #expect(route.count == 2)
        #expect(route[1].target?.name == "Sort")
    }

    @Test func replaysSurviveBeingSavedAndReloaded() throws {
        guard let routine = RoutineBuilder.make(
            goal: "find the price of red trainers",
            host: "shop.test",
            title: "Price check",
            moves: [typeIntoMove("Search"), tapMove("Sort")],
            typedValues: [0: "red trainers"]
        ) else {
            #expect(Bool(false), "a route should save")
            return
        }
        let decoded = try JSONDecoder().decode(Routine.self, from: JSONEncoder().encode(routine))
        #expect(decoded.id == routine.id)
        #expect(decoded.moves.count == 2)
        #expect(decoded.blanks.count == 1)
        #expect(decoded.routeLines.count == 2)
    }

    @Test func routesSavedBeforeReplaysExistedStillDecode() throws {
        let json = "{\"id\":\"\(UUID().uuidString)\",\"action\":\"tap_element\",\"isCommitting\":false}"
        let decoded = try JSONDecoder().decode(RecipeMove.self, from: Data(json.utf8))
        #expect(decoded.submits == nil)
        #expect(decoded.kind == .tapElement)
    }

    @Test func aReplayEntryGetsItsOwnMarkerInsteadOfAStepNumber() {
        var action = AgentAction(type: AgentActionKind.replay.rawValue)
        action.summary = "replay “Morning order”"
        let step = AgentStep(
            index: 0,
            action: action,
            reasoning: "",
            result: nil,
            status: .executed,
            snapshot: nil,
            pageMap: nil
        )
        #expect(step.isReplayEntry)
        #expect(step.displayNumber == "▸")
        // The app writes this entry itself, so a hallucinated tool of the same
        // name must never be accepted as a move.
        #expect(!AgentActionKind.replay.isModelCallable)
    }

    @Test func aRepairedStepSaysSoInSavedHistory() throws {
        let step = PersistedStep(
            id: UUID(),
            index: 3,
            actionType: AgentActionKind.tapElement.rawValue,
            actionDetail: "[4] button “Sort”",
            reasoning: "r",
            result: "the page reacted",
            statusRaw: StepStatus.executed.rawValue,
            thumbnailFile: nil,
            wasReplayed: true,
            wasHealed: true
        )
        let decoded = try JSONDecoder().decode(PersistedStep.self, from: JSONEncoder().encode(step))
        #expect(decoded.wasHealed == true)
        #expect(decoded.wasReplayed == true)
    }

    @Test func repairsAreCountedAsPaidCallsInTheBreakdown() {
        let run = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: [],
            fastSteps: 3,
            preciseSteps: 1,
            planningCalls: 1,
            checkCalls: 1,
            repairCalls: 1
        )
        #expect(run.totalCalls == 4)
        #expect(run.callBreakdown == "4 calls — 1 step, 1 plan, 1 check, 1 repair")
    }

    @Test func theReplayLineIsHonestAboutStoppingEarly() {
        func run(title: String?, replayed: Int?, healed: Int?, held: Bool?) -> AgentRun {
            AgentRun(
                id: UUID(),
                goal: "g",
                date: Date(timeIntervalSince1970: 0),
                outcome: .completed,
                summary: "s",
                steps: [],
                replayedMoves: replayed,
                headStartHeld: held,
                routineTitle: title,
                healedMoves: healed
            )
        }
        #expect(run(title: nil, replayed: 3, healed: nil, held: true).routineLine == nil)
        #expect(run(title: "Morning order", replayed: 4, healed: nil, held: true).routineLine
                == "Morning order — 4 moves replayed")
        #expect(run(title: "Morning order", replayed: 2, healed: 1, held: false).routineLine
                == "Morning order — 2 moves replayed, 1 repaired, then the site had changed too much")
    }

    @Test func aRunFromBeforeAnyOfThisStillReadsCorrectly() throws {
        let old = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: [],
            fastSteps: 1,
            preciseSteps: 1
        )
        let decoded = try JSONDecoder().decode(AgentRun.self, from: JSONEncoder().encode(old))
        #expect(decoded.routineTitle == nil)
        #expect(decoded.routineLine == nil)
        #expect(decoded.cautionLine == nil)
        #expect(decoded.healedMoves == nil)
        #expect(decoded.callBreakdown == "2 calls — 2 steps")
    }

    // MARK: - Pair 7: the repair that silently stopped pressing Enter

    @Test func aRepairedSearchStepStillPressesEnter() {
        let saved = typeIntoMove("Search", submits: true)
        let repaired = saved.retargeted(to: fingerprint("Search products", kind: .field))
        // The whole point of the repair is that the step keeps working. A repair
        // that finds the box and never submits looks like a success and is not one.
        #expect(repaired.submits == true)
        #expect(repaired.target?.name == "Search products")
    }

    @Test func aRepairChangesWhereToLookAndNothingElse() {
        let saved = RecipeMove(
            action: AgentActionKind.typeInto.rawValue,
            target: fingerprint("Search", kind: .field),
            expectedReaction: "the address changed",
            isCommitting: true,
            valueKind: "what you're looking for",
            submits: true,
            direction: "down",
            amount: 600,
            urlString: "https://shop.test/deals"
        )
        let repaired = saved.retargeted(to: fingerprint("Find", kind: .field))
        #expect(repaired.id == saved.id)
        #expect(repaired.action == saved.action)
        #expect(repaired.expectedReaction == saved.expectedReaction)
        #expect(repaired.isCommitting == saved.isCommitting)
        #expect(repaired.valueKind == saved.valueKind)
        #expect(repaired.submits == saved.submits)
        #expect(repaired.direction == saved.direction)
        #expect(repaired.amount == saved.amount)
        #expect(repaired.urlString == saved.urlString)
        #expect(repaired.target?.name == "Find")
    }

    // MARK: - Pair 7: a replay is never saved with a step it cannot perform

    @Test func aRunIsNeverSavedAsAReplayThatStopsDeadPartWayThrough() {
        let form = RecipeMove(
            action: AgentActionKind.fillForm.rawValue,
            target: fingerprint("Checkout"),
            isCommitting: true
        )
        let route = RoutineBuilder.savableRoute(from: [
            typeIntoMove("Search"),
            tapMove("Sort"),
            form,
            tapMove("Never reached"),
        ])
        #expect(route.count == 2)
        #expect(route.last?.target?.name == "Sort")
    }

    @Test func aRouteWhoseFirstStepCannotBeReplayedIsNotSavedAtAll() {
        let overview = RecipeMove(action: AgentActionKind.pageOverview.rawValue)
        #expect(RoutineBuilder.savableRoute(from: [overview, tapMove("Sort")]).isEmpty)
        #expect(RoutineBuilder.make(
            goal: "g",
            host: "shop.test",
            title: "T",
            moves: [overview, tapMove("Sort")],
            typedValues: [:]
        ) == nil)
    }

    @Test func aStepThatCommitsIsStillWorthSavingBecauseItStopsAndAsks() {
        // Committing moves belong in a replay — they just never run unattended.
        #expect(tapMove("Place order", committing: true).isSavableInRoutine)
        #expect(typeIntoMove("Card number", committing: true).isSavableInRoutine)
        // A form fill needs several values at once, so a replay cannot run it.
        #expect(!RecipeMove(
            action: AgentActionKind.fillForm.rawValue,
            target: fingerprint("Checkout"),
            isCommitting: true
        ).isSavableInRoutine)
    }

    @Test func aSavedReplayStaysAShortcutRatherThanBecomingAWorkflow() {
        let long = (1...12).map { tapMove("Step \($0)") }
        #expect(RoutineBuilder.savableRoute(from: long).count == RoutineBuilder.maxMoves)
    }

    // MARK: - Pair 7: history remembers replays, repairs and cautions

    @Test func historyRemembersWhichReplayRanAndWhatItCost() throws {
        let run = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: [],
            fastSteps: 4,
            preciseSteps: 2,
            planningCalls: 1,
            checkCalls: 1,
            routineTitle: "Morning order",
            healedMoves: 2,
            repairCalls: 1,
            cautionsUsed: 2,
            mistakesFlagged: 1
        )
        let decoded = try JSONDecoder().decode(AgentRun.self, from: JSONEncoder().encode(run))
        #expect(decoded.routineTitle == "Morning order")
        #expect(decoded.healedMoves == 2)
        #expect(decoded.cautionLine == "2 cautions from earlier failures on this site")
        #expect(decoded.mistakeLine == "you flagged 1 mistake")
        // The repair is billed as a repair rather than hidden inside thinking.
        #expect(decoded.callBreakdown == "6 calls — 3 steps, 1 plan, 1 check, 1 repair")
    }

    @Test func aRunWhereYouNeverSteppedInSaysNothingAboutMistakes() {
        let run = AgentRun(
            id: UUID(),
            goal: "g",
            date: Date(timeIntervalSince1970: 0),
            outcome: .completed,
            summary: "s",
            steps: []
        )
        #expect(run.mistakeLine == nil)
        #expect(run.cautionLine == nil)
    }

    // MARK: - Pair 7: a failure always leaves something behind to learn from

    @Test func aRunThatRanOutOfStepsLeavesACautionToRecord() {
        let drafts = LessonDistiller.read(LessonDistiller.Evidence(
            moves: [ranMove(.tapElement, "Apply", result: ReactionWatch.noReactionPhrase)],
            outcome: .failed,
            hitStepLimit: true
        ))
        #expect(!drafts.isEmpty)
        #expect(drafts.contains { $0.kind == .deadControl })
        // One rule for "what did this run learn", used both to write the cautions
        // down and to decide which old ones went unseen.
        #expect(Set(drafts.map { $0.kind }).count == drafts.count)
    }

    @Test func aCleanRunOnAQuietSiteLeavesNothingToLearn() {
        let drafts = LessonDistiller.read(LessonDistiller.Evidence(
            moves: [ranMove(.tapElement, "Sort")],
            outcome: .completed,
            verdict: .confirmed
        ))
        #expect(drafts.isEmpty)
    }

    // MARK: - Pair 7: your objection reaches the agent intact

    @Test func yourWordsReachTheAgentExactlyAsYouWroteThem() {
        let rule = MistakeBriefing.standingRule(
            move: "tap the link “Sponsored”",
            note: "that's the sponsored result, not the real one"
        )
        #expect(rule.contains("\"that's the sponsored result, not the real one\""))
        #expect(rule.contains("WORD FOR WORD"))
    }

    @Test func theMoveYouFlaggedIsNamedAndSaidToBeBarred() {
        let rule = MistakeBriefing.standingRule(move: "tap the link “Sponsored”", note: "wrong one")
        #expect(rule.contains("tap the link “Sponsored”"))
        #expect(rule.localizedCaseInsensitiveContains("barred"))
    }

    @Test func flaggingWithNothingWrittenStillMakesAUsableObjection() {
        let rule = MistakeBriefing.standingRule(move: "tap the button “Buy”", note: "   ")
        #expect(!rule.isEmpty)
        #expect(rule.localizedCaseInsensitiveContains("did not say what was wrong"))
        #expect(!rule.contains("WORD FOR WORD"))
    }

    @Test func theRewriteIsDemandedBeforeThePageIsTouchedAgain() {
        let rule = MistakeBriefing.standingRule(move: "scroll down", note: "wrong direction")
        let demand = MistakeBriefing.rewriteDemand(rule: rule)
        #expect(demand.hasPrefix(rule))
        #expect(demand.contains("revise_plan"))
        // The honest part: this costs the turn it was going to spend anyway.
        #expect(demand.contains("not an extra one"))
    }

    @Test func whenNoRewriteIsLeftYourObjectionIsHeldAsAHardRuleInstead() {
        let rule = MistakeBriefing.standingRule(move: "scroll down", note: "wrong direction")
        // The rule on its own never demands a rewrite — that is what makes it
        // usable when the mission's rewrites are gone.
        #expect(!rule.contains("revise_plan"))
        #expect(!rule.contains("BEFORE YOU TOUCH THE PAGE AGAIN"))
        #expect(rule.localizedCaseInsensitiveContains("outrank"))
    }

    @Test func aVeryLongObjectionIsTrimmedRatherThanCrowdingOutThePage() {
        let long = String(repeating: "x", count: 600)
        let rule = MistakeBriefing.standingRule(move: nil, note: long)
        #expect(!rule.contains(String(repeating: "x", count: MistakeBriefing.maxNoteLength + 1)))
    }

    @Test func reachingForThePageAnywayIsSaidPlainlyAndOnlyToleratedOnce() {
        let rule = MistakeBriefing.standingRule(move: "tap the button “Buy”", note: "not that one")
        let refusal = MistakeBriefing.refusalDemand(rule: rule)
        #expect(refusal.hasPrefix(rule))
        #expect(refusal.contains("WAS REFUSED"))
        #expect(MistakeBriefing.maxRefusals == 1)
        #expect(MistakeBriefing.barredLine.localizedCaseInsensitiveContains("barred"))
        #expect(MistakeBriefing.rewriteFirstLine.localizedCaseInsensitiveContains("rewritten"))
    }

    @Test func theSameMoveIsRecognisedAgainSoABarCanActuallyBeEnforced() {
        var flagged = AgentAction(type: AgentActionKind.tapElement.rawValue)
        flagged.element = 12
        var again = AgentAction(type: AgentActionKind.tapElement.rawValue)
        again.element = 12
        var different = AgentAction(type: AgentActionKind.tapElement.rawValue)
        different.element = 13

        let barred: Set<String> = [flagged.repetitionSignature]
        #expect(barred.contains(again.repetitionSignature))
        #expect(!barred.contains(different.repetitionSignature))
    }

    @Test func yourObjectionIsYourOwnEntryInTheLog() {
        var action = AgentAction(type: AgentActionKind.mistake.rawValue)
        action.summary = "that's the sponsored result"
        let step = AgentStep(
            index: 4,
            action: action,
            reasoning: "you rejected: tap the link “Sponsored”",
            result: "that move is barred for the rest of the run",
            status: .terminal,
            snapshot: nil,
            pageMap: nil
        )
        #expect(step.isMistakeEntry)
        #expect(step.displayNumber == "!")
        #expect(step.action.detailText == "that's the sponsored result")
    }

    @Test func theAgentCanNeverFileAnObjectionAgainstItself() {
        // The app writes this entry, so a hallucinated tool of the same name must
        // never be accepted as a move — and it is not a page action either, so it
        // can never end up in a saved route.
        #expect(!AgentActionKind.mistake.isModelCallable)
        #expect(!AgentActionKind.mistake.isPageAction)
    }

    @Test func yourObjectionIsMarkedAsYoursInSavedHistoryToo() {
        let step = PersistedStep(
            id: UUID(),
            index: 4,
            actionType: AgentActionKind.mistake.rawValue,
            actionDetail: "that's the sponsored result",
            reasoning: "r",
            result: nil,
            statusRaw: StepStatus.terminal.rawValue,
            thumbnailFile: nil
        )
        #expect(step.kind == .mistake)
        #expect(step.displayNumber == "!")
    }

    // MARK: - Pair 7: the live thinking panel

    @Test func aMoveIsDescribedInPlainWordsWithNoElementNumbers() {
        var tap = AgentAction(type: AgentActionKind.tapElement.rawValue)
        tap.element = 14
        tap.elementName = "button “Apply filter”"
        #expect(tap.plainSentence == "tap the button “Apply filter”")
        #expect(!tap.plainSentence.contains("14"))
        #expect(!tap.plainSentence.contains("["))
    }

    @Test func typingSaysWhetherItWillPressEnter() {
        var typing = AgentAction(type: AgentActionKind.typeInto.rawValue)
        typing.element = 7
        typing.elementName = "field “Search”"
        typing.text = "red trainers"
        #expect(!typing.plainSentence.contains("press enter"))
        typing.submit = true
        #expect(typing.plainSentence.contains("press enter"))
        #expect(typing.plainSentence.contains("red trainers"))
    }

    @Test func aMoveWithNoResolvedTargetStillReadsAsASentence() {
        let tap = AgentAction(type: AgentActionKind.tapElement.rawValue)
        #expect(tap.plainSentence == "tap a control")
    }

    @Test func everyMoveTheAgentCanMakeHasSomethingReadableToSay() {
        for kind in AgentActionKind.allCases {
            let sentence = AgentAction(type: kind.rawValue).plainSentence
            #expect(!sentence.trimmed.isEmpty, "\(kind.rawValue) has nothing to say")
        }
    }

    @Test func aPageThatRanButDidNothingIsNotReadAsASuccess() {
        #expect(ReactionWatch.readsAsNoReaction("tapped [4] · \(ReactionWatch.noReactionPhrase)"))
        #expect(!ReactionWatch.readsAsNoReaction("tapped [4] · page reacted (3 changes)"))
    }

    @Test func aRealFailureIsStillReadAsAFailure() {
        #expect(ReactionWatch.readsAsFailure("couldn't tap — [4] is no longer on the page"))
        #expect(!ReactionWatch.readsAsFailure("tapped [4] · page reacted (3 changes)"))
    }

    @Test @MainActor func theResultLineIsColouredHonestlyRatherThanOptimistically() {
        #expect(LiveThinkingPanel.resultColor("tapped [4] · page reacted (3 changes)") == Theme.green)
        #expect(LiveThinkingPanel.resultColor("tapped [4] · \(ReactionWatch.noReactionPhrase)") == Theme.amber)
        #expect(LiveThinkingPanel.resultColor("couldn't tap — [4] is no longer on the page") == Theme.red)
    }

    @Test func theTaskRailHasItsOwnMarkerForEveryStateAPlanCanBeIn() {
        let markers = [
            MissionTaskState.pending.icon,
            MissionTaskState.current.icon,
            MissionTaskState.done.icon,
            MissionTaskState.skipped.icon,
        ]
        #expect(markers.allSatisfy { !$0.isEmpty })
        #expect(Set(markers).count == 4)
    }

    // MARK: - Pair 7 — the dossier, and free field matching

    /// Builds one probed field. Defaults are "an ordinary empty text field".
    private func probe(
        _ id: Int,
        label: String = "",
        declared: String = "",
        attribute: String = "",
        type: String = "text",
        widget: FormFieldProbe.Widget = .text,
        required: Bool = false,
        empty: Bool = true,
        sensitive: Bool = false,
        options: [String] = []
    ) -> FormFieldProbe {
        FormFieldProbe(
            id: id,
            declared: declared,
            attribute: attribute,
            label: label,
            type: type,
            widget: widget,
            isRequired: required,
            isEmpty: empty,
            isSensitive: sensitive,
            options: options
        )
    }

    @Test func theDossierCannotHoldASecretAtAll() {
        // The guarantee is structural: there is no case to put a password in.
        let names = DossierFieldKind.allCases.map { $0.rawValue.lowercased() + " " + $0.label.lowercased() }
        for forbidden in ["password", "card", "cvv", "cvc", "security code", "social security", "national insurance", "passcode", "pin"] {
            #expect(!names.contains { $0.contains(forbidden) }, "the dossier must not be able to hold a \(forbidden)")
        }
    }

    @Test func everyFactHasSomethingToShowAndSomethingToMatchOn() {
        for kind in DossierFieldKind.allCases {
            #expect(!kind.label.isEmpty)
            #expect(!kind.placeholder.isEmpty)
            #expect(!kind.briefingName.isEmpty)
            #expect(!kind.phrases.isEmpty, "\(kind.rawValue) can never be matched")
        }
    }

    @Test func noTwoFactsClaimTheSameDeclaredPurpose() {
        var seen: [String: DossierFieldKind] = [:]
        for kind in DossierFieldKind.allCases {
            for token in kind.declaredTokens {
                #expect(seen[token] == nil, "\(token) is claimed by both \(seen[token]?.rawValue ?? "") and \(kind.rawValue)")
                seen[token] = kind
            }
        }
    }

    @Test func everyFactNameIsUniqueSoTheFreeReaderCannotBeAmbiguous() {
        let names = DossierFieldKind.allCases.map(\.briefingName)
        #expect(Set(names).count == names.count)
        #expect(!names.contains("none"), "'none' is the reader's refusal word and must not name a fact")
    }

    @Test func autocompleteSectionAndModePrefixesAreStripped() {
        #expect(FieldScripts.normalizeDeclared("section-work shipping address-line1") == "address-line1")
        #expect(FieldScripts.normalizeDeclared("billing postal-code") == "postal-code")
        #expect(FieldScripts.normalizeDeclared("EMAIL") == "email")
        #expect(FieldScripts.normalizeDeclared("off").isEmpty)
        #expect(FieldScripts.normalizeDeclared("  ").isEmpty)
    }

    @Test func theProbePayloadParsesIntoFields() {
        let raw = """
        {"ok":true,"fields":[
          {"i":3,"ac":"shipping address-line1","nm":"addr1","lb":"Street  address","tp":"text","wd":"text","rq":true,"em":true,"sn":false,"op":[]},
          {"i":9,"ac":"","nm":"pwd","lb":"Password","tp":"password","wd":"text","rq":true,"em":true,"sn":true,"op":[]}
        ]}
        """
        let fields = FieldScripts.parse(raw)
        #expect(fields?.count == 2)
        #expect(fields?.first?.declared == "address-line1")
        #expect(fields?.first?.label == "Street address")
        #expect(fields?.first?.isRequired == true)
        #expect(fields?.last?.isSensitive == true)
        #expect(FieldScripts.parse("{\"ok\":false}")?.isEmpty == true)
        #expect(FieldScripts.parse("blocked") == nil)
    }

    @Test func aDeclaredFieldNeedsNoGuessingAtAll() {
        #expect(FieldMatcher.declaredKind(for: probe(1, declared: "family-name")) == .lastName)
        #expect(FieldMatcher.declaredKind(for: probe(2, declared: "postal-code")) == .postcode)
        // type=email is a declaration in all but name.
        #expect(FieldMatcher.declaredKind(for: probe(3, type: "email")) == .email)
        #expect(FieldMatcher.declaredKind(for: probe(4, type: "tel")) == .phone)
        #expect(FieldMatcher.declaredKind(for: probe(5)) == nil)
    }

    @Test func phraseMatchingRespectsWordBoundaries() {
        // The classic false positive: "state" inside "real estate".
        #expect(!FieldMatcher.containsPhrase("real estate agent", "state"))
        #expect(FieldMatcher.containsPhrase("state / province", "state"))
        #expect(FieldMatcher.containsPhrase("home_state", "state"))
        #expect(FieldMatcher.containsPhrase("what is your full name?", "full name"))
        #expect(!FieldMatcher.containsPhrase("name full", "full name"))
    }

    @Test func theMostSpecificLabelWins() {
        #expect(FieldMatcher.labelKind(for: probe(1, label: "First name")) == .firstName)
        #expect(FieldMatcher.labelKind(for: probe(2, label: "Full name")) == .fullName)
        #expect(FieldMatcher.labelKind(for: probe(3, label: "Name")) == .fullName)
        #expect(FieldMatcher.labelKind(for: probe(4, label: "Expected salary")) == .salaryExpectation)
        #expect(FieldMatcher.labelKind(for: probe(5, label: "Do you require sponsorship?")) == .needsSponsorship)
        #expect(FieldMatcher.labelKind(for: probe(6, label: "Favourite colour")) == nil)
    }

    @Test func matchingSkipsSecretsFilledFieldsAndWidgetsItCannotWriteTo() {
        let probes = [
            probe(1, label: "Email", declared: "email"),
            probe(2, label: "Password", type: "password", sensitive: true),
            probe(3, label: "City", empty: false),
            probe(4, label: "Date of birth", widget: .date),
            probe(5, label: "Phone", declared: "tel"),
        ]
        let (matches, leftovers) = FieldMatcher.match(probes)
        #expect(matches.map(\.id) == [1, 5])
        #expect(leftovers.isEmpty)
        #expect(matches.allSatisfy { $0.source == .declared })
    }

    @Test func aFieldWithNoRecognisableWordsBecomesALeftover() {
        let (matches, leftovers) = FieldMatcher.match([probe(7, label: "Question 4")])
        #expect(matches.isEmpty)
        #expect(leftovers.map(\.id) == [7])
    }

    @Test func confirmFieldsAreKeptButTwoWeakGuessesAtOneFactAreNot() {
        let confirmed = FieldMatcher.dedupe([
            FieldMatch(probe: probe(1, label: "Email", declared: "email"), kind: .email, source: .declared),
            FieldMatch(probe: probe(2, label: "Confirm email"), kind: .email, source: .label),
        ])
        #expect(confirmed.count == 2, "a form that asks twice on purpose should be filled twice")

        let guessed = FieldMatcher.dedupe([
            FieldMatch(probe: probe(1, label: "Company"), kind: .currentEmployer, source: .label),
            FieldMatch(probe: probe(2, label: "Organisation"), kind: .currentEmployer, source: .label),
        ])
        #expect(guessed.count == 1, "two guesses at the same fact is a coin toss, not evidence")

        let oneCertain = FieldMatcher.dedupe([
            FieldMatch(probe: probe(1, label: "Company"), kind: .currentEmployer, source: .label),
            FieldMatch(probe: probe(2, label: "Employer", declared: "organization"), kind: .currentEmployer, source: .declared),
        ])
        #expect(oneCertain.count == 1)
        #expect(oneCertain.first?.source == .declared, "the field the site declared should win")
    }

    @Test func theFillPlanSeparatesReadyFromBlankFromUnknown() {
        let probes = [
            probe(1, label: "Email", declared: "email"),
            probe(2, label: "Notice period"),
            probe(3, label: "Question 4", required: true),
            probe(4, label: "CVV", sensitive: true),
            probe(5, label: "City", empty: false),
            probe(6, label: "Start date", widget: .date),
        ]
        let (matches, _) = FieldMatcher.match(probes)
        let plan = FieldMatcher.plan(probes: probes, matches: matches, available: [.email])

        #expect(plan.ready.map(\.id) == [1])
        #expect(plan.missing.map(\.id) == [2], "a matched fact with nothing stored must be reported, never invented")
        #expect(plan.unmatched.map(\.id) == [3])
        #expect(plan.sensitive.map(\.id) == [4])
        #expect(plan.alreadyFilled.map(\.id) == [5])
        #expect(plan.unsupported.map(\.id) == [6])
        #expect(plan.freeMatchCount == 2)
    }

    @Test func theFreeLineCountsWhereEachMatchCameFrom() {
        let plan = FillPlan(
            ready: [
                FieldMatch(probe: probe(1, declared: "email"), kind: .email, source: .declared),
                FieldMatch(probe: probe(2, label: "Notice period"), kind: .noticePeriod, source: .label),
                FieldMatch(probe: probe(3, label: "Where did you study"), kind: .school, source: .meaning),
            ],
            missing: [], unmatched: [], sensitive: [], alreadyFilled: [], unsupported: []
        )
        let line = plan.freeLine ?? ""
        #expect(line.contains("3 fields matched free"))
        #expect(line.contains("1 the site declared"))
        #expect(line.contains("1 from their labels"))
        #expect(line.contains("1 read by your iPhone"))
        #expect(FillPlan.empty.freeLine == nil)
    }

    @Test func theReportTellsTheAgentWhatIsStillItsJobAndNeverLeaksAValue() {
        let probes = [
            probe(1, label: "Email", declared: "email"),
            probe(2, label: "Notice period"),
            probe(3, label: "Question 4", required: true),
            probe(4, label: "CVV", sensitive: true),
        ]
        let (matches, _) = FieldMatcher.match(probes)
        let plan = FieldMatcher.plan(probes: probes, matches: matches, available: [.email])
        let report = plan.agentReport(filled: 1, failures: [], submitted: false)

        #expect(report.contains("filled 1 of 1"))
        #expect(report.contains("LEFT BLANK"))
        #expect(report.contains("NOT MATCHED"))
        #expect(report.contains("Question 4"))
        #expect(report.contains("(required)"))
        #expect(report.contains("SKIPPED ON PURPOSE"))
        #expect(!report.lowercased().contains("alex@example.com"))
    }

    @Test func theFreeReaderIsStrictAboutWhatItAccepts() {
        let asked = [probe(4, label: "Where did you study"), probe(5, label: "Your postcode")]
        let matches = OnDeviceFieldReader.parse(
            """
            4=school
            5=made up fact
            9=email
            4=city
            """,
            asking: asked
        )
        #expect(matches.count == 1, "only a real field with a real fact name survives")
        #expect(matches.first?.id == 4)
        #expect(matches.first?.kind == .school)
        #expect(matches.first?.source == .meaning)
    }

    @Test func theFreeReaderTreatsNoneAndRamblingAsARefusal() {
        let asked = [probe(4, label: "Question 4")]
        #expect(OnDeviceFieldReader.parse("4=none", asking: asked).isEmpty)
        #expect(OnDeviceFieldReader.parse("Sure! I think field 4 is the email one.", asking: asked).isEmpty)
        #expect(OnDeviceFieldReader.parse("", asking: asked).isEmpty)
    }

    @Test func theFreeReaderBatchesAndIgnoresFieldsWithNoWords() {
        let readable = (1...20).map { probe($0, label: "Question \($0)") }
        let batches = OnDeviceFieldReader.batches(readable + [probe(99)])
        #expect(batches.count == 2)
        #expect(batches.first?.count == OnDeviceFieldReader.batchSize)
        #expect(batches.flatMap { $0 }.count == 20, "a field with no label cannot be read by anyone")
        #expect(OnDeviceFieldReader.batches([probe(99)]).isEmpty)
    }

    @Test func theFreeReadersPromptOffersOnlyFactNamesAndNoValues() {
        let prompt = OnDeviceFieldReader.prompt(for: [probe(4, label: "Where did you study")])
        #expect(prompt.contains("ALLOWED NAMES"))
        #expect(prompt.contains("school"))
        #expect(prompt.contains("4=Where did you study"))
    }

    @Test func theDossierFillIsTheAppsOwnMoveWithItsOwnWords() {
        let kind = AgentActionKind.fillFromDossier
        #expect(kind.rawValue == "fill_from_dossier")
        #expect(kind.isModelCallable, "the agent has to be able to ask for it")
        #expect(kind.isPageAction)
        #expect(kind.label == "AUTOFILL")
        #expect(!kind.icon.isEmpty)

        var action = AgentAction(type: kind.rawValue)
        #expect(action.detailText == "from your dossier")
        #expect(action.plainSentence == "fill this form in from your dossier")
        action.submit = true
        #expect(action.detailText.contains("submit"))
        #expect(action.plainSentence.contains("and submit"))
    }

    @Test func theDossierMoveIsRemovedFromTheToolSetWhenItCannotBeUsed() {
        let withDossier = AIService.tools(hasPlan: false, hasDossier: true).map { $0.function.name }
        let without = AIService.tools(hasPlan: false, hasDossier: false).map { $0.function.name }
        #expect(withDossier.contains("fill_from_dossier"))
        #expect(!without.contains("fill_from_dossier"))
        #expect(without.contains("type_into"), "every other move stays exactly as it was")
        #expect(withDossier.count == without.count + 1)
    }

    @Test func theDossierFillCallParsesWithNoValuesInIt() {
        let turn = AIService.turn(
            fromToolNamed: "fill_from_dossier",
            argumentsJSON: "{\"submit\":true,\"reasoning\":\"this is the application form\"}"
        )
        guard case .move(let decision) = turn else {
            #expect(Bool(false), "fill_from_dossier should parse as a committed move")
            return
        }
        #expect(decision.action.kind == .fillFromDossier)
        #expect(decision.action.submit == true)
        #expect(decision.action.text == nil, "the model must never supply a value")
        #expect(decision.action.fields == nil)
    }

    @Test func aFinishedRunReportsWhatTheDossierDidAndWhatItCost() {
        var run = AgentRun(
            id: UUID(), goal: "apply", date: Date(), outcome: .completed,
            summary: "submitted", steps: []
        )
        #expect(run.dossierLine == nil)
        run.dossierFills = 18
        run.freeFieldMatches = 21
        let line = run.dossierLine ?? ""
        #expect(line.contains("18 fields filled from your dossier"))
        #expect(line.contains("21 matched free"))

        // Free matching must never appear in the paid tally.
        run.fastSteps = 2
        run.preciseSteps = 1
        #expect(run.totalCalls == 3)
        #expect(run.callBreakdown?.contains("3 calls") == true)
    }

    @Test func theMatchingPhaseSaysItIsFreeAndCountsAsThinking() {
        #expect(AgentPhase.matching.isBusyThinking)
        #expect(AgentPhase.matching.activityLine.contains("FREE"))
        #expect(AgentPhase.matching.label == "MATCHING")
    }

    @Test func aStepCanCarryTheFreeMatchNoteIntoHistory() {
        var step = AgentStep(
            index: 3,
            action: AgentAction(type: AgentActionKind.fillFromDossier.rawValue),
            reasoning: "the application form",
            result: "filled 12 of 12",
            status: .executed,
            snapshot: nil,
            pageMap: nil
        )
        step.dossierNote = "12 fields matched free"
        let persisted = PersistedStep(
            id: step.id,
            index: step.index,
            actionType: step.action.kind.rawValue,
            actionDetail: step.action.detailText,
            reasoning: step.reasoning,
            result: step.result,
            statusRaw: step.status.rawValue,
            thumbnailFile: nil,
            dossierNote: step.dossierNote
        )
        #expect(persisted.dossierNote == "12 fields matched free")
        #expect(persisted.kind == .fillFromDossier)

        // Old runs, saved before any of this existed, still decode.
        let legacy = """
        {"id":"\(UUID().uuidString)","index":1,"actionType":"tap_element","actionDetail":"[1]","reasoning":"go","statusRaw":"executed"}
        """
        let decoded = try? JSONDecoder().decode(PersistedStep.self, from: Data(legacy.utf8))
        #expect(decoded?.dossierNote == nil)
    }

    @Test func aFieldDescribesItselfWithoutRevealingItsContents() {
        let named = probe(7, label: "Email address")
        #expect(named.descriptor == "[7] \"Email address\"")
        let unnamed = probe(8, attribute: "field_x")
        #expect(unnamed.descriptor == "[8] \"field_x\"")
        let bare = probe(9, widget: .select)
        #expect(bare.descriptor.contains("dropdown"))
        #expect(probe(10, label: "City", required: true).requiredDescriptor.contains("(required)"))
    }

    @Test func onlyTheWidgetsAValueCanBeWrittenIntoAreCountedAsFillable() {
        #expect(FormFieldProbe.Widget.text.isFillable)
        #expect(FormFieldProbe.Widget.textarea.isFillable)
        #expect(FormFieldProbe.Widget.select.isFillable)
        #expect(!FormFieldProbe.Widget.date.isFillable)
        #expect(!FormFieldProbe.Widget.checkbox.isFillable)
        #expect(!FormFieldProbe.Widget.radio.isFillable)
        #expect(!FormFieldProbe.Widget.other.isFillable)
    }

    @Test func theProbeScriptRefusesToReadSecretsAndKeepsItsBudget() {
        let script = FieldScripts.probeScript
        #expect(script.contains("__rorkAgent"), "probes must use the same numbering the agent sees")
        #expect(script.contains("secret ? [] : optionsOf"), "a secret field's options are never read")
        #expect(script.contains("\(FieldScripts.maxFields)"))
    }

    // MARK: - Guided generation — the free tier stops parsing strings

    @Test func theGuidedReaderIgnoresAFieldItNeverAskedAbout() {
        let asked = [probe(4, label: "Where did you study"), probe(5, label: "Your postcode")]
        let sheet = OnDeviceFieldReader.Sheet(readings: [
            OnDeviceFieldReader.Reading(field: 4, fact: .school),
            OnDeviceFieldReader.Reading(field: 99, fact: .email),
            OnDeviceFieldReader.Reading(field: 4, fact: .city),
        ])
        let matches = OnDeviceFieldReader.resolve(sheet, asking: asked)

        #expect(matches.count == 1, "an unknown number is dropped, and only the first reading of a field counts")
        #expect(matches.first?.id == 4)
        #expect(matches.first?.kind == .school)
        #expect(matches.first?.source == .meaning)
    }

    @Test func anEmptyGuidedSheetIsARefusalRatherThanAGuess() {
        let matches = OnDeviceFieldReader.resolve(
            OnDeviceFieldReader.Sheet(readings: []),
            asking: [probe(4, label: "Question 4")]
        )
        #expect(matches.isEmpty, "omitting a label is how the model says it doesn't know")
    }

    @Test func theGuidedPromptCarriesLabelsOnlyBecauseTheSchemaCarriesTheFactNames() {
        let prompt = OnDeviceFieldReader.guidedPrompt(for: [probe(4, label: "Where did you study")])
        #expect(prompt.contains("4=Where did you study"))
        #expect(!prompt.contains("ALLOWED NAMES"), "the allowed names are the schema now, not prose")
        #expect(!prompt.contains("school"))
    }

    @Test func aDeclinedGuidedAskExplainsItselfAndYieldsNothing() {
        let declined = OnDeviceTyped<OnDeviceFieldReader.Sheet>.declined(.timedOut)
        #expect(declined.value == nil)
        #expect(declined.handoffNote == "your iPhone's model took too long")

        let answered = OnDeviceTyped.answered(OnDeviceFieldReader.Sheet(readings: []))
        #expect(answered.value != nil)
        #expect(answered.handoffNote == nil, "a real answer has nothing to hand off")
    }

    @Test func satisfyingASchemaEarnsALongerLeashThanPlainProse() {
        #expect(OnDeviceModel.guidedTimeout > OnDeviceModel.timeout)
    }

    @Test func everyFactNameIsSchemaSafe() {
        // The schema the model is constrained to is built from these cases, so an
        // unnamed or inconsistently cased case would be an ambiguous choice.
        for kind in DossierFieldKind.allCases {
            #expect(!kind.briefingName.isEmpty)
            #expect(kind.briefingName == kind.briefingName.lowercased())
        }
    }
}
