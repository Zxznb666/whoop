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

    /// 影响洞察（按效应量排序）。
    var insights: [JournalInsight] {
        JournalInsights.compute(cycles: cycles, journal: journal, calendar: calendar)
    }

    /// 最近一周的周报（包含今天）。
    var weeklyReport: PeriodReport? {
        ReportBuilder.week(containing: today?.wakeTime ?? Date(), cycles: cycles, journal: journal, calendar: calendar)
    }

    /// 身体年龄的输入：取最新的 VO2max、夜间静息心率基线、HRV 基线与先验、SRI、近 30 天日均步数与近 7 天 Z2+ 分钟。
    var bodyAge: BodyAgeResult? {
        guard let today, let snapshot else { return nil }
        let year = calendar.component(.year, from: today.wakeTime)
        let birthYear = snapshot.profile.birthYear
        let chronological = birthYear.map { year - $0 } ?? 35
        let lnPrior = PopulationPriors.prior(for: .lnRMSSDNight, profile: snapshot.profile, year: year).mu
        let steps = snapshot.steps.filter { $0.start >= today.wakeTime.addingTimeInterval(-30 * 86_400) }
        let dailySteps = steps.isEmpty ? nil : steps.reduce(0) { $0 + $1.value } / 30
        let zone2 = cycles.suffix(7).reduce(0.0) { $0 + Double($1.load.zoneMinutes.dropFirst().reduce(0, +)) }
        let inputs = BodyAgeInputs(
            vo2Max: snapshot.vo2Max.last?.value,
            restingHeartRateBaseline: today.baselines[.restingHeartRate]?.mu,
            lnRMSSDBaseline: today.baselines[.lnRMSSDNight]?.mu,
            lnRMSSDPrior: lnPrior,
            sri: today.sri,
            dailySteps: dailySteps,
            weeklyZone2PlusMinutes: zone2 > 0 ? zone2 : nil
        )
        return BodyAge.compute(chronologicalAge: chronological, sex: snapshot.profile.sex, inputs: inputs)
    }

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
