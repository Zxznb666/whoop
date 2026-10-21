import Foundation

/// 睡眠基础指标（PRD §5.9.1）。时长单位：分钟，TST 另给小时。
public struct SleepMetrics: Sendable, Hashable, Codable {
    /// 睡着时长 TST（小时）
    public var totalSleepHours: Double
    /// 睡眠效率 0–1；没有在床数据时为“睡眠期效率”
    public var efficiency: Double
    public var efficiencyIsSleepPeriod: Bool
    /// 入睡耗时（分钟），需要在床数据
    public var sleepLatencyMinutes: Double?
    /// 夜间清醒 WASO（分钟）
    public var wasoMinutes: Double
    /// 觉醒次数（持续 ≥ 2 分钟的清醒段）
    public var awakenings: Int
    /// REM 潜伏期（分钟）
    public var remLatencyMinutes: Double?
    /// 修复性睡眠：深睡 + REM（小时）及其占 TST 的比例
    public var restorativeHours: Double
    public var restorativeFraction: Double

    public init(
        totalSleepHours: Double,
        efficiency: Double,
        efficiencyIsSleepPeriod: Bool,
        sleepLatencyMinutes: Double?,
        wasoMinutes: Double,
        awakenings: Int,
        remLatencyMinutes: Double?,
        restorativeHours: Double,
        restorativeFraction: Double
    ) {
        self.totalSleepHours = totalSleepHours
        self.efficiency = efficiency
        self.efficiencyIsSleepPeriod = efficiencyIsSleepPeriod
        self.sleepLatencyMinutes = sleepLatencyMinutes
        self.wasoMinutes = wasoMinutes
        self.awakenings = awakenings
        self.remLatencyMinutes = remLatencyMinutes
        self.restorativeHours = restorativeHours
        self.restorativeFraction = restorativeFraction
    }
}

public enum SleepMetricsCalculator {
    public static func make(
        session: SleepSession,
        bedtime: Date?,
        config: ScoringConfig = .default
    ) -> SleepMetrics {
        let tst = session.asleepDuration
        let onset = session.start
        let wake = session.end
        let inBed = bedtime.flatMap { $0 <= onset ? $0 : nil }

        let efficiencyDenominator = (inBed ?? onset).distance(to: wake)
        let efficiency = efficiencyDenominator > 0 ? tst / efficiencyDenominator : 0

        let restorative = session.stages
            .filter { $0.stage == .deep || $0.stage == .rem }
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }

        let remStart = session.stages.first { $0.stage == .rem }?.start
        return SleepMetrics(
            totalSleepHours: tst / 3600,
            efficiency: efficiency,
            efficiencyIsSleepPeriod: inBed == nil,
            sleepLatencyMinutes: inBed.map { onset.timeIntervalSince($0) / 60 },
            wasoMinutes: max(0, (wake.timeIntervalSince(onset) - tst) / 60),
            awakenings: SleepEvents.awakeningCount(in: session, config: config),
            remLatencyMinutes: remStart.map { $0.timeIntervalSince(onset) / 60 },
            restorativeHours: restorative / 3600,
            restorativeFraction: tst > 0 ? restorative / tst : 0
        )
    }
}
