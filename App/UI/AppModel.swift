import Foundation
import Observation
import VigorDesign
import VigorHealth
import VigorScoring

/// 界面的数据来源：模拟器使用固定日期的合成数据（截图可复现），真机使用 SwiftData 中的周期记录。
@MainActor
@Observable
final class AppModel {
    private(set) var cycles: [CycleResult] = []
    private(set) var output: PipelineOutput?
    private(set) var snapshot: HealthSnapshot?
    private(set) var journal: [JournalEntry] = []
    private(set) var lastUpdated: Date?
    var message: String?

    static let syntheticEnd: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        // 中午结束：当天有醒着的数据，负荷不为零
        components.hour = 12
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }()

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    var today: CycleResult? { cycles.last }

    func load(source: DataSourceKind) async {
        #if targetEnvironment(simulator)
        if source == .synthetic {
            loadSynthetic()
            return
        }
        #endif
        if source == .live {
            await loadFromStore()
        } else {
            loadSynthetic()
        }
    }

    func loadSynthetic() {
        let scenario = SyntheticScenario.make(nights: 120, seed: 42, endingAt: Self.syntheticEnd, calendar: calendar)
        var config = ScoringConfig.default
        config.configVersion = 1
        let output = ScoringPipeline.run(PipelineInput(
            snapshot: scenario.snapshot,
            journal: scenario.journal,
            baseSleepNeedHours: AppSettings.baseSleepNeedHours,
            maxHeartRate: AppSettings.maxHeartRateOverride,
            targetWakeMinutes: AppSettings.targetWakeMinutes,
            config: config,
            now: Self.syntheticEnd,
            calendar: calendar
        ))
        self.output = output
        self.snapshot = scenario.snapshot
        self.journal = scenario.journal
        self.cycles = output.cycles
        self.lastUpdated = Self.syntheticEnd
        self.message = "演示数据：合成场景，结束于 2026-10-01 12:00"
    }

    private func loadFromStore() async {
        let environment = AppBootstrap.shared.environment
        guard let repository = environment.repository else {
            message = environment.setupError ?? "存储未就绪"
            return
        }
        await AppBootstrap.shared.refreshNow()
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -180, to: now) ?? now
        do {
            cycles = try await repository.cycles(from: start, to: now)
            lastUpdated = now
            message = cycles.isEmpty ? "还没有数据，请先完成授权与同步" : nil
        } catch {
            message = error.localizedDescription
        }
    }
}
