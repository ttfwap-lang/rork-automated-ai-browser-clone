import SwiftUI

@main
struct AutomatedAIBrowserApp: App {
    @State private var settings: AppSettings
    @State private var historyStore: HistoryStore
    @State private var onDevice: OnDeviceModel
    @State private var vault: RecipeVault
    @State private var lessonBook: LessonBook
    @State private var routines: RoutineStore
    @State private var dossier: Dossier
    @State private var agent: AgentViewModel

    init() {
        let settings = AppSettings()
        let historyStore = HistoryStore()
        let onDevice = OnDeviceModel()
        let vault = RecipeVault()
        let lessonBook = LessonBook()
        let routines = RoutineStore()
        let dossier = Dossier()
        _settings = State(initialValue: settings)
        _historyStore = State(initialValue: historyStore)
        _onDevice = State(initialValue: onDevice)
        _vault = State(initialValue: vault)
        _lessonBook = State(initialValue: lessonBook)
        _routines = State(initialValue: routines)
        _dossier = State(initialValue: dossier)
        _agent = State(initialValue: AgentViewModel(
            settings: settings,
            history: historyStore,
            onDevice: onDevice,
            vault: vault,
            lessons: lessonBook,
            routines: routines,
            dossier: dossier
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(historyStore)
                .environment(onDevice)
                .environment(vault)
                .environment(lessonBook)
                .environment(routines)
                .environment(dossier)
                .environment(agent)
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
        }
    }
}
