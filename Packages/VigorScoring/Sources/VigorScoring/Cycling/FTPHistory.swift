import Foundation

/// 一次手动 FTP 修改的记录（M6 补完 C4）。`watts` 为 nil 表示当时清除了手动值。
/// 只记录从本版本开始的修改；之前的日期没有历史，不使用手动值。
public struct ManualFTPEntry: Codable, Sendable, Hashable {
    public var date: Date
    public var watts: Double?

    public init(date: Date, watts: Double?) {
        self.date = date
        self.watts = watts
    }
}

/// FTP 历史中的一个点（每周一 00:00）。`watts` 为 nil 表示当时没有任何来源。
public struct FTPPoint: Sendable, Hashable, Identifiable {
    public var date: Date
    public var watts: Double?
    public var source: FTPSource?

    public var id: Date { date }

    public init(date: Date, watts: Double?, source: FTPSource?) {
        self.date = date
        self.watts = watts
        self.source = source
    }
}

/// FTP 历史（施工文档 M6 补完 C4）。
/// 每个时间点的取值优先级：当时生效的手动设置 > 当时最新的 HealthKit FTP 样本 > 截至当时最近 90 天最佳 20 分钟功率 × 0.95 > 无。
public enum FTPHistory {
    /// 覆盖的天数（每周一个点）
    public static let spanDays = 365
    /// 自动估算使用的回看天数
    public static let estimateWindowDays = 90

    /// 每周一 00:00 的点，覆盖 `now` 之前的 `spanDays` 天到 `now` 所在的那一周。
    public static func make(
        rides: [RideResult],
        healthKitFTP: [ValueSample],
        manual: [ManualFTPEntry],
        now: Date,
        calendar: Calendar
    ) -> [FTPPoint] {
        let earliest = calendar.date(byAdding: .day, value: -spanDays, to: now) ?? now
        var monday = startOfWeek(earliest, calendar: calendar)
        var points: [FTPPoint] = []
        while monday <= now {
            points.append(resolve(at: monday, rides: rides, healthKitFTP: healthKitFTP, manual: manual, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 7, to: monday) else { break }
            monday = next
        }
        return points
    }

    /// 某一时刻的 FTP 与来源（优先级见类型注释）。
    public static func resolve(
        at date: Date,
        rides: [RideResult],
        healthKitFTP: [ValueSample],
        manual: [ManualFTPEntry],
        calendar: Calendar
    ) -> FTPPoint {
        // 1. 当时生效的手动设置：最后一次不晚于该时刻的记录；为 nil（清除）时不使用
        if let entry = manual.filter({ $0.date <= date }).max(by: { $0.date < $1.date }),
           let watts = entry.watts, watts > 0 {
            return FTPPoint(date: date, watts: watts, source: .manual)
        }
        // 2. 当时最新的 HealthKit FTP 样本
        if let sample = healthKitFTP.filter({ $0.start <= date }).max(by: { $0.start < $1.start }), sample.value > 0 {
            return FTPPoint(date: date, watts: sample.value, source: .healthKit)
        }
        // 3. 截至当时最近 90 天的最佳 20 分钟功率 × 0.95
        let windowStart = calendar.date(byAdding: .day, value: -estimateWindowDays, to: date) ?? date
        let best = rides
            .filter { $0.end <= date && $0.end >= windowStart }
            .compactMap { $0.powerCurve[1200] }
            .max()
        if let best {
            return FTPPoint(date: date, watts: CyclingMath.estimatedFTP(bestTwentyMinutePower: best), source: .estimated)
        }
        return FTPPoint(date: date, watts: nil, source: nil)
    }

    /// 所在周的周一 00:00（不依赖 `calendar.firstWeekday`）。
    static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // 1 = 周日
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: day) ?? day
    }
}

/// 骑行趋势（M6 补完 C4）：EF 的 90 天斜率、90 天最佳 20 分钟功率的变化。
public enum CyclingTrends {
    public static let windowDays = 90
    /// 计算斜率所需的最少骑行次数（有 EF 的骑行）
    public static let minimumEFRides = 3

    /// EF 的 90 天线性斜率（每天）。`now` 之前 90 天内有 EF 的骑行少于 3 次时为 nil。
    public static func efficiencySlopePerDay(rides: [RideResult], now: Date, calendar: Calendar) -> Double? {
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let points = rides
            .filter { $0.end >= windowStart && $0.end <= now }
            .compactMap { ride -> (date: Date, value: Double)? in
                ride.efficiencyFactor.map { (ride.start, $0) }
            }
            .sorted { $0.date < $1.date }
        guard points.count >= minimumEFRides else { return nil }
        return CardioFitness.slopePerDay(points)
    }

    /// 最近 90 天最佳 20 分钟功率（W）与上一个 90 天的最佳值。任一为空时为 nil。
    public static func bestTwentyMinuteChange(
        rides: [RideResult],
        now: Date,
        calendar: Calendar
    ) -> (current: Double, previous: Double)? {
        let currentStart = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -2 * windowDays, to: now) ?? now
        let current = rides.filter { $0.end > currentStart && $0.end <= now }.compactMap { $0.powerCurve[1200] }.max()
        let previous = rides.filter { $0.end > previousStart && $0.end <= currentStart }.compactMap { $0.powerCurve[1200] }.max()
        guard let current, let previous else { return nil }
        return (current, previous)
    }
}
