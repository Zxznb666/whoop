import Foundation

/// 睡眠分（PRD §5.9.4）：0–100，摘要页的睡眠环显示这个值。
public struct SleepScore: Sendable, Hashable, Codable {
    public var score: Double
    /// 睡眠表现 %（时长达成，0–100）
    public var performance: Double
    public var durationAchieved: Double
    public var efficiencyComponent: Double
    /// 一致性分量（SRI 显示值 / 100）；SRI 不足时为 nil，权重按比例分配给其余分量
    public var consistencyComponent: Double?
    /// 修复分；没有基线时为 nil
    public var restorativeComponent: Double?
    /// 睡眠分对应的 z-score：(睡眠分 − 80) / 12，用于恢复分数
    public var zSleep: Double

    public init(
        score: Double,
        performance: Double,
        durationAchieved: Double,
        efficiencyComponent: Double,
        consistencyComponent: Double?,
        restorativeComponent: Double?,
        zSleep: Double
    ) {
        self.score = score
        self.performance = performance
        self.durationAchieved = durationAchieved
        self.efficiencyComponent = efficiencyComponent
        self.consistencyComponent = consistencyComponent
        self.restorativeComponent = restorativeComponent
        self.zSleep = zSleep
    }
}

public enum SleepScoring {
    /// - Parameters:
    ///   - napCreditHours: 小睡抵扣（小时）
    ///   - needHours: 今晚的睡眠需求（小时）
    ///   - sri: SRI（−100…100），nil 表示数据不足
    ///   - zRestorative: 修复性睡眠时长的 z-score，nil 表示没有基线
    public static func score(
        totalSleepHours: Double,
        napCreditHours: Double,
        needHours: Double,
        efficiency: Double,
        sri: Double?,
        zRestorative: Double?
    ) -> SleepScore {
        let duration = needHours > 0 ? min(1, (totalSleepHours + napCreditHours) / needHours) : 0
        let efficiencyPart = min(max((efficiency - 0.75) / 0.20, 0), 1)
        let consistency = sri.map { max(0, $0) / 100 }
        let restorative = zRestorative.map { min(max(0.5 + 0.25 * $0, 0), 1) }

        var parts: [(value: Double, weight: Double)] = [
            (duration, 0.55),
            (efficiencyPart, 0.15),
        ]
        if let consistency { parts.append((consistency, 0.15)) }
        if let restorative { parts.append((restorative, 0.15)) }
        let weightSum = parts.reduce(0) { $0 + $1.weight }
        let score = 100 * parts.reduce(0) { $0 + $1.value * $1.weight } / weightSum

        return SleepScore(
            score: score,
            performance: duration * 100,
            durationAchieved: duration,
            efficiencyComponent: efficiencyPart,
            consistencyComponent: consistency,
            restorativeComponent: restorative,
            zSleep: (score - 80) / 12
        )
    }
}

/// 作息建议（PRD §5.9.5）。
public struct BedtimeAdvice: Sendable, Hashable, Codable {
    /// 要睡够 100% / 85% / 70% 的需求，分别在几点入睡
    public var bedtimeAt100: Date
    public var bedtimeAt85: Date
    public var bedtimeAt70: Date
    /// 是否因渐进调整而推迟了理论值
    public var progressivelyAdjusted: Bool

    public init(bedtimeAt100: Date, bedtimeAt85: Date, bedtimeAt70: Date, progressivelyAdjusted: Bool) {
        self.bedtimeAt100 = bedtimeAt100
        self.bedtimeAt85 = bedtimeAt85
        self.bedtimeAt70 = bedtimeAt70
        self.progressivelyAdjusted = progressivelyAdjusted
    }
}

public enum BedtimeAdvisor {
    /// - Parameters:
    ///   - wakeTime: 目标起床时间
    ///   - needHours: 今晚的睡眠需求（小时）
    ///   - latencyMinutes: 个人入睡耗时的中位数（没有数据时取 15 分钟）
    ///   - averageBedtime: 最近 7 天入睡时刻的环形均值；用于渐进调整
    ///   - previousBedtime: 昨晚的入睡时刻；每晚最多提前 30 分钟逐步靠拢
    public static func advise(
        wakeTime: Date,
        needHours: Double,
        latencyMinutes: Double,
        averageBedtime: Date?,
        previousBedtime: Date?
    ) -> BedtimeAdvice {
        func bedtime(_ fraction: Double) -> Date {
            wakeTime.addingTimeInterval(-(fraction * needHours * 3600 + latencyMinutes * 60))
        }
        var at100 = bedtime(1.0)
        var adjusted = false
        if let average = averageBedtime, let previous = previousBedtime,
           at100 < average.addingTimeInterval(-60 * 60) {
            let limit = previous.addingTimeInterval(-30 * 60)
            if at100 < limit {
                at100 = limit
                adjusted = true
            }
        }
        let shift = at100.timeIntervalSince(bedtime(1.0))
        return BedtimeAdvice(
            bedtimeAt100: at100,
            bedtimeAt85: bedtime(0.85).addingTimeInterval(shift),
            bedtimeAt70: bedtime(0.70).addingTimeInterval(shift),
            progressivelyAdjusted: adjusted
        )
    }
}
