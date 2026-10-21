import Foundation
import VigorScoring

/// 发送给教练的脱敏每日汇总（PRD §6.10、施工文档 §5 阶段 9）：只有分数、z-score、日志项与趋势。
/// 不含原始样本、心跳序列，也不含时间戳精度以外的信息。
public struct DailySummary: Codable, Sendable, Hashable {
    public var day: String
    public var recovery: Int?
    public var recoveryZone: String?
    public var strain: Double
    public var targetLower: Int?
    public var targetUpper: Int?
    public var sleepScore: Int
    public var sleepHours: Double
    public var sleepRegularity: Int?
    public var zHRV: Double?
    public var zRestingHeartRate: Double?
    public var debtHours: Double
    public var illness: String
    public var journal: [String]
    public var trend: String?
    public var recoveryState: String

    public init(
        day: String,
        recovery: Int?,
        recoveryZone: String?,
        strain: Double,
        targetLower: Int?,
        targetUpper: Int?,
        sleepScore: Int,
        sleepHours: Double,
        sleepRegularity: Int?,
        zHRV: Double?,
        zRestingHeartRate: Double?,
        debtHours: Double,
        illness: String,
        journal: [String],
        trend: String?,
        recoveryState: String
    ) {
        self.day = day
        self.recovery = recovery
        self.recoveryZone = recoveryZone
        self.strain = strain
        self.targetLower = targetLower
        self.targetUpper = targetUpper
        self.sleepScore = sleepScore
        self.sleepHours = sleepHours
        self.sleepRegularity = sleepRegularity
        self.zHRV = zHRV
        self.zRestingHeartRate = zRestingHeartRate
        self.debtHours = debtHours
        self.illness = illness
        self.journal = journal
        self.trend = trend
        self.recoveryState = recoveryState
    }
}

public enum SummaryBuilder {
    /// 从一个周期生成脱敏汇总。日期只保留到日。
    public static func daily(from cycle: CycleResult, journal: JournalEntry?, calendar: Calendar) -> DailySummary {
        let day = String(format: "%04d-%02d-%02d", cycle.wakeDay.year ?? 0, cycle.wakeDay.month ?? 0, cycle.wakeDay.day ?? 0)
        let behaviors = (journal?.behaviors ?? [:]).filter(\.value).keys.sorted()
        return DailySummary(
            day: day,
            recovery: cycle.recovery.map { Int($0.score.rounded()) },
            recoveryZone: cycle.recovery.map { $0.zone.rawValue },
            strain: (cycle.load.strain * 10).rounded() / 10,
            targetLower: cycle.loadTarget.map { Int($0.lower) },
            targetUpper: cycle.loadTarget.map { Int($0.upper) },
            sleepScore: Int(cycle.sleepScore.score.rounded()),
            sleepHours: (cycle.sleepMetrics.totalSleepHours * 10).rounded() / 10,
            sleepRegularity: cycle.sri.map { Int(max(0, $0).rounded()) },
            zHRV: cycle.zHRV.map { ($0 * 100).rounded() / 100 },
            zRestingHeartRate: cycle.zRHR.map { ($0 * 100).rounded() / 100 },
            debtHours: (cycle.debtAfterNight * 10).rounded() / 10,
            illness: cycle.illness.rawValue,
            journal: behaviors,
            trend: cycle.trend.map { $0.state.rawValue },
            recoveryState: cycle.recoveryState.rawValue
        )
    }
}
