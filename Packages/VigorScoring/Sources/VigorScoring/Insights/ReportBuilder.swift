import Foundation

/// 周报与月报的数据（PRD §6.7）。纯函数：同样的周期与日期得到同样的报告。
public struct PeriodReport: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case week
        case month
    }

    public var kind: Kind
    public var start: Date
    public var end: Date
    public var cycleCount: Int
    public var meanRecovery: Double?
    public var meanStrain: Double?
    public var meanSleepScore: Double?
    public var bestRecoveryDay: Date?
    public var worstRecoveryDay: Date?
    public var workoutCount: Int
    public var totalStrain: Double
    /// 周期末睡眠负债减去周期初（小时）
    public var debtChangeHours: Double?
    public var topInsights: [JournalInsight]

    public init(
        kind: Kind,
        start: Date,
        end: Date,
        cycleCount: Int,
        meanRecovery: Double?,
        meanStrain: Double?,
        meanSleepScore: Double?,
        bestRecoveryDay: Date?,
        worstRecoveryDay: Date?,
        workoutCount: Int,
        totalStrain: Double,
        debtChangeHours: Double?,
        topInsights: [JournalInsight]
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.cycleCount = cycleCount
        self.meanRecovery = meanRecovery
        self.meanStrain = meanStrain
        self.meanSleepScore = meanSleepScore
        self.bestRecoveryDay = bestRecoveryDay
        self.worstRecoveryDay = worstRecoveryDay
        self.workoutCount = workoutCount
        self.totalStrain = totalStrain
        self.debtChangeHours = debtChangeHours
        self.topInsights = topInsights
    }
}

public enum ReportBuilder {
    /// 包含 `date` 的那一周（周一 00:00 至下周一 00:00，本地时间）。
    public static func week(containing date: Date, cycles: [CycleResult], journal: [JournalEntry], calendar: Calendar) -> PeriodReport? {
        var calendar = calendar
        calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        return build(kind: .week, interval: interval, cycles: cycles, journal: journal, calendar: calendar)
    }

    /// 包含 `date` 的那一个自然月。
    public static func month(containing date: Date, cycles: [CycleResult], journal: [JournalEntry], calendar: Calendar) -> PeriodReport? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        return build(kind: .month, interval: interval, cycles: cycles, journal: journal, calendar: calendar)
    }

    static func build(
        kind: PeriodReport.Kind,
        interval: DateInterval,
        cycles: [CycleResult],
        journal: [JournalEntry],
        calendar: Calendar
    ) -> PeriodReport {
        let inside = cycles.filter { interval.contains($0.wakeTime) }
        let recoveries = inside.compactMap { cycle in cycle.recovery.map { (cycle.wakeTime, $0.score) } }
        let best = recoveries.max { $0.1 < $1.1 }?.0
        let worst = recoveries.min { $0.1 < $1.1 }?.0
        let workouts = inside.flatMap(\.load.workouts)
        let insights = JournalInsights.compute(cycles: cycles, journal: journal, calendar: calendar)
        return PeriodReport(
            kind: kind,
            start: interval.start,
            end: interval.end,
            cycleCount: inside.count,
            meanRecovery: Statistics.mean(recoveries.map(\.1)),
            meanStrain: Statistics.mean(inside.map { $0.load.strain }),
            meanSleepScore: Statistics.mean(inside.map { $0.sleepScore.score }),
            bestRecoveryDay: best,
            worstRecoveryDay: worst,
            workoutCount: workouts.count,
            totalStrain: inside.reduce(0) { $0 + $1.load.strain },
            // 周期末的负债减去周期初第一晚结束时的负债
            debtChangeHours: inside.last.flatMap { last in inside.first.map { last.debtAfterNight - $0.debtAfterNight } },
            topInsights: Array(insights.prefix(3))
        )
    }
}
