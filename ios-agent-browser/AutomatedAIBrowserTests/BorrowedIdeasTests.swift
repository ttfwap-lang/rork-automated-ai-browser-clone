//
//  BorrowedIdeasTests.swift
//  AutomatedAIBrowserTests
//
//  Focused reading, page-change detection, several moves per turn, the
//  person's turn, natural hands, and runs saved as editable scripts.
//

import Testing
import Foundation
@testable import AutomatedAIBrowser

struct BorrowedIdeasTests {

    private func page(_ elements: [ScannedElement], signature: String = "") -> PageObservation {
        var observation = PageObservation(
            elements: elements,
            viewportWidth: 390,
            viewportHeight: 760,
            scrollFraction: 0,
            documentHeightRatio: 3,
            elementsAbove: 0,
            elementsBelow: 0,
            unlistedVisibleCount: 0,
            overlayLikely: false,
            isPartial: false
        )
        observation.textSignature = signature
        return observation
    }

    private func target(_ id: Int, _ kind: ScannedElement.Kind = .button, _ name: String = "Go") -> ScannedElement {
        ScannedElement(
            id: id, kind: kind, name: name, states: [], valuePreview: nil,
            isEditable: kind == .field, x: 0, y: Double(id) * 40, width: 80, height: 30
        )
    }

    // MARK: - Focused reading

    private var longPage: String {
        let filler = (1...40).map { "# Section \($0)\n" + String(repeating: "General store news and opening hours. ", count: 12) }
        return (filler + ["# Returns\nOpened items can be returned within 30 days with a receipt for a full refund."])
            .joined(separator: "\n")
    }

    @Test func aQueryFindsTheAnswerPastTheOldCutOff() {
        let full = longPage
        #expect(full.count > PageDigest.budget)
        let reading = PageDigest.digest(full, query: "return policy for opened items")
        #expect(reading.contains("within 30 days"))
        #expect(reading.contains("Reading focused on"))
        #expect(reading.count <= PageDigest.budget + 400)
    }

    @Test func withoutAQueryALongPageIsReadInPages() {
        let full = longPage
        let first = PageDigest.digest(full, query: nil)
        #expect(first.contains("start_from="))
        #expect(!first.contains("within 30 days"))
        let marker = first.range(of: "start_from=")!
        let next = Int(first[marker.upperBound...].prefix { $0.isNumber })!
        let later = PageDigest.digest(full, query: nil, startFrom: next)
        #expect(later.hasPrefix("(Continuing from character \(next).)"))
    }

    @Test func aQueryThatMatchesNothingFallsBackToTheTop() {
        let reading = PageDigest.digest(longPage, query: "zebra xylophone")
        #expect(reading.contains("Nothing on this page mentions"))
        #expect(reading.contains("# Section 1"))
    }

    @Test func sectionsBreakAtHeadings() {
        let sections = PageDigest.sections(of: "# One\nalpha\n# Two\nbeta")
        #expect(sections.map(\.text) == ["# One\nalpha", "# Two\nbeta"])
        #expect(sections[1].offset == 12)
    }

    // MARK: - Noticing a page that did not change

    @Test func theFingerprintMovesWhenTheTextChanges() {
        let before = page([target(1)], signature: "123/40")
        let same = page([target(1)], signature: "123/40")
        let after = page([target(1)], signature: "999/52")
        let url = "https://shop.test/cart"
        #expect(before.fingerprint(urlString: url) == same.fingerprint(urlString: url))
        #expect(before.fingerprint(urlString: url) != after.fingerprint(urlString: url))
    }

    @Test func aPageThatStopsChangingRaisesTheRead() {
        let read = DifficultyScout.read(.init(isFirstStep: false, observation: page([target(1)]), stagnantSteps: 2))
        #expect(read.difficulty != .routine)
        #expect(read.reasons.contains { $0.contains("has not changed") })
    }

    @Test func newControlsAreStarredInTheMap() {
        var menuItem = target(4, .button, "Sort by price")
        menuItem.isNew = true
        let observation = page([target(1), menuItem])
        #expect(menuItem.mapLine.hasPrefix("*[4]"))
        #expect(observation.mapText.contains("* marks controls that appeared"))
        #expect(!page([target(1)]).mapText.contains("* marks controls"))
    }

    @Test func adFramesAreSkipped() {
        #expect(PageScanner.isAdFrame(src: "https://tpc.googlesyndication.com/safeframe/1"))
        #expect(PageScanner.isAdFrame(src: "https://securepubads.g.doubleclick.net/x"))
        #expect(!PageScanner.isAdFrame(src: "https://www.youtube.com/embed/abc"))
        #expect(!PageScanner.isAdFrame(src: "not a url"))
    }

    // MARK: - New tools and fields

    @Test func everyMoveCarriesItsOwnVerdictAndAim() {
        let decision = AIService.decision(
            fromToolNamed: "tap_element",
            argumentsJSON: #"{"reasoning":"open filters","element":3,"previous_move":"Failed","next_goal":"open the filter panel"}"#
        )
        #expect(decision?.action.previousMove == "failed")
        #expect(decision?.action.nextGoal == "open the filter panel")
        let tools = AIService.tools()
        #expect(tools.allSatisfy { $0.function.parameters.properties["previous_move"] != nil })
    }

    @Test func extractTakesAQuestionAndAPlaceToContinueFrom() {
        let decision = AIService.decision(
            fromToolNamed: "extract",
            argumentsJSON: #"{"reasoning":"find it","query":"delivery times","start_from":9000}"#
        )
        #expect(decision?.action.query == "delivery times")
        #expect(decision?.action.startFrom == 9000)
        #expect(decision?.action.detailText.contains("delivery times") == true)
    }

    @Test func aSequenceParsesIntoItsMovesAndDropsWhatItMayNotDo() {
        let decision = AIService.decision(
            fromToolNamed: "do_sequence",
            argumentsJSON: #"{"reasoning":"tick then apply","moves":[{"move":"set_toggle","element":2,"on":true},{"move":"done"},{"move":"tap_element","element":9}]}"#
        )
        #expect(decision?.action.kind == .sequence)
        #expect(decision?.action.moves?.map(\.kind) == [.setToggle, .tapElement])
        #expect(decision?.action.detailText.contains("→") == true)
    }

    @Test func aSequenceOfOneIsJustThatMove() {
        let decision = AIService.decision(
            fromToolNamed: "do_sequence",
            argumentsJSON: #"{"reasoning":"just one","task":2,"moves":[{"move":"tap_element","element":5}]}"#
        )
        #expect(decision?.action.kind == .tapElement)
        #expect(decision?.action.element == 5)
        #expect(decision?.action.task == 2)
    }

    @Test func aSequenceHidingACommitmentIsEscalated() {
        let observation = page([target(1, .toggle, "In stock only"), target(2, .button, "Place order")])
        var tick = AgentAction(type: "set_toggle")
        tick.element = 1
        var order = AgentAction(type: "tap_element")
        order.element = 2
        var sequence = AgentAction(type: "do_sequence")
        sequence.moves = [tick, order]
        #expect(ModelRouter.isCommitting(sequence, in: observation))
        sequence.moves = [tick]
        #expect(!ModelRouter.isCommitting(sequence, in: observation))
    }

    @Test func handOverIsUsableOnlyWhenSwitchedOn() {
        #expect(AIService.tools().contains { $0.function.name == "hand_over" })
        #expect(AIService.availabilityLine(canHandOver: true).contains("every page move, hand_over."))
        #expect(AIService.availabilityLine().contains("hand_over."))
        #expect(!AIService.availabilityLine().contains("USABLE THIS TURN: every page move, hand_over"))
        #expect(AgentActionKind.handOver.isPageAction == false)
        let decision = AIService.decision(
            fromToolNamed: "hand_over",
            argumentsJSON: #"{"reasoning":"needs a sign-in","instruction":"Sign in, then tap Done"}"#
        )
        #expect(decision?.action.instruction == "Sign in, then tap Done")
    }

    @Test func theToolsForLookingAreOnOffer() {
        let names = Set(AIService.tools().map(\.function.name))
        #expect(names.isSuperset(of: ["list_options", "find_text", "do_sequence", "extract"]))
    }

    // MARK: - Natural hands

    @Test func tapsAndTypingUseTheFullNaturalSequence() {
        let tap = PageScanner.tapScript(id: 3, display: 3, descriptor: "", expectedName: "Go")
        #expect(tap.contains("__press(el, x, y)"))
        #expect(PageScanner.naturalPressFunction.contains("pointerType: 'touch'"))
        let type = PageScanner.typeScript(id: 4, display: 4, text: "hi", submit: true, descriptor: "", expectedName: "Search")
        #expect(type.contains("__typeNaturally(el, t)"))
        #expect(type.contains("__pressEnter(el)"))
        // Enter only submits when the page left the key alone.
        #expect(PageScanner.naturalTypingFunction.contains("if (unhandled && el.form)"))
    }

    // MARK: - Runs saved as scripts

    @Test func lookingIsNotAStepOfTheRoute() {
        let moves = [
            RecipeDistiller.Move(kind: .findText, result: "found 1 match"),
            RecipeDistiller.Move(kind: .tapElement, fingerprint: ElementFingerprint(name: "Next", kind: .button, neighbourhood: [], approxX: 0.5, approxY: 0.5), result: "tapped · page reacted (3 changes)"),
            RecipeDistiller.Move(kind: .extract, result: "read the page"),
        ]
        #expect(RecipeDistiller.keptIndices(from: moves) == [1])
    }

    private func typeMove(_ name: String, source: StepValueSource?) -> RecipeMove {
        RecipeMove(
            action: AgentActionKind.typeInto.rawValue,
            target: ElementFingerprint(name: name, kind: .field, neighbourhood: [], approxX: 0.5, approxY: 0.5),
            valueKind: "what you're looking for",
            valueSource: source
        )
    }

    @Test func onlyStepsThatAskGetABlank() {
        let moves = [
            typeMove("Search", source: nil),
            typeMove("Email", source: .identity(.email)),
            typeMove("Promo code", source: .fixed("SPRING")),
            typeMove("Postcode", source: .askAtLaunch),
        ]
        let blanks = RoutineBuilder.blanks(for: moves)
        #expect(blanks.map(\.moveIndex) == [0, 3])
    }

    @Test func anEditedScriptKeepsItsGoalInLineWithItsBlanks() {
        let original = Routine(
            host: "shop.test",
            title: "Find shoes",
            goalTemplate: "find ⟨what you're looking for⟩ on shop.test",
            moves: [typeMove("Search", source: nil)],
            blanks: RoutineBuilder.blanks(for: [typeMove("Search", source: nil)])
        )
        var edited = original
        edited.moves = [typeMove("Search", source: .fixed("running shoes"))]
        let rebuilt = RoutineBuilder.rebuilt(edited)
        #expect(rebuilt.blanks.isEmpty)
        #expect(!rebuilt.goalTemplate.contains("⟨"))
        #expect(rebuilt.id == original.id)
    }

    @Test func aStepSpeaksInYourWordsWhenYouGiveThem() {
        var move = typeMove("Email", source: .identity(.email))
        #expect(move.plainLine.contains("your email"))
        move.note = "Enter my work email"
        #expect(move.plainLine == "Enter my work email")
        #expect(move.generatedLine.contains("your email"))
    }

    @Test func aScriptStepSurvivesTheCodeView() throws {
        var move = typeMove("Email", source: .identity(.email))
        move.note = "Enter my email"
        let code = ScriptStepEditor.encode(move)
        let decoded = try JSONDecoder().decode(RecipeMove.self, from: Data(code.utf8))
        #expect(decoded == move)
        // A step stores which identity detail to use, never the detail itself.
        #expect(code.contains("email"))
        #expect(!code.contains("@"))
    }

    @Test func routesSavedBeforeScriptsStillDecode() throws {
        let legacy = #"{"id":"6F1C1D5E-8C7A-4C39-9A0B-1B2C3D4E5F60","action":"tap_element","isCommitting":false}"#
        let move = try JSONDecoder().decode(RecipeMove.self, from: Data(legacy.utf8))
        #expect(move.note == nil)
        #expect(move.valueSource == nil)
    }
}
