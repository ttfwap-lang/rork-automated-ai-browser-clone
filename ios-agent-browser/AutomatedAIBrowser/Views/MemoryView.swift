import SwiftUI

/// The sites the agent has learned, newest first. Nothing here is required to
/// use the app — it exists so a memory is never a black box: whatever the agent
/// recalled silently, you can read, rename, or delete.
struct MemoryView: View {
    @Environment(RecipeVault.self) private var vault
    @Environment(AppSettings.self) private var settings
    @Environment(OnDeviceModel.self) private var onDevice
    @Environment(LessonBook.self) private var lessonBook
    @Environment(RoutineStore.self) private var routines
    @Environment(\.dismiss) private var dismiss
    @State private var confirmWipe = false

    /// True when there is genuinely nothing to show: no routes, no cautions, no
    /// saved replays.
    private var hasNothing: Bool {
        vault.isEmpty && lessonBook.isEmpty && routines.isEmpty
    }

    /// Sites the notebook knows about but the vault does not — a site can teach
    /// the agent something without ever having handed it a route that worked.
    private var lessonOnlySites: [(host: String, lessons: [SiteLesson])] {
        let known = Set(vault.sites.map { $0.host })
        return lessonBook.sites.filter { !known.contains($0.host) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasNothing {
                    emptyState
                } else {
                    siteList
                }
            }
            .background(Theme.bg)
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !hasNothing {
                        Button("Forget All", role: .destructive) {
                            confirmWipe = true
                        }
                        .foregroundStyle(Theme.red)
                    }
                }
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
            .navigationDestination(for: SiteRecipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .navigationDestination(for: Routine.self) { routine in
                RoutineDetailView(routine: routine)
            }
            .confirmationDialog("Forget everything learned?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Forget All", role: .destructive) {
                    vault.wipe()
                    lessonBook.wipe()
                    Haptics.warning()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears learned routes and everything learned from failures. Saved one-tap replays are kept — delete those individually.")
            }
        }
    }

    private var siteList: some View {
        @Bindable var settings = settings
        return List {
            Section {
                Toggle("Remember routes that work", isOn: $settings.memoryEnabled)
                Toggle("Replay known opening moves", isOn: $settings.headStartEnabled)
                    .disabled(!settings.memoryEnabled)
            } header: {
                Text("Memory")
            } footer: {
                Text(settings.memoryEnabled
                     ? "After a success the independent check confirms, the route that worked is written down here — on your device. Nothing you typed is ever stored."
                     : "Memory is off. Nothing is recalled and nothing new is written down.")
            }
            .listRowBackground(Theme.surface)

            if !routines.isEmpty {
                Section {
                    ForEach(routines.ordered) { routine in
                        NavigationLink(value: routine) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(routine.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if routine.healCount > 0 {
                                        Text("REPAIRED \(routine.healCount)×")
                                            .techLabel(8)
                                            .foregroundStyle(Theme.green)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Theme.green.opacity(0.12), in: Capsule())
                                    }
                                }
                                Text(routine.subtitle)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.textSecondary)
                                Text(routine.host.uppercased())
                                    .techLabel(8)
                                    .foregroundStyle(Theme.cyan.opacity(0.8))
                            }
                            .padding(.vertical, 3)
                        }
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.line)
                    }
                } header: {
                    Text("One-Tap Replays")
                } footer: {
                    Text("Saved runs you can launch again with one tap. Each asks you for anything that has to be typed, because the value itself is never stored.")
                }
            }

            ForEach(vault.sites, id: \.host) { site in
                Section {
                    ForEach(site.recipes) { recipe in
                        NavigationLink(value: recipe) {
                            MemorySiteRow(recipe: recipe)
                        }
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.line)
                    }
                    ForEach(lessonBook.lessons(for: site.host)) { lesson in
                        LessonRow(lesson: lesson)
                            .listRowBackground(Theme.surface)
                            .listRowSeparatorTint(Theme.line)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    lessonBook.delete(lesson.id)
                                    Haptics.warning()
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(site.host)
                        Spacer()
                        Button("Forget") {
                            Haptics.warning()
                            vault.forget(host: site.host)
                            lessonBook.forget(host: site.host)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    }
                }
            }

            ForEach(lessonOnlySites, id: \.host) { site in
                Section {
                    ForEach(site.lessons) { lesson in
                        LessonRow(lesson: lesson)
                            .listRowBackground(Theme.surface)
                            .listRowSeparatorTint(Theme.line)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    lessonBook.delete(lesson.id)
                                    Haptics.warning()
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(site.host)
                        Spacer()
                        Button("Forget") {
                            Haptics.warning()
                            lessonBook.forget(host: site.host)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    }
                } footer: {
                    Text("Learned the hard way — no route here has been proven yet.")
                }
            }

            if !onDevice.isReady {
                Section {
                    EmptyView()
                } footer: {
                    Text("Routes are written down using your iPhone's own model when it's available. \(onDevice.state.caption)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textSecondary)
            Text("Nothing learned yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("When a mission succeeds and the independent check confirms it, the route that worked is written down here. The next mission on that site starts with a head start.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
