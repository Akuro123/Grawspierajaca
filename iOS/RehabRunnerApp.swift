import SwiftUI
import SwiftData

enum Route: Hashable {
    case profile, calibration, game, demo, summary, stats, reminders, settings, diagnostics
}

@MainActor
final class Router: ObservableObject {
    @Published var path: [Route] = []
    func push(_ r: Route) { path.append(r) }
    func showSummary() { path = [.summary] }
    func home() { path = [] }
}

@main
struct RehabRunnerApp: App {
    @StateObject private var controller = SessionController()
    @StateObject private var router = Router()
    @StateObject private var reminders = ReminderStore()
    private let container: ModelContainer = {
        do { return try ModelContainer(for: ExerciseSessionRecord.self, PatientProfile.self) }
        catch { fatalError("Nie można utworzyć magazynu danych: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .environmentObject(router)
                .environmentObject(reminders)
                .modelContainer(container)
                .onAppear {
                    controller.modelContext = container.mainContext
                    #if DEBUG
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-debugDemo") {
                        controller.startDemo(); router.push(.demo)
                        if let i = args.firstIndex(of: "-debugPose"), i + 1 < args.count { controller.scene?.forcedPose = args[i + 1] }
                        if let i = args.firstIndex(of: "-debugAction"), i + 1 < args.count {
                            let name = args[i + 1]
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(3.0))
                                switch name {
                                case "jump": controller.perform(.jump)
                                case "slide": controller.perform(.slide)
                                case "crouch": controller.perform(.crouchBegan)
                                case "left": controller.perform(.moveLeft)
                                default: break
                                }
                            }
                        }
                        if let i = args.firstIndex(of: "-debugZone"), i + 1 < args.count, let n = Int(args[i + 1]), let z = Zone(rawValue: n) { controller.debugSetZone(z) }
                    }
                    if args.contains("-debugExercise") { controller.beginExercise(requireWatch: false); router.push(.game) }
                    if args.contains("-debugHistory") { router.push(.stats) }
                    if args.contains("-debugProfile") { router.push(.profile) }
                    if args.contains("-debugDiagnostics") { router.push(.diagnostics) }
                    #endif
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router
    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .profile: ProfileView()
                    case .calibration: CalibrationView()
                    case .game: GameView(demo: false)
                    case .demo: GameView(demo: true)
                    case .summary: SummaryView()
                    case .stats: StatsView()
                    case .settings: SettingsView()
                    case .diagnostics: DiagnosticsView()
                    case .reminders: RemindersView()
                    }
                }
        }
    }
}
