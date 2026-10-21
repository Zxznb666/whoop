import SwiftUI
import VigorDesign
import VigorHealth
import VigorScoring

/// 页面路由（PRD §4）。截图脚本用 `-VigorRoute` 直接打开其中一个。
enum Route: Hashable {
    case recovery
    case sleep
    case strain
    case workout(UUID)
    case metric(MetricKind)
    case browse
    case journal
    case journalEdit(Date)
    case journalQuestions
    case report
    case coach
    case settings
    case lab
    case labNight
    case diagnostics
    case onboarding

    /// 路由所属的标签页。
    var tab: AppTab {
        switch self {
        case .recovery, .settings, .lab, .labNight, .diagnostics, .onboarding: .summary
        case .sleep: .sleep
        case .strain, .workout: .strain
        case .journal, .journalEdit: .journal
        case .journalQuestions: .summary
        case .metric, .browse, .report, .coach: .browse
        }
    }

    static func parse(_ text: String) -> Route? {
        switch text {
        case "recovery": .recovery
        case "sleep": .sleep
        case "strain": .strain
        case "workout": .workout(UUID())
        case "metric:hrv": .metric(.hrv)
        case "metric:rhr": .metric(.restingHeartRate)
        case "browse": .browse
        case "journal": .journal
        case "journal:edit": .journalEdit(Calendar.current.startOfDay(for: Date()))
        case "journal:questions": .journalQuestions
        case "report": .report
        case "coach": .coach
        case "settings": .settings
        case "lab": .lab
        case "lab:night": .labNight
        case "diagnostics": .diagnostics
        case "onboarding": .onboarding
        default: nil
        }
    }
}

enum AppTab: Hashable, CaseIterable {
    case summary, sleep, strain, journal, browse

    var title: String {
        switch self {
        case .summary: "摘要"
        case .sleep: "睡眠"
        case .strain: "负荷"
        case .journal: "日志"
        case .browse: "浏览"
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "heart.text.square"
        case .sleep: "bed.double"
        case .strain: "flame"
        case .journal: "square.and.pencil"
        case .browse: "square.grid.2x2"
        }
    }
}

struct RootView: View {
    @State private var model = AppModel()
    @State private var selection: AppTab = .summary
    @State private var paths: [AppTab: [Route]] = [:]
    @State private var source: DataSourceKind = {
        #if targetEnvironment(simulator)
        .synthetic
        #else
        .live
        #endif
    }()

    private let launchRoute: Route?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-VigorRoute"), arguments.indices.contains(index + 1) {
            launchRoute = Route.parse(arguments[index + 1])
        } else {
            launchRoute = nil
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                NavigationStack(path: binding(for: tab)) {
                    tabRoot(tab)
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(route: route, model: model)
                        }
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }
        }
        .task {
            if let launchRoute {
                selection = launchRoute.tab
                paths[launchRoute.tab] = [launchRoute]
            }
            await model.load(source: source)
        }
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .summary: SummaryView(model: model)
        case .sleep: SleepView(model: model)
        case .strain: StrainView(model: model)
        case .journal: JournalView(model: model)
        case .browse: BrowseView(model: model)
        }
    }

    private func binding(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { paths[tab] ?? [] },
            set: { paths[tab] = $0 }
        )
    }
}

/// 路由到页面的唯一映射。
struct RouteDestination: View {
    let route: Route
    let model: AppModel

    var body: some View {
        switch route {
        case .recovery: RecoveryDetailView(model: model)
        case .sleep: SleepView(model: model)
        case .strain: StrainView(model: model)
        case .workout: WorkoutListView(model: model)
        case .metric(let kind): MetricDetailView(model: model, kind: kind)
        case .browse: BrowseView(model: model)
        case .journal: JournalView(model: model)
        case .journalEdit(let night): JournalEditView(model: model, night: night)
        case .journalQuestions: JournalQuestionsView()
        case .report: ReportView(model: model)
        case .coach: CoachView(model: model)
        case .settings: SettingsView()
        case .lab, .labNight: LabRootView(model: LabModel(source: .synthetic), app: model)
        case .diagnostics: DiagnosticsView()
        case .onboarding: OnboardingView()
        }
    }
}
