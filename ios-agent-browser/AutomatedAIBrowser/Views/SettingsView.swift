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
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var confirmForget = false
    @State private var confirmForgetLessons = false
    @State private var confirmForgetRoutines = false

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                railsSection
                planningSection
                checkSection
                strategySection
                freeTierSection
                memorySection
                lessonsSection
                replaySection
                judgmentSection
                modelSection
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
            Stepper("Max steps per run: \(settings.maxSteps)", value: $settings.maxSteps, in: 5...25)
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

    private var verifyBeforeDone: Bool { settings.verifyBeforeDone }

    private var judgmentSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Weigh alternatives on hard steps", isOn: $settings.weighAlternatives)
            Toggle("Checkpoints and rewind", isOn: $settings.bookmarksEnabled)
        } header: {
            Text("Judgment")
        } footer: {
            Text("On hard steps the agent drafts 2-4 possible moves in one reply and the app scores them against the live page before playing the best — no extra calls. Checkpoints save the page before branching moves so the agent can go back out of a dead end, up to three times per mission. A checkpoint restores the page, not text already typed into a form.")
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
