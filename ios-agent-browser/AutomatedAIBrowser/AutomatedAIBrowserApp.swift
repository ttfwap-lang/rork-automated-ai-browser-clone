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
    @State private var plugins: PluginManager
    @State private var agent: AgentViewModel

    init() {
        let settings = AppSettings()
        let historyStore = HistoryStore()
        let onDevice = OnDeviceModel()
        let vault = RecipeVault()
        let lessonBook = LessonBook()
        let routines = RoutineStore()
        let dossier = Dossier()
        let plugins = PluginManager()
        _settings = State(initialValue: settings)
        _historyStore = State(initialValue: historyStore)
        _onDevice = State(initialValue: onDevice)
        _vault = State(initialValue: vault)
        _lessonBook = State(initialValue: lessonBook)
        _routines = State(initialValue: routines)
        _dossier = State(initialValue: dossier)
        _plugins = State(initialValue: plugins)
        _agent = State(initialValue: AgentViewModel(
            settings: settings,
            history: historyStore,
            onDevice: onDevice,
            vault: vault,
            lessons: lessonBook,
            routines: routines,
            dossier: dossier,
            plugins: plugins
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
                .environment(plugins)
                .environment(agent)
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
        }
    }
}
