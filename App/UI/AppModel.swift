import Foundation
import Observation
import VigorDesign
import VigorHealth
import VigorScoring
import VigorStore

enum JournalSaveError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? {
        "数据存储未就绪，请稍后重试。"
    }
}

/// 界面的数据来源：模拟器使用固定日期的合成数据（截图可复现），真机使用 SwiftData 中的周期记录。
@MainActor
@Observable
final class AppModel {
    private(set) var cycles: [CycleResult] = []
    private(set) var output: PipelineOutput?
    /// 当前生效的评分配置（实验室的对比与采用以它为基准）
    private(set) var config: ScoringConfig = .default
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

    /// 界面使用的日历（日志的醒来日、洞察与周报都按它划分日期）
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    var today: CycleResult? { cycles.last }

    /// 影响洞察（按效应量排序）。
    var insights: [JournalInsight] {
        JournalInsights.compute(cycles: cycles, journal: journal, calendar: calendar)
    }

    /// 亮点：固定规则生成（D-067）。
    var highlights: [Highlight] {
        Highlights.make(cycles: cycles)
    }

    /// 本月的月报（包含今天）。
    var monthlyReport: PeriodReport? {
        ReportBuilder.month(containing: today?.wakeTime ?? Date(), cycles: cycles, journal: journal, calendar: calendar)
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

    /// 当前数据来源，决定保存日志后是否从 SwiftData 重新读取
    private(set) var source: DataSourceKind = .synthetic

    /// 实验室采用新配置后，用重算的结果替换当前界面数据。
    func apply(_ output: PipelineOutput, config: ScoringConfig) {
        self.output = output
        self.cycles = output.cycles
        self.config = config
    }

    /// 某个醒来日的日志（本地零点）。
    func journalEntry(on night: Date) -> JournalEntry? {
        journal.first { $0.night == night }
    }

    /// 日志页“自动填充”的只读值，取醒来日前一天的健康数据。
    func autoFill(for night: Date) -> JournalAutoFill {
        JournalAutoFill.summarize(snapshot, night: night, calendar: calendar)
    }

    /// 保存一天的日志：先写入 SwiftData，界面立即更新，然后在后台刷新分数（洞察与生病预警随之生效）。
    func saveJournal(_ entry: JournalEntry) async throws {
        guard let repository = AppBootstrap.shared.environment.repository else {
            throw JournalSaveError.storeUnavailable
        }
        try await repository.saveJournal(entry)
        journal.removeAll { $0.night == entry.night }
        journal.append(entry)
        journal.sort { $0.night < $1.night }
        Task {
            await AppBootstrap.shared.refreshNow()
            await reloadStored()
        }
    }

    /// 从 SwiftData 重新读取（只在真机数据来源下有意义；合成数据不会被覆盖）。
    private func reloadStored() async {
        guard source == .live, let repository = AppBootstrap.shared.environment.repository else { return }
        await reloadFromStore(repository: repository)
    }

    func load(source: DataSourceKind) async {
        self.source = source
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
        self.config = config
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
        // 先显示上次保存的结果，再在后台刷新，避免打开 App 时等待 HealthKit 读取
        await reloadFromStore(repository: repository)
        await AppBootstrap.shared.refreshNow()
        await reloadFromStore(repository: repository)
    }

    private func reloadFromStore(repository: ScoreRepository) async {
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -180, to: now) ?? now
        do {
            config = try await repository.currentConfig() ?? .default
            cycles = try await repository.cycles(from: start, to: now)
            journal = try await repository.journal(from: start, to: now)
            snapshot = await AppBootstrap.shared.environment.sync?.cachedSnapshot()
            lastUpdated = now
            message = cycles.isEmpty ? "还没有数据，请先完成授权与同步" : nil
        } catch {
            message = error.localizedDescription
        }
    }
}
