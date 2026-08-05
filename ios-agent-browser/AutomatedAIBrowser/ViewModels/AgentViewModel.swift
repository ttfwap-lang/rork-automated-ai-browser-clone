import UIKit
import WebKit
import Observation

/// Drives the plan-see-decide-act-verify loop: write the mission checklist,
/// snapshot the page, ask the AI, execute the action, and — before any run can
/// be called complete — have an independent check confirm the claim.
@Observable
final class AgentViewModel {
    let webProxy = WebViewProxy()

    var goalText = ""
    var mode: AgentMode
    var isFeedPresented = false

    private(set) var phase: AgentPhase = .idle
    private(set) var steps: [AgentStep] = []
    private(set) var activeGoal: String?
    private(set) var currentStepIndex = 0
    private(set) var maxStepsThisRun = 12
    /// The live mission checklist; nil when planning is switched off.
    private(set) var plan: MissionPlan?
    /// Honest note shown on the plan card when planning could not run.
    private(set) var planNote: String?
    var outcomeBanner: OutcomeBanner?

    private let settings: AppSettings
    private let history: HistoryStore
    /// This iPhone's own free model, and the vault of routes that have worked.
    private let onDevice: OnDeviceModel
    private let vault: RecipeVault
    /// What each site has taught the agent by going wrong, and the saved one-tap
    /// replays built out of runs that worked.
    private let lessonBook: LessonBook
    private let routines: RoutineStore
    private let ai = AIService()

    private var runTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var runStartDate = Date()
    private var didPersistRun = false
    /// The most recent page scan — used to resolve element targets at act time.
    private var lastObservation: PageObservation?
    /// Whole-page overview captured by page_overview, delivered with the NEXT decision.
    private var pendingOverview: (image: UIImage, note: String)?

    /// The independent check's objection, handed to the agent's next briefing.
    private var pendingObjection: String?
    private var rejectionCount = 0
    private var unclearCount = 0
    /// A rejection grants two extra steps, once per run.
    private var didGrantExtraSteps = false
    private var taskStuckCount = 0
    private var lastCurrentTaskNumber: Int?
    private var finalVerdict: VerificationVerdict?

    /// Checkpoints captured before branching or risky moves.
    private(set) var bookmarks: [PageBookmark] = []
    /// Every paid AI call in this run, split by which model answered — step
    /// decisions, the opening plan, and each independent check.
    private(set) var fastCallCount = 0
    private(set) var preciseCallCount = 0
    private(set) var planningCallCount = 0
    private(set) var checkCallCount = 0
    /// Decisions made on this iPhone, which cost nothing. Deliberately kept out
    /// of the paid totals.
    private(set) var freeCallCount = 0
    /// The one paid call a memory write can cost on a phone that cannot run the
    /// free tier.
    private(set) var memoryCallCount = 0
    private(set) var rewindCount = 0
    private(set) var weighedMoveCount = 0
    private var bookmarkCounter = 0
    private var currentBookmarkNumber: Int?
    private var checkpointsUnavailable = false
    /// True when the last step failed — the next attempt is never on the cheap model.
    private var mustEscalate = false
    private var runnerUp: MoveCandidate?
    private var pendingRunnerUpNote: String?
    private var pendingDeadEndNote: String?
    private var pendingRescueNote: String?
    private var didOfferRescue = false
    private var failedSignatures: Set<String> = []
    /// What the page did last, shown live on the thinking panel.
    private(set) var lastResultLine: String?
    private var lastTaskNumberForBookmark: Int?
    private var userRewindTarget: PageBookmark?

    /// The remembered route recalled for this run, when one matched well enough.
    private var recalledMatch: RecipeMatch?
    /// That route as the planner and the agent read it.
    private var memoryNote: String?
    /// The free restatement of the goal, when this iPhone could write one.
    private var refinement: GoalRefiner.Refinement?
    private(set) var replayedMoveCount = 0
    /// nil when no head start ran; false when it stopped early.
    private var headStartHeld: Bool?
    /// The head start switches itself off for the rest of a run at the first
    /// mismatch, rather than optimistically trying again.
    private var headStartOver = false
    /// Every move that ran, in the form the memory writer needs. By construction
    /// this never holds anything the user typed.
    private var executedMoves: [RecipeDistiller.Move] = []

    /// The saved one-tap replay this run was launched from, when it was one.
    private var activeRoutine: Routine?
    private var routineValues: [UUID: String] = [:]
    private var pendingRoutine: (routine: Routine, values: [UUID: String])?
    /// True when a replay ran every one of its moves and every one of them held.
    private var routineFinishedCleanly = false
    /// Saved steps that had to be repaired because the site had moved them.
    private(set) var healedMoveCount = 0
    /// Paid calls spent working out where a moved control had gone.
    private(set) var repairCallCount = 0
    /// This site's cautions, as the planner and the agent read them.
    private var cautionNote: String?
    /// Which cautions were handed over, so the ones that turn out not to apply
    /// can be doubted afterwards.
    private var handedOverCautions: Set<UUID> = []
    private var cautionsUsedCount = 0
    /// The site those cautions came from.
    private var cautionHost: String?
    /// Honest handover notes from a replay that stopped matching the site.
    private var mismatchNotes: [String] = []
    private var overlaySeenThisRun = false
    private var hitStepLimit = false
    private var lastFailReason: String?
    /// What was typed, keyed by executed-move index. Held for this run only, used
    /// to blank out a saved replay's goal sentence, and never written to disk.
    private var typedValues: [Int: String] = [:]
    /// The goal of the run that just finished, so it can be saved as a replay.
    private(set) var lastFinishedGoal: String?
    /// How that run ended — the only evidence available when the independent
    /// check is switched off.
    private(set) var lastFinishedOutcome: RunOutcome?

    /// Your objection to a move, written the way the agent has to read it. Kept
    /// for the whole run so it can be re-handed rather than quietly forgotten.
    private var mistakeRule: String?
    /// The one-shot note for the next briefing.
    private var pendingMistakeNote: String?
    /// True while the agent owes you a rewritten route before it may act again.
    private(set) var awaitingReplan = false
    /// True when there was no plan rewrite left to demand, so your words stand as
    /// a hard rule for every remaining step instead of being silently dropped.
    private(set) var mistakeRuleOnly = false
    /// How many times you stepped in.
    private(set) var mistakeCount = 0
    /// Moves you flagged. Barred for the rest of the run, by signature.
    private var barredSignatures: Set<String> = []
    /// One refusal per objection: a model that will not rewrite its route must
    /// not be able to spin the run refusing forever.
    private var replanRefusals = 0
    /// Set when you flagged the very move the agent was waiting on approval for.
    private var didFlagDuringApproval = false

    /// How many steps on the same task before the briefing suggests re-planning.
    private static let stuckNudgeThreshold = 4
    /// Rewinds allowed per mission.
    private static let maxRewinds = 3


    init(
        settings: AppSettings,
        history: HistoryStore,
        onDevice: OnDeviceModel,
        vault: RecipeVault,
        lessons: LessonBook,
        routines: RoutineStore
    ) {
        self.settings = settings
        self.history = history
        self.onDevice = onDevice
        self.vault = vault
        self.lessonBook = lessons
        self.routines = routines
        self.mode = settings.defaultMode
    }

    /// True when the free tier is switched on AND this iPhone can actually run it.
    private var isFreeTierReady: Bool {
        settings.onDeviceFirst && onDevice.isReady
    }

    var isRunning: Bool { runTask != nil }

    var pendingStep: AgentStep? {
        phase == .awaitingApproval ? steps.last : nil
    }

    var isScanningVisual: Bool {
        phase.isBusyThinking
    }

    func loadHomepageIfNeeded() {
        guard webProxy.webView.url == nil else { return }
        webProxy.load(settings.homepage)
    }

    // MARK: - Run control

    func startRun() {
        let goal = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, runTask == nil else { return }
        steps = []
        outcomeBanner = nil
        lastObservation = nil
        pendingOverview = nil
        plan = nil
        planNote = nil
        pendingObjection = nil
        rejectionCount = 0
        unclearCount = 0
        didGrantExtraSteps = false
        taskStuckCount = 0
        lastCurrentTaskNumber = nil
        finalVerdict = nil
        bookmarks = []
        bookmarkCounter = 0
        currentBookmarkNumber = nil
        checkpointsUnavailable = false
        fastCallCount = 0
        preciseCallCount = 0
        planningCallCount = 0
        checkCallCount = 0
        rewindCount = 0
        weighedMoveCount = 0
        mustEscalate = false
        runnerUp = nil
        pendingRunnerUpNote = nil
        pendingDeadEndNote = nil
        pendingRescueNote = nil
        didOfferRescue = false
        failedSignatures = []
        lastResultLine = nil
        lastTaskNumberForBookmark = nil
        userRewindTarget = nil
        freeCallCount = 0
        memoryCallCount = 0
        recalledMatch = nil
        memoryNote = nil
        refinement = nil
        replayedMoveCount = 0
        headStartHeld = nil
        headStartOver = false
        executedMoves = []
        typedValues = [:]
        activeRoutine = nil
        routineValues = [:]
        routineFinishedCleanly = false
        healedMoveCount = 0
        repairCallCount = 0
        cautionNote = nil
        cautionHost = nil
        handedOverCautions = []
        cautionsUsedCount = 0
        mismatchNotes = []
        overlaySeenThisRun = false
        hitStepLimit = false
        lastFailReason = nil
        lastFinishedGoal = nil
        lastFinishedOutcome = nil
        mistakeRule = nil
        pendingMistakeNote = nil
        awaitingReplan = false
        mistakeRuleOnly = false
        mistakeCount = 0
        barredSignatures = []
        replanRefusals = 0
        didFlagDuringApproval = false
        activeGoal = goal
        currentStepIndex = 0
        maxStepsThisRun = settings.maxSteps
        if let pending = pendingRoutine {
            pendingRoutine = nil
            activeRoutine = pending.routine
            routineValues = pending.values
            // A saved route can be longer than the budget a typed goal gets, and
            // cutting a replay off half way through is worse than useless.
            maxStepsThisRun = max(settings.maxSteps, pending.routine.moves.count + 4)
        }
        runStartDate = Date()
        didPersistRun = false
        isFeedPresented = true
        Haptics.medium()
        // Warm the free model so its first answer is instant rather than sluggish.
        if settings.onDeviceFirst {
            onDevice.warmUp()
        }
        runTask = Task { [weak self] in
            await self?.runLoop(goal: goal)
        }
    }

    func stopRun() {
        guard runTask != nil else { return }
        Haptics.warning()
        runTask?.cancel()
        resumeApproval(false)
    }

    func approvePendingAction() {
        Haptics.medium()
        resumeApproval(true)
    }

    func rejectPendingAction() {
        Haptics.warning()
        resumeApproval(false)
    }

    func dismissBanner() {
        outcomeBanner = nil
    }

    // MARK: - The loop

    private func runLoop(goal: String) async {
        var extracted: String?

        // Free, offline, and it makes the paid planning call sharper.
        await refineGoal(goal)
        // Silent recall: no card, no prompt, no extra tap.
        recallMemory(goal: goal)
        recallLessons(goal: goal)

        await preparePlan(goal: goal)
        guard !Task.isCancelled else {
            finishRun(.stopped, "Stopped by you.", goal: goal)
            return
        }

        // Replaying a proven opening consumes steps, but not decisions. A saved
        // one-tap replay takes the same slot and replays the whole route.
        var index = activeRoutine == nil ? await runHeadStart() : await runSavedReplay()
        guard !Task.isCancelled else {
            finishRun(.stopped, "Stopped by you.", goal: goal)
            return
        }

        // A replay that held end to end has already done the job, so the app
        // claims it rather than paying for a decision that would only say "done".
        if routineFinishedCleanly {
            switch await finishReplayedRun(goal: goal) {
            case .finished: return
            case .backToWork: break
            }
        }

        while index < maxStepsThisRun {
            index += 1
            currentStepIndex = index

            guard !Task.isCancelled else {
                finishRun(.stopped, "Stopped by you.", goal: goal)
                return
            }

            // A rewind you asked for while flagging a mistake happens before
            // anything else, so the agent rethinks from where you sent it rather
            // than from where it went wrong.
            if let target = userRewindTarget, !steps.isEmpty {
                userRewindTarget = nil
                phase = .acting
                await rewind(to: target, reason: "you sent the agent back here after flagging a mistake", counted: false)
            }

            phase = .observing
            await webProxy.waitForQuiet(maxWait: 8)
            guard !Task.isCancelled else {
                finishRun(.stopped, "Stopped by you.", goal: goal)
                return
            }
            let observation = await webProxy.observe()
            lastObservation = observation
            if observation?.overlayLikely == true { overlaySeenThisRun = true }
            guard let rawSnapshot = await webProxy.snapshot() else {
                finishRun(.failed, "Couldn't capture the page. Try again once a page is loaded.", goal: goal)
                return
            }
            let snapshotImage = observation.map { SnapshotAnnotator.annotate(rawSnapshot, with: $0) } ?? rawSnapshot

            // Consume the overview captured last step (if any) — it rides along
            // with THIS decision and is recorded on THIS step for Agent Vision.
            let overview = pendingOverview
            pendingOverview = nil
            // The check's objection is handed over exactly once.
            let objection = pendingObjection
            pendingObjection = nil
            // Yours is handed over once as a demand to rewrite the route, and then
            // every remaining step once it has become a standing rule.
            let mistake = pendingMistakeNote ?? (mistakeRuleOnly ? mistakeRule : nil)
            pendingMistakeNote = nil
            let deadEnds = pendingDeadEndNote
            pendingDeadEndNote = nil
            let rescue = pendingRescueNote
            pendingRescueNote = nil
            let runnerUpNote = pendingRunnerUpNote
            pendingRunnerUpNote = nil

            // The difficulty read costs nothing and decides both which model
            // answers this step and whether alternatives are drafted.
            let read = DifficultyScout.read(DifficultyScout.Signals(
                isFirstStep: index == 1,
                observation: observation,
                lastResult: lastResultLine,
                isRepeating: isRepeatingRecently(),
                taskStuckCount: taskStuckCount,
                hasObjection: objection != nil || mistake != nil
            ))
            let routingInputs = ModelRouter.Inputs(
                strategy: settings.modelStrategy,
                preferred: settings.model,
                read: read,
                isFirstStep: index == 1,
                mustEscalate: mustEscalate,
                onDeviceReady: isFreeTierReady
            )
            var route = ModelRouter.route(routingInputs)
            let allowShortlist = settings.weighAlternatives && read.difficulty == .hard

            phase = .thinking
            var turn: AgentTurn?
            // Set when the free tier was asked and the cloud had to take over.
            var handoffNote: String?

            // The free tier gets first refusal, and nothing it says is trusted on
            // faith: every answer is checked against the live page before it runs.
            if route.choice == .onDevice {
                switch await freeDecision(goal: goal, observation: observation) {
                case .decided(let action, let reasoning):
                    freeCallCount += 1
                    turn = .move(AgentDecision(reasoning: reasoning, action: action))
                case .handedOver(let why):
                    handoffNote = why
                    route = ModelRouter.cloudRoute(routingInputs)
                }
            }

            if turn == nil {
                do {
                    turn = try await ai.decide(AIService.DecisionRequest(
                    goal: goal,
                    urlString: webProxy.webView.url?.absoluteString ?? "",
                    pageTitle: webProxy.webView.title ?? "",
                    stepIndex: index,
                    maxSteps: maxStepsThisRun,
                    historyLines: historyLines(),
                    extractedText: extracted,
                    pageMap: observation?.mapText,
                    imageBase64: Self.jpegBase64(from: snapshotImage),
                    overviewImageBase64: overview.map { Self.jpegBase64(from: $0.image, maxBytes: 1_500_000, startQuality: 0.55) },
                    overviewNote: overview?.note,
                    planBriefing: plan?.briefingText,
                    objection: objection,
                    nudge: stuckNudge(),
                    difficultyNote: read.briefingNote,
                    bookmarksNote: bookmarksNote(),
                    runnerUpNote: runnerUpNote,
                    deadEndNote: deadEnds,
                    rescueNote: rescue,
                    memoryNote: memoryNote,
                    cautionNote: cautionNote,
                    mistakeNote: mistake,
                    allowShortlist: allowShortlist,
                    hasBookmarks: settings.bookmarksEnabled && !bookmarks.isEmpty && !checkpointsUnavailable,
                    modelID: route.choice.modelID
                    ))
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        finishRun(.stopped, "Stopped by you.", goal: goal)
                    } else {
                        finishRun(.failed, error.localizedDescription, goal: goal)
                    }
                    return
                }
            }

            guard let resolvedTurn = turn else {
                finishRun(.failed, "No decision came back for this step. Please run it again.", goal: goal)
                return
            }
            extracted = nil

            var resolvedAction: AgentAction
            var reasoningText: String
            var weighed: [MoveCandidate] = []

            switch resolvedTurn {
            case .move(let decision):
                resolvedAction = decision.action
                reasoningText = decision.reasoning ?? ""
            case .shortlist(let reasoning, let drafted):
                weighed = CandidateScorer.score(drafted, in: CandidateScorer.Context(
                    observation: observation,
                    failedSignatures: failedSignatures,
                    currentTask: plan?.currentTask
                ))
                guard let winner = weighed.first else {
                    finishRun(.failed, "The AI weighed no usable moves. Please run it again.", goal: goal)
                    return
                }
                weighedMoveCount += weighed.count
                resolvedAction = winner.action
                var pieces: [String] = []
                if let reasoning, !reasoning.isEmpty { pieces.append(reasoning) }
                if !winner.rationale.isEmpty { pieces.append("picked: \(winner.rationale)") }
                reasoningText = pieces.joined(separator: " — ")
                runnerUp = weighed.dropFirst().first
            }

            var fingerprint: ElementFingerprint?
            if let elementID = resolvedAction.element, let observation,
               let match = observation.element(withID: elementID) {
                resolvedAction.elementName = match.shortDescriptor
                fingerprint = ElementFingerprint.make(for: match, in: observation)
            }
            countCall(on: route.choice)

            var step = AgentStep(
                index: index,
                action: resolvedAction,
                reasoning: reasoningText,
                result: nil,
                status: .proposed,
                snapshot: snapshotImage,
                pageMap: observation?.mapText
            )
            step.overviewImage = overview?.image
            step.overviewNote = overview?.note
            step.taskNumber = resolvedAction.task
            step.taskTitle = resolvedAction.task.flatMap { plan?.task(numbered: $0)?.title }
            step.modelChoice = route.choice
            step.routingReason = handoffNote.map { "\(route.reason) — your iPhone's model handed it over: \($0)" } ?? route.reason
            step.targetFingerprint = fingerprint
            step.difficulty = read.difficulty
            step.difficultyReason = read.summary
            step.candidates = weighed
            steps.append(step)
            trimStoredImages()
            Haptics.light()

            switch resolvedAction.kind {
            case .done:
                switch await handleClaimedDone(resolvedAction, goal: goal) {
                case .finished: return
                case .backToWork: continue
                }
            case .fail:
                let reason = resolvedAction.reason ?? "The agent couldn't complete the goal."
                lastFailReason = reason
                if let target = rescueTarget(for: reason), index < maxStepsThisRun {
                    didOfferRescue = true
                    steps[steps.count - 1].status = .executed
                    steps[steps.count - 1].result = "not so fast — checkpoint \(target.number) still has an untried route"
                    pendingRescueNote = "YOU JUST GAVE UP, AND IT IS BEING PUSHED BACK — ONCE. Checkpoint \(target.number) (\(target.label)) still has a route you have not tried. From there you already tried: \(target.triedLine). Either rewind to it and try something genuinely different, or call fail again and the run ends."
                    Haptics.warning()
                    continue
                }
                steps[steps.count - 1].status = .terminal
                finishRun(
                    .failed,
                    didOfferRescue ? "\(reason)\n\nA rescue was offered and declined." : reason,
                    goal: goal
                )
                return
            default:
                break
            }

            // Your objection outranks the model. A move you flagged never runs
            // again, and while a rewrite is outstanding the page stays off limits
            // until the route actually changes.
            if let refusal = refusalReason(for: resolvedAction) {
                steps[steps.count - 1].status = .rejected
                steps[steps.count - 1].result = refusal
                Haptics.warning()
                continue
            }

            if mode == .supervised {
                phase = .awaitingApproval
                Haptics.warning()
                let approved = await waitForApproval()
                guard !Task.isCancelled else {
                    finishRun(.stopped, "Stopped by you.", goal: goal)
                    return
                }
                if !approved {
                    // Flagging already marked the move rejected and wrote your
                    // entry into the log, so the run carries on from there.
                    if didFlagDuringApproval {
                        didFlagDuringApproval = false
                        continue
                    }
                    if let target = userRewindTarget {
                        userRewindTarget = nil
                        steps[steps.count - 1].status = .rejected
                        steps[steps.count - 1].result = "you sent the agent back to checkpoint \(target.number)"
                        phase = .acting
                        await rewind(to: target, reason: "you sent the agent back here", counted: false)
                        continue
                    }
                    steps[steps.count - 1].status = .rejected
                    steps[steps.count - 1].result = "rejected by you"
                    finishRun(.stopped, "Run ended — you rejected the proposed action.", goal: goal)
                    return
                }
            }

            phase = .acting

            if resolvedAction.kind == .revisePlan {
                applyRevision(resolvedAction)
                continue
            }

            if resolvedAction.kind == .rewind {
                await performRewind(resolvedAction)
                continue
            }

            if shouldCapture(before: resolvedAction) {
                await captureBookmark(snapshot: rawSnapshot)
            }

            let execution = await execute(resolvedAction)
            var resultText = execution.result
            if observation == nil {
                resultText += " · page scan unavailable (vision-only step)"
            }
            steps[steps.count - 1].result = resultText
            steps[steps.count - 1].status = .executed
            extracted = execution.extracted
            lastResultLine = resultText
            recordExecutedMove(resolvedAction, fingerprint: fingerprint, result: resultText)
            applyChecklist(from: resolvedAction)
            noteOutcome(action: resolvedAction, result: resultText)
        }

        hitStepLimit = true
        finishRun(.failed, "Reached the \(maxStepsThisRun)-step limit before finishing. Raise the limit in Settings or narrow the goal.", goal: goal)
    }

    // MARK: - Stage A: the mission plan

    /// Writes the opening checklist. Planning can never block or break a run:
    /// any failure falls back to a single task and continues.
    private func preparePlan(goal: String) async {
        guard settings.planning.isEnabled else {
            plan = nil
            planNote = nil
            return
        }

        phase = .planning
        await webProxy.waitForQuiet(maxWait: 6)
        guard !Task.isCancelled else { return }

        let planningModel: ModelChoice = settings.planning == .strong ? .precise : settings.model
        planningCallCount += 1
        countCall(on: planningModel)
        do {
            let written = try await ai.plan(AIService.PlanRequest(
                goal: goal,
                urlString: webProxy.webView.url?.absoluteString ?? "",
                pageTitle: webProxy.webView.title ?? "",
                modelID: planningModel.modelID,
                refinement: refinement,
                memoryNote: memoryNote,
                cautionNote: cautionNote
            ))
            plan = written
            planNote = nil
            lastCurrentTaskNumber = written.currentTask?.number
            Haptics.success()
        } catch {
            guard !(Task.isCancelled || error is CancellationError) else { return }
            let fallback = MissionPlan.fallback(goal: goal)
            plan = fallback
            planNote = "Planning was unavailable (\(error.localizedDescription)) — running as a single task."
            lastCurrentTaskNumber = fallback.currentTask?.number
        }
    }

    /// Applies what the agent reported this step: which task it served and which
    /// tasks it can see are finished. Free — it rides on the decision call.
    private func applyChecklist(from action: AgentAction) {
        guard var current = plan else { return }
        let ticked = current.apply(claimedCurrent: action.task, completed: action.completedTasks)
        plan = current
        if ticked > 0 {
            Haptics.success()
        }

        let currentNumber = current.currentTask?.number
        if currentNumber == lastCurrentTaskNumber {
            taskStuckCount += 1
        } else {
            lastCurrentTaskNumber = currentNumber
            taskStuckCount = currentNumber == nil ? 0 : 1
        }
    }

    /// Rewrites the rest of the plan. Consumes the turn instead of a page action,
    /// so re-planning never costs an extra call.
    private func applyRevision(_ action: AgentAction) {
        let last = steps.count - 1
        guard last >= 0 else { return }
        applyChecklist(from: action)
        steps[last].status = .executed

        // The turn was spent on planning, which is exactly what a forced rewrite
        // demanded — so the gate lifts here whatever the rewrite itself achieves.
        // Leaving it up would let one uncooperative answer stall the whole run.
        let wasForced = awaitingReplan
        awaitingReplan = false

        guard var current = plan else {
            steps[last].result = "there is no mission plan to revise (planning is off) — carry on with the goal as written"
            holdMistakeAsRule(wasForced)
            return
        }
        guard current.canRevise else {
            steps[last].result = "plan rewrite refused — this mission's \(MissionPlan.maxRevisions)-rewrite limit is used up; work the plan you have or report honestly"
            holdMistakeAsRule(wasForced)
            return
        }
        let drafts = action.tasks ?? []
        guard !drafts.isEmpty else {
            steps[last].result = "revise_plan arrived with no tasks — the plan is unchanged"
            return
        }

        current.revise(with: drafts)
        plan = current
        planNote = nil
        replanRefusals = 0
        taskStuckCount = 0
        lastCurrentTaskNumber = current.currentTask?.number
        let plural = drafts.count == 1 ? "" : "s"
        steps[last].result = "plan revised — \(drafts.count) task\(plural) ahead, \(current.doneCount) already done (rewrite \(current.revisions) of \(MissionPlan.maxRevisions))"
        Haptics.success()
    }

    /// When a rewrite you forced could not happen at all, your objection is kept
    /// as a hard rule for every remaining step rather than quietly dropped.
    private func holdMistakeAsRule(_ wasForced: Bool) {
        guard wasForced, mistakeRule != nil else { return }
        mistakeRuleOnly = true
    }

    /// Gentle, free nudge when the same task has been current for a while.
    private func stuckNudge() -> String? {
        guard let plan, plan.canRevise, let current = plan.currentTask else { return nil }
        guard taskStuckCount >= Self.stuckNudgeThreshold else { return nil }
        return "NUDGE: task \(current.number) has been your current task for \(taskStuckCount) steps without finishing. If the plan no longer fits this site, call revise_plan with a route that does."
    }

    // MARK: - Stage E: the independent check

    private enum ClaimOutcome {
        case finished
        case backToWork
    }

    /// Runs the independent check on a claimed success. Confirmed ends the run
    /// green; rejected sends the agent back with the objection; a claim the check
    /// cannot stand behind never ends green.
    private func handleClaimedDone(_ action: AgentAction, goal: String) async -> ClaimOutcome {
        let claimed = (action.summary ?? "").trimmed.isEmpty ? "Goal completed." : action.summary!.trimmed
        let last = steps.count - 1
        steps[last].status = .terminal
        applyChecklist(from: action)

        guard settings.verifyBeforeDone else {
            finishRun(.completed, claimed, goal: goal)
            return .finished
        }

        phase = .verifying
        await webProxy.waitForQuiet(maxWait: 6)
        guard !Task.isCancelled else {
            finishRun(.stopped, "Stopped by you.", goal: goal)
            return .finished
        }

        let fresh = await webProxy.snapshot()
        let pageText = await webProxy.extractText()
        let checkModel = verificationModel()
        checkCallCount += 1
        countCall(on: checkModel)

        let result: VerificationResult
        do {
            result = try await ai.verify(AIService.VerifyRequest(
                goal: goal,
                successStatement: plan?.successStatement ?? goal,
                answerShape: plan?.answerShape,
                claimedResult: claimed,
                actionTrail: actionTrail(),
                urlString: webProxy.webView.url?.absoluteString ?? "",
                pageTitle: webProxy.webView.title ?? "",
                pageText: pageText,
                imageBase64: fresh.map { Self.jpegBase64(from: $0) } ?? "",
                modelID: checkModel.modelID
            ))
        } catch {
            if Task.isCancelled || error is CancellationError {
                finishRun(.stopped, "Stopped by you.", goal: goal)
            } else {
                appendCheckStep(result: nil, snapshot: fresh, note: "the independent check couldn't run — \(error.localizedDescription)")
                finishRun(
                    .unconfirmed,
                    "\(claimed)\n\nThe independent check couldn't run (\(error.localizedDescription)), so this claim is unconfirmed.",
                    goal: goal
                )
            }
            return .finished
        }

        appendCheckStep(result: result, snapshot: fresh, note: nil)
        finalVerdict = result.verdict

        switch result.verdict {
        case .confirmed:
            var message = result.correctedAnswer ?? claimed
            if let corrected = result.correctedAnswer, corrected != claimed {
                message += "\n\n(The check corrected the agent's wording to match the page.)"
            }
            message += "\n\nVerified — \(result.evidence)"
            // The check is the gate: only a confirmed success teaches the agent
            // anything, so a false "done" can never become a bad habit.
            if let match = recalledMatch {
                vault.recordHelped(match.recipe.id)
            }
            await rememberRoute(goal: goal, evidence: result.evidence)
            finishRun(.completed, message, goal: goal)
            return .finished

        case .rejected, .unclear:
            let isUnclear = result.verdict == .unclear
            if isUnclear {
                unclearCount += 1
            } else {
                rejectionCount += 1
            }

            let outOfPatience = rejectionCount >= 2 || unclearCount >= 2
            if outOfPatience {
                let headline = isUnclear
                    ? "The independent check could not confirm this claim from what was on screen."
                    : "The independent check rejected this claim twice."
                finishRun(
                    .unconfirmed,
                    "\(claimed)\n\n\(headline)\n\n\(result.pushback)",
                    goal: goal
                )
                return .finished
            }

            steps[last].status = .rejected
            steps[last].result = "the independent check \(isUnclear ? "could not confirm" : "rejected") this claim — back to work"
            plan?.untickLatest()
            pendingObjection = result.pushback
            mustEscalate = true
            if !didGrantExtraSteps {
                didGrantExtraSteps = true
                maxStepsThisRun += 2
            }
            Haptics.warning()
            return .backToWork
        }
    }

    /// The check runs on the strong model, or on the model the steps are NOT
    /// using when cross-checking is on, so reviewer and doer don't share a blind spot.
    private func verificationModel() -> ModelChoice {
        guard settings.crossCheckWithOtherModel else { return .precise }
        return settings.model == .precise ? .fast : .precise
    }

    /// Adds the independent check to the log as its own auditable entry, holding
    /// the fresh screenshot the check actually looked at.
    private func appendCheckStep(result: VerificationResult?, snapshot: UIImage?, note: String?) {
        var action = AgentAction(type: AgentActionKind.verify.rawValue)
        action.summary = result?.verdict.label ?? "COULD NOT RUN"

        var step = AgentStep(
            index: 0,
            action: action,
            reasoning: result?.evidence ?? (note ?? ""),
            result: nil,
            status: result?.verdict == .rejected ? .rejected : .terminal,
            snapshot: snapshot,
            pageMap: nil
        )
        step.verification = result
        if let result {
            var parts: [String] = []
            if let objection = result.objection, !objection.isEmpty {
                parts.append(objection)
            }
            if let corrected = result.correctedAnswer, !corrected.isEmpty {
                parts.append("corrected answer: \(corrected)")
            }
            if let by = result.checkedBy, !by.isEmpty {
                parts.append("checked by \(by)")
            }
            step.result = parts.isEmpty ? nil : parts.joined(separator: " · ")
        } else {
            step.result = note
        }
        steps.append(step)
        trimStoredImages()
    }

    // MARK: - Free brainpower: this iPhone's own model

    private enum FreeAttempt {
        case decided(AgentAction, String)
        case handedOver(String)
    }

    /// Offers a routine step to this iPhone's own model, then checks the answer
    /// against the live page before it is allowed anywhere near the browser. Any
    /// hesitation, ramble, refusal or rejected target hands the step to the cloud.
    private func freeDecision(goal: String, observation: PageObservation?) async -> FreeAttempt {
        guard let observation else {
            return .handedOver("the page scan was unavailable")
        }
        let answer = await onDevice.ask(
            instructions: OnDeviceDecider.instructions,
            prompt: OnDeviceDecider.prompt(
                goal: refinement?.missionLine ?? goal,
                currentTask: plan?.currentTask?.title,
                pageMap: observation.mapText,
                lastResult: lastResultLine
            )
        )
        guard let raw = answer.text else {
            return .handedOver(answer.handoffNote ?? "your iPhone's model couldn't answer")
        }
        guard let draft = OnDeviceDecider.parse(raw) else {
            return .handedOver("your iPhone's model passed on this one")
        }
        switch OnDeviceGate.review(draft.action, against: observation) {
        case .allowed(let action):
            return .decided(action, draft.reasoning)
        case .rejected(let why):
            return .handedOver(why)
        }
    }

    /// Restates the goal as one crisp mission line before the paid planning call.
    /// Free, and never allowed to replace the goal itself — it rides alongside it,
    /// so a bad rewrite cannot quietly change what was asked for.
    private func refineGoal(_ goal: String) async {
        guard isFreeTierReady else { return }
        let answer = await onDevice.ask(
            instructions: GoalRefiner.instructions,
            prompt: GoalRefiner.prompt(goal: goal)
        )
        guard let raw = answer.text,
              let parsed = GoalRefiner.parse(raw, original: goal)
        else { return }
        freeCallCount += 1
        refinement = parsed
    }

    // MARK: - Memory: recall, replay, and writing it down

    /// Matches the vault against this goal by site AND by intent, then folds the
    /// winner into the briefing. A weak or ambiguous match is not used at all.
    /// The user sees nothing — it just gets better at the sites they use.
    private func recallMemory(goal: String) {
        guard settings.memoryEnabled else { return }
        guard let match = RecipeMatcher.best(
            for: refinement?.missionLine ?? goal,
            urlString: webProxy.webView.url?.absoluteString ?? "",
            in: vault.recipes
        ) else { return }
        recalledMatch = match
        memoryNote = match.recipe.briefingText
        vault.recordUse(match.recipe.id)
    }

    /// Replays the opening moves of a proven route without paying for a decision
    /// on each one. Every replayed move consumes a step from the budget exactly
    /// like a normal one; what it does not consume is a decision.
    private func runHeadStart() async -> Int {
        guard settings.memoryEnabled, settings.headStartEnabled else { return 0 }
        guard let match = recalledMatch, let replay = HeadStart.plan(from: match.recipe) else { return 0 }
        guard !Task.isCancelled else { return 0 }

        var summary = AgentAction(type: AgentActionKind.headStart.rawValue)
        summary.summary = replay.proposalText
        var entry = AgentStep(
            index: 0,
            action: summary,
            reasoning: "\(match.reason) — its opening is \(replay.summaryText)",
            result: nil,
            status: .proposed,
            snapshot: nil,
            pageMap: nil
        )
        entry.isReplayed = true
        steps.append(entry)
        let entryIndex = steps.count - 1
        Haptics.light()

        // In Supervised mode the whole head start is one thing to approve.
        if mode == .supervised {
            phase = .awaitingApproval
            Haptics.warning()
            let approved = await waitForApproval()
            if Task.isCancelled || !approved {
                steps[entryIndex].status = .rejected
                steps[entryIndex].result = "you skipped the head start — working from a fresh look instead"
                headStartOver = true
                return 0
            }
        }
        steps[entryIndex].status = .executed

        var used = 0
        for (offset, move) in replay.moves.enumerated() {
            guard !Task.isCancelled, !headStartOver, used < maxStepsThisRun else { break }

            phase = .observing
            await webProxy.waitForQuiet(maxWait: 6)
            let observation = await webProxy.observe()
            lastObservation = observation
            let rawSnapshot = await webProxy.snapshot()

            switch HeadStart.resolve(move, in: observation) {
            case .mismatch(let why):
                stopHeadStart(at: entryIndex, move: offset + 1, reason: why, recipeID: match.recipe.id, replayed: used)
                return used

            case .matched(let action):
                used += 1
                currentStepIndex = used
                let annotated: UIImage? = {
                    guard let rawSnapshot else { return nil }
                    guard let observation else { return rawSnapshot }
                    return SnapshotAnnotator.annotate(rawSnapshot, with: observation)
                }()
                var step = AgentStep(
                    index: used,
                    action: action,
                    reasoning: "replayed from a route that worked on this site before",
                    result: nil,
                    status: .executed,
                    snapshot: annotated,
                    pageMap: observation?.mapText
                )
                step.isReplayed = true
                step.routingReason = "replayed from memory — no decision paid for"
                step.targetFingerprint = move.target
                steps.append(step)
                trimStoredImages()

                phase = .acting
                let resultText = await execute(action).result
                steps[steps.count - 1].result = resultText
                lastResultLine = resultText
                recordExecutedMove(action, fingerprint: move.target, result: resultText)

                if let why = HeadStart.heldUp(expected: move.expectedReaction, actual: resultText) {
                    stopHeadStart(at: entryIndex, move: offset + 1, reason: why, recipeID: match.recipe.id, replayed: used)
                    return used
                }
            }
        }

        replayedMoveCount = used
        headStartHeld = true
        let plural = used == 1 ? "" : "s"
        steps[entryIndex].result = "replayed \(used) opening move\(plural) from memory — \(used) step\(plural) used, no decisions paid for"
        return used
    }

    /// Ends the head start honestly and marks the recipe as having gone stale. The
    /// replay does not try again for the rest of the run.
    private func stopHeadStart(at entryIndex: Int, move: Int, reason: String, recipeID: UUID, replayed: Int) {
        headStartOver = true
        headStartHeld = false
        replayedMoveCount = replayed
        vault.recordStray(recipeID)
        Haptics.warning()
        guard steps.indices.contains(entryIndex) else { return }
        steps[entryIndex].result = HeadStart.handoverLine(atMove: move, reason: reason)
    }

    /// Remembers the move for the memory writer. Only the shape of what happened
    /// is kept.
    ///
    /// The typed value is held separately, in memory, for this run only: it is
    /// what lets a saved replay put a blank where the value was. It is never
    /// added to `executedMoves`, so nothing that reaches disk can carry it.
    private func recordExecutedMove(_ action: AgentAction, fingerprint: ElementFingerprint?, result: String) {
        guard action.kind.isPageAction, executedMoves.count < 24 else { return }
        switch action.kind {
        case .typeInto, .typeText:
            if let text = action.text?.trimmed, !text.isEmpty {
                typedValues[executedMoves.count] = text
            }
        case .selectOption:
            if let option = action.option?.trimmed, !option.isEmpty {
                typedValues[executedMoves.count] = option
            }
        default:
            break
        }
        executedMoves.append(RecipeDistiller.Move(
            kind: action.kind,
            fingerprint: fingerprint,
            result: result,
            submitted: action.submit ?? false,
            direction: action.direction,
            amount: action.amount,
            urlString: action.url,
            valueKind: Self.valueKind(for: action)
        ))
    }

    /// Describes what KIND of thing was typed, never the text itself. This is the
    /// one place a typed value could have leaked into a memory, so it is written
    /// to make that impossible rather than merely unlikely.
    nonisolated private static func valueKind(for action: AgentAction) -> String? {
        switch action.kind {
        case .typeInto, .typeText: "what you're looking for"
        case .fillForm: "your details"
        case .selectOption: "an option"
        default: nil
        }
    }

    /// Writes the route that just worked into the vault. Reached only after the
    /// independent check confirms a success, so an unverified claim can never
    /// become a recipe.
    private func rememberRoute(goal: String, evidence: String?) async {
        guard settings.memoryEnabled else { return }
        let host = RecipeMatcher.normalizedHost(webProxy.webView.url?.absoluteString ?? "")
        guard !host.isEmpty, !executedMoves.isEmpty else { return }
        let route = RecipeDistiller.route(from: executedMoves)
        guard !route.isEmpty else { return }

        phase = .remembering
        let routeLines = route.enumerated().map { "\($0.offset + 1). \($0.element.plainLine)" }
        let label = await writeLabel(goal: goal, host: host, routeLines: routeLines)
        guard let recipe = RecipeDistiller.make(
            host: host,
            label: label,
            moves: executedMoves,
            plan: plan,
            verdictEvidence: evidence,
            stepCount: currentStepIndex
        ) else { return }
        vault.upsert(recipe)
    }

    /// Free on this iPhone; one small paid call when it cannot run the free tier;
    /// and a mechanical label if neither is possible — so a confirmed success
    /// always leaves something behind.
    private func writeLabel(goal: String, host: String, routeLines: [String]) async -> RecipeDistiller.Label {
        if isFreeTierReady {
            let answer = await onDevice.ask(
                instructions: RecipeDistiller.instructions,
                prompt: RecipeDistiller.prompt(goal: goal, host: host, routeLines: routeLines)
            )
            if let raw = answer.text, let label = RecipeDistiller.parseLabel(raw) {
                freeCallCount += 1
                return label
            }
        }
        do {
            let label = try await ai.label(AIService.LabelRequest(
                goal: goal,
                host: host,
                routeLines: routeLines,
                modelID: ModelChoice.fast.modelID
            ))
            memoryCallCount += 1
            countCall(on: .fast)
            return label
        } catch {
            return RecipeDistiller.fallbackLabel(goal: goal, host: host)
        }
    }

    // MARK: - Lessons: what this site has taught the agent by going wrong

    /// Folds this site's cautions into the briefing. Silent, free, and never used
    /// when a route that still works would contradict them.
    private func recallLessons(goal: String) {
        guard settings.lessonsEnabled else { return }
        let proven = vault.liveRecipes
        for host in lessonHosts(goal: goal) {
            let usable = lessonBook.cautions(for: host, avoiding: proven)
            guard !usable.isEmpty else { continue }
            cautionNote = lessonBook.briefing(for: host, avoiding: proven)
            handedOverCautions = Set(usable.map { $0.id })
            cautionsUsedCount = usable.count
            cautionHost = host
            return
        }
    }

    /// Sites worth reading the notebook for: where the browser is, where a saved
    /// replay is aimed, and any site the goal itself names.
    private func lessonHosts(goal: String) -> [String] {
        var hosts: [String] = []
        let current = RecipeMatcher.normalizedHost(webProxy.webView.url?.absoluteString ?? "")
        if !current.isEmpty { hosts.append(current) }
        if let routineHost = activeRoutine?.host, !routineHost.isEmpty { hosts.append(routineHost) }
        let words = RecipeMatcher.significantWords(goal)
        for host in Set(lessonBook.lessons.map { $0.host }) {
            let label = RecipeMatcher.primaryLabel(host)
            if !label.isEmpty, words.contains(label) { hosts.append(host) }
        }
        var seen: Set<String> = []
        return hosts.filter { seen.insert($0).inserted }
    }

    /// Writes down what this run learned, and doubts the cautions that turned out
    /// not to apply. Entirely mechanical, so it costs nothing and happens on every
    /// finished run rather than only the good ones.
    private func recordLessons(outcome: RunOutcome) -> (host: String, drafts: [LessonDistiller.Draft])? {
        guard settings.lessonsEnabled else { return nil }
        let current = RecipeMatcher.normalizedHost(webProxy.webView.url?.absoluteString ?? "")
        let host = current.isEmpty ? (cautionHost ?? activeRoutine?.host ?? "") : current
        guard !host.isEmpty else { return nil }

        let evidence = LessonDistiller.Evidence(
            moves: executedMoves,
            outcome: outcome,
            verdict: finalVerdict,
            failReason: lastFailReason,
            overlaySeen: overlaySeenThisRun,
            hitStepLimit: hitStepLimit,
            mismatchNotes: mismatchNotes
        )
        let drafts = LessonDistiller.read(evidence)

        // A caution is only doubted when the agent worked the site and found no
        // sign of the thing it warns about — never merely because a run went well.
        if let recalled = cautionHost, !handedOverCautions.isEmpty, executedMoves.count >= 2 {
            lessonBook.noteAbsent(
                host: recalled,
                handedOver: handedOverCautions,
                observed: Set(drafts.map { $0.kind })
            )
        }

        guard !drafts.isEmpty else { return nil }
        lessonBook.record(drafts, host: host)
        return (host, drafts)
    }

    /// Shortens this run's cautions, one at a time, on this iPhone. Runs after the
    /// run has already finished and been saved, so it can never delay a result or
    /// break one — the mechanical wording is already safely written down.
    private func polishCautions(_ drafts: [LessonDistiller.Draft], host: String) async {
        for draft in drafts {
            await polishCaution(draft, host: host)
        }
    }

    /// Asks this iPhone to shorten one caution into something a person would say.
    /// Free, optional, and discarded unless it still means the same thing.
    private func polishCaution(_ draft: LessonDistiller.Draft, host: String) async {
        let answer = await onDevice.ask(
            instructions: LessonDistiller.instructions,
            prompt: LessonDistiller.prompt(host: host, caution: draft.caution)
        )
        guard let raw = answer.text,
              let polished = LessonDistiller.parseCaution(raw, original: draft),
              let lesson = lessonBook.lessons(for: host).first(where: {
                  $0.kind == draft.kind && ($0.subject ?? "") == (draft.subject ?? "")
              })
        else { return }
        lessonBook.reword(lesson.id, to: polished)
    }

    // MARK: - Saved one-tap replays

    /// Launches a saved replay. The values you filled in are used for this run and
    /// then dropped — they are never written down.
    func startRoutine(_ routine: Routine, values: [UUID: String]) {
        guard runTask == nil else { return }
        pendingRoutine = (routine, values)
        goalText = routine.goal(filling: values)
        startRun()
    }

    /// True when the run that just finished is worth offering to save: it can be
    /// trusted, it happened somewhere real, it has moves a replay can actually
    /// perform, and it is not something you already saved.
    var canSaveRoutine: Bool {
        guard !isRunning, activeRoutine == nil, wasLastRunTrustworthy else { return false }
        guard lastFinishedGoal != nil else { return false }
        let host = RecipeMatcher.normalizedHost(webProxy.webView.url?.absoluteString ?? "")
        guard !host.isEmpty else { return false }
        let route = RoutineBuilder.savableRoute(from: RecipeDistiller.route(from: executedMoves))
        guard !route.isEmpty else { return false }
        return !routines.contains(host: host, moves: route)
    }

    /// Whether the last run earned the right to become a saved replay.
    ///
    /// Normally the independent check has to have confirmed it. With the check
    /// switched off there is no verdict to wait for, so a completed run stands on
    /// its own — otherwise turning the check off would quietly switch saving off
    /// with it, which is not a trade-off anyone asked for.
    private var wasLastRunTrustworthy: Bool {
        settings.verifyBeforeDone ? finalVerdict == .confirmed : lastFinishedOutcome == .completed
    }

    /// A name to offer for the replay, derived from the goal rather than invented.
    var suggestedRoutineTitle: String {
        let host = RecipeMatcher.normalizedHost(webProxy.webView.url?.absoluteString ?? "")
        return RecipeDistiller.fallbackLabel(goal: lastFinishedGoal ?? "", host: host).title
    }

    /// Saves the run that just finished as a one-tap replay.
    ///
    /// The route comes from the same mechanical derivation a memory uses, so it is
    /// value-free. What was typed is used only to find those values in the goal
    /// sentence and replace them with blanks to be asked for next time.
    func saveRoutine(title: String) {
        guard let goal = lastFinishedGoal else { return }
        let host = RecipeMatcher.normalizedHost(webProxy.webView.url?.absoluteString ?? "")
        let kept = RecipeDistiller.keptIndices(from: executedMoves)
        let route = RecipeDistiller.route(from: executedMoves)
        var values: [Int: String] = [:]
        for (routeIndex, executedIndex) in kept.enumerated() {
            if let value = typedValues[executedIndex] {
                values[routeIndex] = value
            }
        }
        guard let routine = RoutineBuilder.make(
            goal: goal,
            host: host,
            title: title,
            moves: route,
            typedValues: values
        ) else { return }
        routines.add(routine)
        Haptics.success()
    }

    /// Replays a saved route, repairing any step the site has moved.
    ///
    /// Each move has to earn its place exactly like a head start's does: the
    /// target has to be found on the live page, and the page has to react the way
    /// it did when the route was saved. What is different here is what happens
    /// when it is not found — instead of giving up, the step climbs the repair
    /// ladder, and a repair that works is written back so the next run is clean.
    private func runSavedReplay() async -> Int {
        guard let routine = activeRoutine, !routine.moves.isEmpty else { return 0 }

        var summary = AgentAction(type: AgentActionKind.replay.rawValue)
        let count = routine.moves.count
        summary.summary = "replay “\(routine.title)” — \(count) saved move\(count == 1 ? "" : "s")"
        var entry = AgentStep(
            index: 0,
            action: summary,
            reasoning: routine.routeLines.joined(separator: " → "),
            result: nil,
            status: .proposed,
            snapshot: nil,
            pageMap: nil
        )
        entry.isReplayed = true
        steps.append(entry)
        let entryIndex = steps.count - 1
        Haptics.light()

        // In Supervised mode the replay is one thing to approve, not many.
        if mode == .supervised {
            phase = .awaitingApproval
            Haptics.warning()
            let approved = await waitForApproval()
            if Task.isCancelled || !approved {
                steps[entryIndex].status = .rejected
                steps[entryIndex].result = "you skipped the saved replay — working from a fresh look instead"
                return 0
            }
        }
        steps[entryIndex].status = .executed

        var used = 0
        for (offset, move) in routine.moves.enumerated() {
            guard !Task.isCancelled, used < maxStepsThisRun else { break }

            phase = .replaying
            await webProxy.waitForQuiet(maxWait: 6)
            let observation = await webProxy.observe()
            lastObservation = observation
            if observation?.overlayLikely == true { overlaySeenThisRun = true }
            let rawSnapshot = await webProxy.snapshot()

            let resolution = await resolveSavedMove(move, at: offset, in: observation, routine: routine)
            guard case .ready(let action, let healNote, let healedTarget) = resolution else {
                if case .stop(let why) = resolution {
                    stopReplay(at: entryIndex, move: offset + 1, reason: why, replayed: used)
                }
                return used
            }

            let annotated: UIImage? = {
                guard let rawSnapshot else { return nil }
                guard let observation else { return rawSnapshot }
                return SnapshotAnnotator.annotate(rawSnapshot, with: observation)
            }()

            let stepNumber = used + 1
            var step = AgentStep(
                index: stepNumber,
                action: action,
                reasoning: healNote ?? "replayed from your saved route",
                result: nil,
                status: move.isCommitting ? .proposed : .executed,
                snapshot: annotated,
                pageMap: observation?.mapText
            )
            step.isReplayed = true
            step.wasHealed = healNote != nil
            step.healNote = healNote
            step.routingReason = healNote == nil
                ? "replayed from your saved route — no decision paid for"
                : StepHealer.repairLine(healNote ?? "")
            step.targetFingerprint = healedTarget ?? move.target
            steps.append(step)
            trimStoredImages()

            // Anything that submits, buys, sends or deletes stops for a yes, in
            // every mode. A saved replay is allowed to save you the setup; it is
            // never allowed to make the commitment on its own.
            if move.isCommitting {
                phase = .awaitingApproval
                Haptics.warning()
                let approved = await waitForApproval()
                if Task.isCancelled || !approved {
                    steps[steps.count - 1].status = .rejected
                    steps[steps.count - 1].result = "you did not approve this step, so the replay stopped here"
                    stopReplay(
                        at: entryIndex,
                        move: offset + 1,
                        reason: "the step that commits was not approved",
                        replayed: used
                    )
                    return used
                }
                steps[steps.count - 1].status = .executed
            }

            used = stepNumber
            currentStepIndex = used

            phase = .acting
            let resultText = await execute(action).result
            steps[steps.count - 1].result = resultText
            lastResultLine = resultText
            recordExecutedMove(action, fingerprint: step.targetFingerprint, result: resultText)

            if let why = HeadStart.heldUp(expected: move.expectedReaction, actual: resultText) {
                stopReplay(at: entryIndex, move: offset + 1, reason: why, replayed: used)
                return used
            }

            // The repair only becomes the route's new truth once it has actually
            // worked. A repair written back on faith would be a guess promoted to
            // a memory.
            if let healedTarget {
                healedMoveCount += 1
                routines.replaceTarget(routine.id, moveIndex: offset, with: healedTarget)
            }
        }

        replayedMoveCount = used
        headStartHeld = true
        routineFinishedCleanly = used == routine.moves.count && used > 0
        let plural = used == 1 ? "" : "s"
        var line = "replayed \(used) saved move\(plural) — no decisions paid for"
        if healedMoveCount > 0 {
            line += ", \(healedMoveCount) step\(healedMoveCount == 1 ? "" : "s") repaired along the way"
        }
        steps[entryIndex].result = line
        return used
    }

    private enum ReplayResolution {
        case ready(AgentAction, healNote: String?, healedTarget: ElementFingerprint?)
        case stop(String)
    }

    /// Works out how to run one saved move against the page as it is now.
    private func resolveSavedMove(
        _ move: RecipeMove,
        at index: Int,
        in observation: PageObservation?,
        routine: Routine
    ) async -> ReplayResolution {
        switch move.kind {
        case .wait, .back, .scroll, .navigate:
            switch HeadStart.resolve(move, in: observation) {
            case .matched(let action):
                return .ready(action, healNote: nil, healedTarget: nil)
            case .mismatch(let why):
                return .stop(why)
            }
        case .tapElement, .typeInto, .selectOption:
            break
        default:
            return .stop("this step needs something a saved replay never stores")
        }

        guard let target = move.target else {
            return .stop("the saved step has no target to look for")
        }

        // Typing and choosing need the blank you filled in at launch.
        var filled: String?
        if move.kind == .typeInto || move.kind == .selectOption {
            guard let value = routine.value(forMoveAt: index, from: routineValues) else {
                return .stop("nothing was filled in for “\(move.valueKind ?? "this step")”")
            }
            filled = value
        }

        var elementID: Int?
        var healNote: String?

        switch StepHealer.repair(for: target, in: observation) {
        case .exact(let id):
            elementID = id
        case .relaxed(let id, let note):
            guard settings.selfHealEnabled else {
                return .stop("“\(target.name)” is not on this page any more")
            }
            elementID = id
            healNote = note
        case .needsJudgement(let candidates):
            guard settings.selfHealEnabled else {
                return .stop("“\(target.name)” is not on this page any more")
            }
            guard let choice = await judgeReplacement(for: move, target: target, candidates: candidates) else {
                return .stop("nothing on this page could be matched to “\(target.name)”")
            }
            elementID = choice.id
            healNote = choice.why
        case .impossible(let why):
            return .stop(why)
        }

        guard let elementID,
              let observation,
              let element = observation.element(withID: elementID)
        else {
            return .stop("the target could not be read back from the page")
        }

        var action = AgentAction(type: move.action)
        action.element = elementID
        action.elementName = element.shortDescriptor
        if move.kind == .typeInto {
            action.text = filled
            action.submit = move.submits ?? false
        }
        if move.kind == .selectOption {
            action.option = filled
        }

        let healed = healNote == nil ? nil : ElementFingerprint.make(for: element, in: observation)
        return .ready(action, healNote: healNote, healedTarget: healed)
    }

    /// Decides which live element a moved step meant: free on this iPhone first,
    /// then one small paid call. Both are given the same shortlist of elements
    /// that provably exist on the page, and any answer outside it is discarded.
    private func judgeReplacement(
        for move: RecipeMove,
        target: ElementFingerprint,
        candidates: [StepHealer.Candidate]
    ) async -> (id: Int, why: String)? {
        guard !candidates.isEmpty else { return nil }

        if isFreeTierReady {
            let answer = await onDevice.ask(
                instructions: OnDeviceRepairer.instructions,
                prompt: OnDeviceRepairer.prompt(
                    intent: move.plainLine,
                    missingName: target.name,
                    missingKind: target.kind.rawValue,
                    candidates: candidates
                )
            )
            if let raw = answer.text, let picked = OnDeviceRepairer.parse(raw, allowed: candidates) {
                freeCallCount += 1
                return (picked, "your iPhone matched it to what the saved step meant — free")
            }
        }

        do {
            let choice = try await ai.repairTarget(AIService.RepairRequest(
                intent: move.plainLine,
                missingName: target.name,
                missingKind: target.kind.rawValue,
                candidates: candidates,
                urlString: webProxy.webView.url?.absoluteString ?? "",
                pageTitle: webProxy.webView.title ?? "",
                modelID: ModelChoice.fast.modelID
            ))
            repairCallCount += 1
            countCall(on: .fast)
            guard let choice else { return nil }
            return (choice.elementID, choice.why)
        } catch {
            return nil
        }
    }

    /// Ends a replay honestly. It does not try again for the rest of the run — the
    /// normal look-decide loop takes over from exactly here.
    private func stopReplay(at entryIndex: Int, move: Int, reason: String, replayed: Int) {
        headStartHeld = false
        replayedMoveCount = replayed
        routineFinishedCleanly = false
        mismatchNotes.append(reason)
        Haptics.warning()
        guard steps.indices.contains(entryIndex) else { return }
        steps[entryIndex].result = "the saved route stopped matching at move \(move) — \(reason); carrying on by looking"
    }

    /// A replay that held end to end has done the work, so the app makes the claim
    /// itself rather than paying for a decision that would only say "done". The
    /// independent check still has to confirm it — nothing is called complete on
    /// the strength of a replay alone.
    private func finishReplayedRun(goal: String) async -> ClaimOutcome {
        routineFinishedCleanly = false
        var action = AgentAction(type: AgentActionKind.done.rawValue)
        action.summary = "Replayed the saved route end to end."
        var step = AgentStep(
            index: currentStepIndex,
            action: action,
            reasoning: "every move of the saved replay ran, and the page reacted the way it did when the route was saved",
            result: nil,
            status: .proposed,
            snapshot: nil,
            pageMap: nil
        )
        step.isReplayed = true
        step.routingReason = "claimed by the replay itself — no decision paid for"
        steps.append(step)
        return await handleClaimedDone(action, goal: goal)
    }

    // MARK: - Your own objection

    /// True while flagging a mistake would mean anything: a run in flight with at
    /// least one move to object to.
    var canFlagMistake: Bool {
        isRunning && steps.contains { $0.action.kind.isPageAction }
    }

    /// The move your objection would be about, in plain words — shown on the
    /// sheet so you can see exactly what you are rejecting.
    var flaggableMoveText: String? {
        flaggableStep.map { $0.action.plainSentence }
    }

    /// While the agent is waiting on you, the move in question is the one on the
    /// table. Otherwise it is the last one that actually touched the page.
    private var flaggableStep: AgentStep? {
        if phase == .awaitingApproval { return steps.last }
        return steps.last { $0.action.kind.isPageAction }
    }

    /// Checkpoints you could be sent back to along with the objection.
    var rewindableBookmarks: [PageBookmark] {
        guard settings.bookmarksEnabled, !checkpointsUnavailable else { return [] }
        return bookmarks.reversed()
    }

    /// What your objection is doing right now, in plain words. nil when you have
    /// not stepped in this run.
    var mistakeStatus: String? {
        guard mistakeCount > 0 else { return nil }
        if awaitingReplan { return "rewriting its route — no extra call" }
        if mistakeRuleOnly { return "no rewrite left — held as a hard rule" }
        return "route rewritten after your flag"
    }

    /// You saw the agent go wrong. This is the one control in the app that
    /// outranks the agent's own judgement.
    ///
    /// It costs nothing extra. The rewrite it forces rides along with the next
    /// step's thinking, exactly as the agent's own re-planning does, and it never
    /// touches the mission's rewind allowance — spending the agent's own budget on
    /// your correction would punish you for helping.
    ///
    /// - Parameters:
    ///   - note: what was wrong, in your words. Optional — flagging with nothing
    ///     to say is still worth more than saying nothing at all.
    ///   - bookmark: a checkpoint to be sent back to as well, when one helps.
    func flagMistake(note: String, rewindTo bookmark: PageBookmark? = nil) {
        guard isRunning else { return }
        let clean = String(note.trimmed.prefix(MistakeBriefing.maxNoteLength))
        let flagged = flaggableStep
        let wasWaiting = phase == .awaitingApproval

        mistakeCount += 1
        replanRefusals = 0
        // Your correction always goes to the strongest model. This is the moment
        // the run can least afford a cheap guess.
        mustEscalate = true

        // Barred by signature, so the exact move cannot come back around — not
        // discouraged in a prompt, refused in code.
        if let flagged {
            let signature = flagged.action.repetitionSignature
            barredSignatures.insert(signature)
            failedSignatures.insert(signature)
            noteTried("you flagged this as a mistake: \(flagged.action.plainSentence)")
        }

        // The checklist stops claiming work you have just rejected.
        plan?.untickLatest()

        // A rewrite is only demanded when there is a plan with a rewrite left in
        // it. When there is not, your objection becomes a standing rule rather
        // than being quietly dropped.
        let canRewrite = plan?.canRevise ?? false
        awaitingReplan = canRewrite
        mistakeRuleOnly = !canRewrite
        mistakeRule = MistakeBriefing.standingRule(move: flagged?.action.plainSentence, note: clean)
        pendingMistakeNote = canRewrite
            ? MistakeBriefing.rewriteDemand(rule: mistakeRule ?? "")
            : mistakeRule

        // The move on the table never runs — marked before your entry is added so
        // the log reads in the order it happened.
        if wasWaiting, let last = steps.indices.last {
            steps[last].status = .rejected
            steps[last].result = "you flagged this as a mistake, so it never ran"
        }

        appendMistakeStep(flagged: flagged, note: clean, canRewrite: canRewrite, bookmark: bookmark)

        if let bookmark { userRewindTarget = bookmark }
        Haptics.warning()

        if wasWaiting {
            didFlagDuringApproval = true
            resumeApproval(false)
        }
    }

    /// Your objection, in the log, as your own entry. Marked as yours so the
    /// record shows who changed course and why.
    private func appendMistakeStep(
        flagged: AgentStep?,
        note: String,
        canRewrite: Bool,
        bookmark: PageBookmark?
    ) {
        var action = AgentAction(type: AgentActionKind.mistake.rawValue)
        action.summary = note.isEmpty ? "you flagged the last move as a mistake" : note

        var step = AgentStep(
            index: currentStepIndex,
            action: action,
            reasoning: flagged.map { "you rejected: \($0.action.plainSentence)" }
                ?? "you rejected the route the agent was taking",
            result: nil,
            status: .terminal,
            snapshot: nil,
            pageMap: nil
        )

        var parts: [String] = [
            canRewrite
                ? "the agent has to rewrite its route before it can touch the page again — no extra call, the rewrite uses the next step's thinking"
                : "there is no plan rewrite left in this mission, so your objection is held as a hard rule for every remaining step",
        ]
        if flagged != nil { parts.append("that move is barred for the rest of the run") }
        if let bookmark { parts.append("going back to checkpoint \(bookmark.number)") }
        step.result = parts.joined(separator: " · ")

        steps.append(step)
        trimStoredImages()
    }

    /// Why this move may not run, when your objection bars it. nil means run it.
    private func refusalReason(for action: AgentAction) -> String? {
        if barredSignatures.contains(action.repetitionSignature) {
            return MistakeBriefing.barredLine
        }
        guard awaitingReplan, action.kind.isPageAction else { return nil }

        if replanRefusals >= MistakeBriefing.maxRefusals {
            // A model that will not rewrite its route must not be able to spin the
            // run being refused. Your objection stops being a gate and becomes a
            // standing rule — which the panel says out loud.
            awaitingReplan = false
            mistakeRuleOnly = true
            pendingMistakeNote = mistakeRule
            return nil
        }

        replanRefusals += 1
        pendingMistakeNote = MistakeBriefing.refusalDemand(rule: mistakeRule ?? "")
        return MistakeBriefing.rewriteFirstLine
    }

    // MARK: - Memory ceiling

    /// How many recent steps keep their screenshots at full resolution.
    private static let sharpStepWindow = 3
    /// Width older screenshots are shrunk to — still readable in Agent Vision.
    private static let archivedImageWidth: CGFloat = 400

    /// Keeps the newest screenshots sharp and downscales older ones, so a long
    /// run's image memory stops growing. Every step keeps a picture; only the
    /// resolution of the older ones drops.
    private func trimStoredImages() {
        let cutoff = steps.count - Self.sharpStepWindow
        guard cutoff > 0 else { return }
        for index in 0..<cutoff where !steps[index].imagesTrimmed {
            steps[index].imagesTrimmed = true
            steps[index].snapshot = Self.shrink(steps[index].snapshot)
            steps[index].overviewImage = Self.shrink(steps[index].overviewImage)
            steps[index].destinationSnapshot = Self.shrink(steps[index].destinationSnapshot)
        }
    }

    private static func shrink(_ image: UIImage?) -> UIImage? {
        guard let image, image.size.width > archivedImageWidth, image.size.width > 0 else { return image }
        let scale = archivedImageWidth / image.size.width
        let size = CGSize(
            width: archivedImageWidth,
            height: max((image.size.height * scale).rounded(), 1)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The bare trail handed to the check: moves and outcomes only. The agent's
    /// own reasoning is withheld on purpose.
    private func actionTrail() -> [String] {
        steps
            .filter { $0.action.kind != .verify && ($0.status == .executed || $0.status == .terminal) }
            .suffix(12)
            .map { step in
                var line = "\(step.displayNumber). \(step.action.kind.label) \(step.action.detailText)"
                if let result = step.result, !result.isEmpty {
                    line += " → \(String(result.prefix(110)))"
                }
                return line
            }
    }

    // MARK: - Checkpoints and rewinding

    /// Your own rewind from the checkpoint strip: mid-run it sends the agent back
    /// there, and when nothing is running it simply takes the browser back.
    func userRewind(to bookmark: PageBookmark) {
        Haptics.medium()
        if phase == .awaitingApproval {
            userRewindTarget = bookmark
            resumeApproval(false)
            return
        }
        guard !isRunning else { return }
        Task { [weak self] in
            await self?.restoreForUser(bookmark)
        }
    }

    /// True while tapping a checkpoint is allowed — paused for approval, or idle.
    var canRewindByHand: Bool {
        phase == .awaitingApproval || !isRunning
    }

    /// True for the checkpoint the browser is currently standing on.
    func isCurrentBookmark(_ bookmark: PageBookmark) -> Bool {
        currentBookmarkNumber == bookmark.number
    }

    /// Compact routing tally for the run telemetry — every paid call, not just steps.
    var routingTally: String? {
        guard fastCallCount + preciseCallCount > 0 else { return nil }
        return "\(fastCallCount)F/\(preciseCallCount)P"
    }

    /// The free share, shown apart from the paid tally so free work looks free.
    var freeTally: String? {
        freeCallCount > 0 ? "\(freeCallCount) FREE" : nil
    }

    /// Saved steps this run had to repair to keep a replay working.
    var healTally: String? {
        healedMoveCount > 0 ? "\(healedMoveCount) HEALED" : nil
    }

    /// Cautions from earlier failures on this site that are in play right now.
    var cautionTally: String? {
        cautionsUsedCount > 0 ? "\(cautionsUsedCount) CAUTION\(cautionsUsedCount == 1 ? "" : "S")" : nil
    }

    // MARK: - The live thinking panel

    /// The step the panel is currently narrating: the newest one that is not one
    /// of the app's own bookkeeping entries.
    private var narratedStep: AgentStep? {
        steps.last { !$0.isCheckEntry && !$0.isHeadStartEntry && !$0.isReplayEntry }
    }

    /// The agent's own words for the move it is making. Never synthesised — when
    /// the agent said nothing, the panel shows nothing rather than inventing an
    /// inner monologue for it.
    var liveThought: String? {
        guard let step = narratedStep else { return nil }
        let text = step.reasoning.trimmed
        return text.isEmpty ? nil : text
    }

    /// That move in plain words — "tap the button “Apply filter”".
    var liveMove: String? {
        narratedStep.map { $0.action.plainSentence }
    }

    /// Whether the newest narrated entry is your own objection rather than a move.
    var liveMoveIsYours: Bool {
        narratedStep?.isMistakeEntry ?? false
    }

    /// True when the move being narrated repaired itself because the site had
    /// moved the control. Shown so a healed step never passes for a clean one.
    var liveMoveWasHealed: Bool {
        narratedStep?.wasHealed ?? false
    }

    /// What the page actually did, for the panel's honest result line.
    var liveResult: String? {
        guard let result = narratedStep?.result?.trimmed, !result.isEmpty else { return nil }
        return result
    }

    /// The saved replay this run is working through, when it is working through one.
    var activeRoutineTitle: String? { activeRoutine?.title }

    /// Total PAID AI calls made so far this run.
    var totalCallCount: Int { fastCallCount + preciseCallCount }

    /// Records one AI call against the model that answered it. On-device work is
    /// counted separately and never added to the paid totals — it is free, and a
    /// tally that inflated it would be lying about what the run cost.
    private func countCall(on choice: ModelChoice) {
        switch choice {
        case .onDevice: freeCallCount += 1
        case .fast: fastCallCount += 1
        case .precise: preciseCallCount += 1
        }
    }

    private func restoreForUser(_ bookmark: PageBookmark) async {
        switch await webProxy.restore(bookmark) {
        case .restored(let note), .changed(let note):
            currentBookmarkNumber = bookmark.number
            outcomeBanner = OutcomeBanner(outcome: .stopped, message: "Rewound — \(note).")
            Haptics.medium()
        case .failed(let why):
            outcomeBanner = OutcomeBanner(outcome: .failed, message: "Couldn't rewind — \(why).")
            Haptics.error()
        }
    }

    /// Checkpoints go in before anything branching or risky: a new page, the first
    /// tap into a list of results, any submit, and at each checklist task boundary.
    private func shouldCapture(before action: AgentAction) -> Bool {
        guard settings.bookmarksEnabled, !checkpointsUnavailable else { return false }
        if action.submit == true { return true }
        switch action.kind {
        case .navigate, .fillForm:
            return true
        case .tapElement:
            let name = (action.elementName ?? "").lowercased()
            if name.hasPrefix("link") { return true }
            if DifficultyScout.irreversibleWords.contains(where: { name.contains($0) }) { return true }
        default:
            break
        }
        if let number = plan?.currentTask?.number, number != lastTaskNumberForBookmark {
            return true
        }
        return false
    }

    /// Captures the page as it stands before the move, keeping five at most.
    private func captureBookmark(snapshot: UIImage?) async {
        let urlString = webProxy.webView.url?.absoluteString ?? ""
        guard !urlString.isEmpty else { return }
        lastTaskNumberForBookmark = plan?.currentTask?.number

        if let existing = bookmarks.last, existing.urlString == urlString {
            currentBookmarkNumber = existing.number
            return
        }

        let scrollY = await webProxy.scrollPosition()
        let label = await webProxy.checkpointLabel()
        bookmarkCounter += 1
        bookmarks.append(PageBookmark(
            number: bookmarkCounter,
            label: label,
            urlString: urlString,
            scrollY: scrollY,
            thumbnail: snapshot,
            taskNumber: plan?.currentTask?.number
        ))
        if bookmarks.count > PageBookmark.capacity {
            bookmarks.removeFirst(bookmarks.count - PageBookmark.capacity)
        }
        currentBookmarkNumber = bookmarkCounter
    }

    /// The checkpoint strip as the agent reads it, with what has already failed there.
    private func bookmarksNote() -> String? {
        guard settings.bookmarksEnabled, !checkpointsUnavailable, !bookmarks.isEmpty else { return nil }
        var lines = ["CHECKPOINTS you can rewind to (\(rewindCount) of \(Self.maxRewinds) rewinds used):"]
        for bookmark in bookmarks {
            var line = "\(bookmark.number). \(bookmark.label)"
            if bookmark.number == currentBookmarkNumber { line += " (you are here)" }
            line += " — tried from here: \(bookmark.triedLine)"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Remembers a dead end at the point the agent is standing on.
    private func noteTried(_ line: String) {
        guard let number = currentBookmarkNumber,
              let index = bookmarks.firstIndex(where: { $0.number == number }),
              bookmarks[index].tried.count < 6
        else { return }
        bookmarks[index].tried.append(line)
    }

    /// Learns from what just happened: a failure escalates the next step to the
    /// frontier model, is remembered as a dead end, and puts the runner-up back
    /// on the table.
    private func noteOutcome(action: AgentAction, result: String) {
        guard ReactionWatch.readsAsFailure(result) else {
            mustEscalate = false
            runnerUp = nil
            return
        }
        mustEscalate = true
        failedSignatures.insert(action.repetitionSignature)
        noteTried("\(action.kind.label) \(action.detailText) → \(String(result.prefix(70)))")
        if let alternative = runnerUp {
            pendingRunnerUpNote = "YOUR ALTERNATIVE FROM LAST STEP is still on the table: \(alternative.moveText)\(alternative.rationale.isEmpty ? "" : " — \(alternative.rationale)"). The move you played failed, so this is the natural next try."
            runnerUp = nil
        }
    }

    /// The agent's own rewind move.
    private func performRewind(_ action: AgentAction) async {
        let last = steps.count - 1
        guard last >= 0 else { return }
        steps[last].status = .executed

        guard settings.bookmarksEnabled, !checkpointsUnavailable, !bookmarks.isEmpty else {
            steps[last].result = "there are no checkpoints to rewind to — find another route from here"
            return
        }
        guard rewindCount < Self.maxRewinds else {
            steps[last].result = "rewind refused — this mission's \(Self.maxRewinds)-rewind limit is used up; work forward from here"
            return
        }
        guard let number = action.bookmark,
              let target = bookmarks.first(where: { $0.number == number })
        else {
            let available = bookmarks.map { "\($0.number)" }.joined(separator: ", ")
            steps[last].result = "there is no checkpoint \(action.bookmark ?? 0) — available: \(available)"
            return
        }

        if let reason = action.reason, !reason.isEmpty {
            noteTried("abandoned this route: \(String(reason.prefix(70)))")
        }
        await rewind(to: target, reason: action.reason ?? "", counted: true)
    }

    /// Restores a checkpoint and writes the result into the current step, handing
    /// the dead-end list to the next briefing.
    private func rewind(to bookmark: PageBookmark, reason: String, counted: Bool) async {
        let last = steps.count - 1
        guard last >= 0 else { return }
        if counted { rewindCount += 1 }

        let outcome = await webProxy.restore(bookmark)
        var landedNote: String?
        var pageMovedOn = false
        switch outcome {
        case .restored(let note):
            landedNote = note
        case .changed(let note):
            landedNote = note
            pageMovedOn = true
        case .failed(let why):
            checkpointsUnavailable = true
            steps[last].result = "couldn't rewind — \(why); checkpoints are switched off for the rest of this run"
            Haptics.warning()
            return
        }

        guard let note = landedNote else { return }
        currentBookmarkNumber = bookmark.number
        lastTaskNumberForBookmark = bookmark.taskNumber
        lastResultLine = nil
        mustEscalate = true
        steps[last].destinationSnapshot = await webProxy.snapshot()
        // Appended rather than replaced: the entry may already say something the
        // user needs — why they sent it back, what got barred.
        let landed = counted ? "\(note) (rewind \(rewindCount) of \(Self.maxRewinds))" : note
        if let existing = steps[last].result, !existing.isEmpty {
            steps[last].result = "\(existing) · \(landed)"
        } else {
            steps[last].result = landed
        }

        let tried = bookmark.tried.isEmpty
            ? "Nothing has been tried from here yet."
            : "From here you already tried: \(bookmark.triedLine). Do not repeat any of it."
        var deadEnds = "YOU ARE BACK AT CHECKPOINT \(bookmark.number) (\(bookmark.label)). \(tried) Take a different branch."
        if pageMovedOn {
            deadEnds += " The page came back different from the checkpoint, so read it fresh instead of assuming."
        }
        if !reason.isEmpty {
            deadEnds += " You came back because: \(String(reason.prefix(90)))."
        }
        pendingDeadEndNote = deadEnds
        Haptics.medium()
    }

    /// A checkpoint that still has something left to try — the basis of the
    /// one-time push-back after a premature give-up. Real walls are exempt.
    private func rescueTarget(for reason: String) -> PageBookmark? {
        guard settings.bookmarksEnabled,
              !checkpointsUnavailable,
              !didOfferRescue,
              rewindCount < Self.maxRewinds,
              !Self.isHardWall(reason)
        else { return nil }
        let untried = bookmarks.reversed().filter { $0.hasUntriedRoute }
        return untried.first { $0.number != currentBookmarkNumber } ?? untried.first
    }

    nonisolated private static func isHardWall(_ reason: String) -> Bool {
        let lower = reason.lowercased()
        let walls = [
            "captcha", "bot ", "bot-", "robot", "log in", "login", "sign in", "signin",
            "account", "blocked", "403", "paywall", "verify you", "human", "subscription",
        ]
        return walls.contains { lower.contains($0) }
    }

    private func isRepeatingRecently() -> Bool {
        let pageMoves = steps.filter { $0.action.kind.isPageAction }
        guard pageMoves.count >= 2 else { return false }
        return Set(pageMoves.suffix(2).map { $0.action.repetitionSignature }).count == 1
    }

    // MARK: - Acting

    private func execute(_ action: AgentAction) async -> (result: String, extracted: String?) {
        switch action.kind {
        case .tapElement:
            guard let elementID = action.element else {
                return ("tap_element was missing its element number — look at the page and try again", nil)
            }
            let expected = lastObservation?.element(withID: elementID)
            await webProxy.beginReactionWatch(targetID: elementID)
            let result = await webProxy.tapElement(
                id: elementID,
                descriptor: expected?.shortDescriptor ?? "",
                expectedName: expected?.name ?? ""
            )
            try? await Task.sleep(for: .milliseconds(900))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .typeInto:
            guard let elementID = action.element else {
                return ("type_into was missing its element number — look at the page and try again", nil)
            }
            let expected = lastObservation?.element(withID: elementID)
            let typed = action.text ?? ""
            let submitted = action.submit ?? false
            await webProxy.beginReactionWatch(targetID: elementID)
            let result = await webProxy.typeInto(
                id: elementID,
                text: typed,
                submit: submitted,
                descriptor: expected?.shortDescriptor ?? "",
                expectedName: expected?.name ?? ""
            )
            try? await Task.sleep(for: .milliseconds(700))
            let landed = await webProxy.fieldValue(id: elementID, expectedName: expected?.name ?? "")
            let watcher = await webProxy.endReactionWatch()
            let verdict = ReactionWatch.typingVerdict(
                typed: typed,
                fieldValue: landed,
                watcher: watcher,
                submitted: submitted
            ).text
            return (ReactionWatch.combine(result, verdict), nil)
        case .fillForm:
            let fields = action.fields ?? []
            guard !fields.isEmpty else {
                return ("fill_form had no fields — provide {element, text} pairs", nil)
            }
            await webProxy.beginReactionWatch(targetID: fields.first?.element)
            let entries = fields.map { field in
                (id: field.element, text: field.text, expectedName: lastObservation?.element(withID: field.element)?.name ?? "")
            }
            let result = await webProxy.fillForm(entries, submit: action.submit ?? false)
            try? await Task.sleep(for: .milliseconds(800))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .selectOption:
            guard let elementID = action.element else {
                return ("select_option was missing its element number — look at the page and try again", nil)
            }
            await webProxy.beginReactionWatch(targetID: elementID)
            let result = await webProxy.selectOption(
                id: elementID,
                option: action.option ?? "",
                expectedName: lastObservation?.element(withID: elementID)?.name ?? ""
            )
            try? await Task.sleep(for: .milliseconds(700))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .setToggle:
            guard let elementID = action.element else {
                return ("set_toggle was missing its element number — look at the page and try again", nil)
            }
            await webProxy.beginReactionWatch(targetID: elementID)
            let result = await webProxy.setToggle(
                id: elementID,
                on: action.on ?? true,
                expectedName: lastObservation?.element(withID: elementID)?.name ?? ""
            )
            try? await Task.sleep(for: .milliseconds(500))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .setSlider:
            guard let elementID = action.element else {
                return ("set_slider was missing its element number — look at the page and try again", nil)
            }
            await webProxy.beginReactionWatch(targetID: elementID)
            let result = await webProxy.setSlider(
                id: elementID,
                percent: action.value ?? 50,
                expectedName: lastObservation?.element(withID: elementID)?.name ?? ""
            )
            try? await Task.sleep(for: .milliseconds(500))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .drag:
            let hasSource = action.from != nil || (action.fromX != nil && action.fromY != nil)
            let hasTarget = action.to != nil || (action.toX != nil && action.toY != nil)
            guard hasSource, hasTarget else {
                return ("drag needs both ends — from/to element numbers, or from_x/from_y and to_x/to_y", nil)
            }
            await webProxy.beginReactionWatch(targetID: action.from ?? action.to)
            let result = await webProxy.drag(
                fromID: action.from,
                toID: action.to,
                fromNormX: action.fromX,
                fromNormY: action.fromY,
                toNormX: action.toX,
                toNormY: action.toY,
                fromName: action.from.flatMap { lastObservation?.element(withID: $0)?.name } ?? "",
                toName: action.to.flatMap { lastObservation?.element(withID: $0)?.name } ?? ""
            )
            try? await Task.sleep(for: .milliseconds(700))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .longPress:
            guard let elementID = action.element else {
                return ("long_press was missing its element number — look at the page and try again", nil)
            }
            await webProxy.beginReactionWatch(targetID: elementID)
            let result = await webProxy.longPress(
                id: elementID,
                expectedName: lastObservation?.element(withID: elementID)?.name ?? ""
            )
            try? await Task.sleep(for: .milliseconds(500))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .hover:
            guard let elementID = action.element else {
                return ("hover was missing its element number — look at the page and try again", nil)
            }
            await webProxy.beginReactionWatch(targetID: elementID)
            let result = await webProxy.hover(
                id: elementID,
                expectedName: lastObservation?.element(withID: elementID)?.name ?? ""
            )
            try? await Task.sleep(for: .milliseconds(800))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .swipe:
            await webProxy.beginReactionWatch(targetID: action.element)
            let result = await webProxy.swipe(
                direction: action.direction ?? "left",
                elementID: action.element,
                expectedName: action.element.flatMap { lastObservation?.element(withID: $0)?.name } ?? ""
            )
            try? await Task.sleep(for: .milliseconds(400))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .tap:
            await webProxy.beginReactionWatch(targetID: nil)
            let result = await webProxy.tap(normX: action.x ?? 500, normY: action.y ?? 500)
            try? await Task.sleep(for: .milliseconds(900))
            let verdict = await webProxy.endReactionWatch()
            return (ReactionWatch.combine(result, verdict), nil)
        case .typeText:
            let typed = action.text ?? ""
            let submitted = action.submit ?? false
            await webProxy.beginReactionWatch(targetID: nil)
            let result = await webProxy.typeText(typed, submit: submitted)
            try? await Task.sleep(for: .milliseconds(600))
            let landed = await webProxy.focusedFieldValue()
            let watcher = await webProxy.endReactionWatch()
            let verdict = ReactionWatch.typingVerdict(
                typed: typed,
                fieldValue: landed,
                watcher: watcher,
                submitted: submitted
            ).text
            return (ReactionWatch.combine(result, verdict), nil)
        case .scroll:
            let before = await webProxy.scrollPosition()
            await webProxy.beginReactionWatch(targetID: nil)
            let result = await webProxy.scroll(direction: action.direction ?? "down", amount: action.amount ?? 600)
            try? await Task.sleep(for: .milliseconds(900))
            let watcher = await webProxy.endReactionWatch()
            let moved = await webProxy.scrollPosition() - before
            let verdict = ReactionWatch.scrollVerdict(movedBy: moved, watcher: watcher).text
            return (ReactionWatch.combine(result, verdict), nil)
        case .navigate:
            let target = (action.url ?? "").trimmed
            guard !target.isEmpty else {
                return ("navigate was missing its address — provide a full url", nil)
            }
            let before = webProxy.webView.url?.absoluteString ?? ""
            webProxy.load(target)
            await webProxy.waitForQuiet(maxWait: 8)
            let verdict = ReactionWatch.addressVerdict(
                before: before,
                after: webProxy.webView.url?.absoluteString ?? ""
            ).text
            return ("asked for \(target) · \(verdict)", nil)
        case .back:
            guard webProxy.canGoBack else {
                return ("couldn't go back — there is no earlier page to return to", nil)
            }
            let before = webProxy.webView.url?.absoluteString ?? ""
            webProxy.goBack()
            await webProxy.waitForQuiet(maxWait: 8)
            let verdict = ReactionWatch.addressVerdict(
                before: before,
                after: webProxy.webView.url?.absoluteString ?? ""
            ).text
            return ("went back · \(verdict)", nil)
        case .extract:
            let text = await webProxy.extractText()
            return ("read a cleaned copy of the whole page (\(text.count) characters)", text)
        case .pageOverview:
            switch await webProxy.capturePageOverview() {
            case .captured(let image, let note):
                pendingOverview = (image, note)
                return ("captured a whole-page overview — \(note); it is attached to my next look (orientation only, no badges)", nil)
            case .singleScreen:
                return ("the whole page already fits on one screen — no overview needed", nil)
            case .failed(let why):
                return ("couldn't capture the overview — \(why)", nil)
            }
        case .wait:
            try? await Task.sleep(for: .seconds(2))
            return ("waited 2s", nil)
        case .revisePlan, .rewind, .done, .fail, .verify, .headStart, .replay, .mistake, .unknown:
            return ("no-op", nil)
        }
    }

    private func finishRun(_ outcome: RunOutcome, _ message: String, goal: String) {
        phase = .idle
        onDevice.coolDown()
        resumeApproval(false)

        // Both of these are mechanical and free, so they happen on every finished
        // run rather than only the good ones — a run that went wrong is the one
        // with the most to teach.
        let learned = recordLessons(outcome: outcome)
        recordRoutineAttempt(outcome: outcome)

        // Held so the banner can offer to save this run as a one-tap replay.
        lastFinishedGoal = goal
        lastFinishedOutcome = outcome

        persistRun(outcome: outcome, message: message, goal: goal)
        outcomeBanner = OutcomeBanner(outcome: outcome, message: message)
        activeGoal = nil
        runTask = nil
        switch outcome {
        case .completed: Haptics.success()
        case .unconfirmed: Haptics.warning()
        case .failed: Haptics.error()
        case .stopped: Haptics.warning()
        }

        // The one optional flourish, off the critical path: ask this iPhone to
        // shorten the cautions into something a person would say. Free, and the
        // mechanical wording stands if it declines.
        if let learned, isFreeTierReady {
            Task { [weak self] in
                await self?.polishCautions(learned.drafts, host: learned.host)
            }
        }
    }

    /// Writes the attempt back onto the saved replay it came from: how many times
    /// it has run, how many steps it had to repair, and how it ended. Without this
    /// a routine's own record stays frozen at zero and the honest "last time this
    /// didn't work" warning on its chip can never appear.
    private func recordRoutineAttempt(outcome: RunOutcome) {
        guard let routine = activeRoutine else { return }
        routines.recordRun(routine.id, outcome: outcome, healed: healedMoveCount)
    }

    // MARK: - Approval plumbing

    private func waitForApproval() async -> Bool {
        await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    private func resumeApproval(_ approved: Bool) {
        guard let continuation = approvalContinuation else { return }
        approvalContinuation = nil
        continuation.resume(returning: approved)
    }

    // MARK: - Context helpers

    private func historyLines() -> [String] {
        var lines = steps.suffix(8).map { step in
            var line = "\(step.displayNumber). \(step.action.kind.label) \(step.action.detailText)"
            if !step.reasoning.isEmpty {
                line += " — \(String(step.reasoning.prefix(80)))"
            }
            if let result = step.result {
                line += " → \(String(result.prefix(90)))"
            }
            return line
        }
        let pageMoves = steps.filter { $0.action.kind.isPageAction }
        if pageMoves.count >= 3 {
            let signatures = Set(pageMoves.suffix(3).map { $0.action.repetitionSignature })
            if signatures.count == 1 {
                lines.append("WARNING: The same action was repeated 3 times without progress. Choose a different approach.")
            }
        }
        return lines
    }

    private func persistRun(outcome: RunOutcome, message: String, goal: String) {
        guard !didPersistRun else { return }
        didPersistRun = true
        guard !steps.isEmpty else { return }
        let persisted = steps.map { step in
            PersistedStep(
                id: step.id,
                index: step.index,
                actionType: step.action.kind.rawValue,
                actionDetail: step.action.detailText,
                reasoning: step.reasoning,
                result: step.result,
                statusRaw: step.status.rawValue,
                thumbnailFile: step.displaySnapshot.flatMap { history.saveThumbnail($0) },
                taskNumber: step.taskNumber,
                taskTitle: step.taskTitle,
                verdictRaw: step.verification?.verdict.rawValue,
                modelRaw: step.modelChoice?.rawValue,
                difficultyRaw: step.difficulty?.rawValue,
                weighedCount: step.candidates.isEmpty ? nil : step.candidates.count,
                wasReplayed: step.isReplayed ? true : nil,
                wasHealed: step.wasHealed ? true : nil
            )
        }
        history.add(AgentRun(
            id: UUID(),
            goal: goal,
            date: runStartDate,
            outcome: outcome,
            summary: message,
            steps: persisted,
            plan: plan,
            verdictRaw: finalVerdict?.rawValue,
            fastSteps: fastCallCount,
            preciseSteps: preciseCallCount,
            rewinds: rewindCount,
            weighedMoves: weighedMoveCount,
            planningCalls: planningCallCount,
            checkCalls: checkCallCount,
            memoryCalls: memoryCallCount,
            freeSteps: freeCallCount,
            memoryUsed: recalledMatch?.recipe.title,
            replayedMoves: replayedMoveCount,
            headStartHeld: headStartHeld,
            routineTitle: activeRoutine?.title,
            healedMoves: healedMoveCount > 0 ? healedMoveCount : nil,
            repairCalls: repairCallCount > 0 ? repairCallCount : nil,
            cautionsUsed: cautionsUsedCount > 0 ? cautionsUsedCount : nil,
            mistakesFlagged: mistakeCount > 0 ? mistakeCount : nil
        ))
    }

    // MARK: - Image encoding

    /// JPEG-encodes a snapshot within a conservative byte budget for the AI gateway.
    nonisolated private static func jpegBase64(
        from image: UIImage,
        maxBytes: Int = 2_800_000,
        startQuality: CGFloat = 0.7
    ) -> String {
        var quality = startQuality
        var data = image.jpegData(compressionQuality: quality) ?? Data()
        while data.count > maxBytes && quality > 0.3 {
            quality -= 0.15
            data = image.jpegData(compressionQuality: quality) ?? Data()
        }
        return data.base64EncodedString()
    }
}
