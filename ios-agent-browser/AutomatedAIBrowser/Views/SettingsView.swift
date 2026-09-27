import SwiftUI

/// Mode, step budget, mission planning, the independent check, model routing,
/// judgment aids, and data controls.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HistoryStore.self) private var history
    @Environment(OnDeviceModel.self) private var onDevice
    @Environment(RecipeVault.self) private var vault
    @Environment(LessonBook.self) private var lessonBook
    @Environment(RoutineStore.self) private var routines
    @Environment(Dossier.self) private var dossier
    @Environment(\.dismiss) private var dismiss
    @State private var showDossier = false
    @State private var confirmClear = false
    @State private var confirmForget = false
    @State private var confirmForgetLessons = false
    @State private var confirmForgetRoutines = false
    @State private var gatewayProfile = GatewayProfile.current
    @State private var gatewayReport: [String] = []
    @State private var probing = false

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                benchmarkSection
                railsSection
                planningSection
                checkSection
                strategySection
                freeTierSection
                memorySection
                lessonsSection
                replaySection
                dossierSection
                judgmentSection
                modelSection
                gatewaySection
                dataSection
                limitsSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .confirmationDialog("Delete all saved runs?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    history.clearAll()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Forget every learned route?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget All", role: .destructive) {
                    vault.wipe()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Clear everything learned from failures?", isPresented: $confirmForgetLessons, titleVisibility: .visible) {
                Button("Clear All", role: .destructive) {
                    lessonBook.wipe()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete every saved replay?", isPresented: $confirmForgetRoutines, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    routines.wipe()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showDossier) {
                DossierView()
            }
            .onAppear {
                onDevice.refresh()
            }
        }
    }

    private var modeSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker("Default mode", selection: $settings.defaultMode) {
                ForEach(AgentMode.allCases) { mode in
                    Text(mode.fullName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Default Mode")
        } footer: {
            Text("Autopilot runs every step on its own. Supervised waits for your approval before each action. You can still switch per run from the command bar.")
        }
    }

    private var railsSection: some View {
        @Bindable var settings = settings
        return Section {
            Stepper("Max steps per run: \(settings.maxSteps)", value: $settings.maxSteps, in: AppSettings.stepRange)
        } header: {
            Text("Safety Rails")
        } footer: {
            Text("Counts browser steps only — rewinds and drafted alternatives use steps, they never silently extend a run. Mission planning and the independent check are separate and never eat this budget.")
        }
    }

    private var planningSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker("Mission planning", selection: $settings.planning) {
                ForEach(PlanningPreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Mission Planning")
        } footer: {
            Text("Before the first move the agent writes a short checklist — each task with its own \"done when\" test — and you watch it tick off live. One extra call at the start of a run; ticking the list and rewriting the plan are free. Off restores the old behavior exactly.")
        }
    }

    private var checkSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Verify before done", isOn: $settings.verifyBeforeDone)
            Toggle("Cross-check with the other model", isOn: $settings.crossCheckWithOtherModel)
                .disabled(!settings.verifyBeforeDone)
        } header: {
            Text("Independent Check")
        } footer: {
            Text("When the agent claims success a separate check looks at a fresh screenshot, with no access to the agent's own reasoning, and confirms, corrects, or rejects it. A rejected claim sends the agent back to work with the objection. One extra call per claimed success.")
        }
    }

    private var strategySection: some View {
        @Bindable var settings = settings
        return Section {
            Picker("Model strategy", selection: $settings.modelStrategy) {
                ForEach(ModelStrategy.allCases) { strategy in
                    Text(strategy.label).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            Text(settings.modelStrategy.caption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text("Model Strategy")
        } footer: {
            Text("Auto reads how hard each moment is — look-alike targets, blocking overlays, a move that got no reaction, a stuck task — and sends only the easy ones to the fast model. Every step card shows which model decided it, so the split is never a mystery.")
        }
    }

    /// The free tier, with the device situation stated in plain words rather than
    /// buried — including the three reasons it might not be available.
    private var freeTierSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Use my iPhone's model first", isOn: $settings.onDeviceFirst)
                .disabled(!onDevice.isReady)
            HStack(spacing: 7) {
                Image(systemName: onDevice.state.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(onDevice.isReady ? Theme.green : Theme.amber)
                Text(onDevice.state.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(onDevice.state.caption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text("Free — On Your iPhone")
        } footer: {
            Text("Routine steps go to Apple's on-device model: free, offline, and nothing leaves the phone. Its answers are never trusted blind — the app checks the element exists, is reachable and is safe before any of them touch the page, and hands the step to the cloud if anything is off. The hard calls, the plan, the fact-check and anything irreversible always stay with the frontier model.")
        }
    }

    /// Memory, and the honest statement of what gates it.
    private var memorySection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Remember routes that work", isOn: $settings.memoryEnabled)
            Toggle("Replay known opening moves", isOn: $settings.headStartEnabled)
                .disabled(!settings.memoryEnabled)
            Button(role: .destructive) {
                confirmForget = true
            } label: {
                Text("Forget all learned routes")
            }
            .disabled(vault.isEmpty)
        } header: {
            Text("Memory")
        } footer: {
            Text(verifyBeforeDone
                 ? "After a success the independent check confirms, the route that worked is written down on this device — which field to use, never what you typed. A recognised mission then replays up to three opening moves with no decision to pay for, stopping the moment the page stops matching. \(vault.isEmpty ? "Nothing learned yet." : "\(vault.recipes.count) route\(vault.recipes.count == 1 ? "" : "s") learned so far.")"
                 : "Memory needs the independent check, because only a confirmed success is allowed to teach the agent anything. Turn Verify before done back on to learn routes.")
        }
    }

    /// Learning from failure, and the honest statement of what it costs: nothing.
    private var lessonsSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Learn from failures", isOn: $settings.lessonsEnabled)
            Button(role: .destructive) {
                confirmForgetLessons = true
            } label: {
                Text("Clear what went wrong")
            }
            .disabled(lessonBook.isEmpty)
        } header: {
            Text("Lessons")
        } footer: {
            Text("When a run goes wrong the app writes down the KIND of problem — a banner that has to go first, a button that does nothing, a page that looks finished when it isn't — and quietly warns the next run on that site. Grouped by kind, never one note per bad day, and no paid call is ever made to learn one. A caution that stops matching the site is doubted and then dropped, so an out-of-date warning cannot keep costing you missions. \(lessonBook.isEmpty ? "Nothing learned yet." : "\(lessonBook.lessons.count) caution\(lessonBook.lessons.count == 1 ? "" : "s") on this device.")")
        }
    }

    /// One-tap replays and the repair ladder.
    private var replaySection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Let replays repair themselves", isOn: $settings.selfHealEnabled)
            Button(role: .destructive) {
                confirmForgetRoutines = true
            } label: {
                Text("Delete all one-tap replays")
            }
            .disabled(routines.isEmpty)
        } header: {
            Text("One-Tap Replays")
        } footer: {
            Text("After a confirmed success you can save the run as a replay you launch with one tap. Anything you typed becomes a blank it asks for — the value is never stored. When a site moves a control, the step is matched to where it went (free on your iPhone where possible, otherwise one small paid call chosen strictly from elements that really are on the page) and the fix is written back, so the next run is clean. Any step that submits, buys, sends or deletes always stops for a yes. Off makes replays strict: any mismatch hands straight over to the agent. \(routines.isEmpty ? "Nothing saved yet." : "\(routines.routines.count) saved.")")
        }
    }

    /// Your own details, and the honest statement of what filling a form from
    /// them costs: almost nothing.
    private var dossierSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Fill forms from my details", isOn: $settings.dossierEnabled)
            Button {
                showDossier = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(dossier.isEmpty ? "Set up your dossier" : "Your dossier — \(dossier.filledCount) details")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(Theme.cyan)
            }
        } header: {
            Text("Your Details")
        } footer: {
            Text("Fill in your name, contacts, address, work history and the questions long applications ask — once, behind \(DossierGuard.methodName()) — and the agent fills a whole form in one move. Fields are matched for free: most declare what they want in the page's own markup, the rest are read from their labels, and only genuinely odd ones ever reach a paid call. The agent is told which details exist, never what they say, and a field with nothing stored for it is left blank rather than invented. No box exists for a password, a card or a security code, so it can never type one.")
        }
    }

    private var verifyBeforeDone: Bool { settings.verifyBeforeDone }

    private var judgmentSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Weigh alternatives on hard steps", isOn: $settings.weighAlternatives)
            Toggle("Checkpoints and rewind", isOn: $settings.bookmarksEnabled)
            Toggle("Hand the browser to me at walls", isOn: $settings.handOverEnabled)
        } header: {
            Text("Judgment")
        } footer: {
            Text("On hard steps the agent drafts 2-4 possible moves in one reply and the app scores them against the live page before playing the best — no extra calls. Checkpoints save the page before branching moves so the agent can go back out of a dead end, up to three times per mission. A checkpoint restores the page, not text already typed into a form. With hand-over on, a sign-in, verification or code the agent cannot get past pauses the run so you can do that part yourself; off, the agent keeps working the page's own route until its step budget runs out.")
        }
    }

    private var modelSection: some View {
        Section {
            ForEach(ModelChoice.cloudCases) { choice in
                SettingsModelRow(choice: choice, isSelected: settings.model == choice) {
                    settings.model = choice
                }
            }
        } header: {
            Text("Preferred Model")
        } footer: {
            Text("Used for normal steps under Auto, and for every step when the strategy is Always. Each step sends one page snapshot and uses a small amount of Rork AI Cloud credits.")
        }
    }

    private var benchmarkSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Benchmark mode", isOn: $settings.benchmarkMode)
        } header: {
            Text("Benchmark")
        } footer: {
            Text("The strongest unattended setup: every step on the precise model at medium thinking effort, no on-device tier, at least \(AppSettings.benchmarkMinSteps) steps, the independent check always on, and no hand-over. Slower and costlier per step, fewer wrong turns.")
        }
    }

    private var gatewaySection: some View {
        Section {
            Text(gatewayProfile.summary)
                .font(.footnote)
            ForEach(gatewayReport, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                probing = true
                Task {
                    let report = await AIService().probeGateway()
                    report.profile.save()
                    gatewayProfile = report.profile
                    gatewayReport = report.lines
                    probing = false
                }
            } label: {
                HStack {
                    Text(probing ? "Testing…" : "Test what the gateway supports")
                    if probing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(probing)
        } header: {
            Text("AI Gateway")
        } footer: {
            Text("Makes about six small calls to the precise model to see whether thinking effort and prompt caching reach Claude through the gateway. Only what passes is used. Temperature is never sent to Claude.")
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Text("Clear run history")
            }
            .disabled(history.runs.isEmpty)
        } header: {
            Text("Data")
        } footer: {
            Text(history.runs.isEmpty ? "No saved runs." : "\(history.runs.count) saved runs on this device.")
        }
    }

    private var limitsSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("Honest limits: sites with strong bot protection or CAPTCHAs may resist automation, and third-party embedded frames inside pages can be off-limits. The agent will tell you when a site fights back.")
        }
    }
}
