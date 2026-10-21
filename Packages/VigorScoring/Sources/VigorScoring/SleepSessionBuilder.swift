import Foundation

/// 睡眠会话（PRD §5.2）。stages 为会话内的睡着与清醒分期（不含在床）。
public struct SleepSession: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case main
        case nap
    }

    /// 第一个“睡着”分期的开始（入睡）
    public var start: Date
    /// 最后一个“睡着”分期的结束（醒来）
    public var end: Date
    /// 与会话重叠的在床样本中最早的开始时间（上床）
    public var bedtime: Date?
    /// 会话内的分期样本（睡着 + 清醒），按时间排序
    public var stages: [SleepStageSample]
    /// 各睡着分期的并集时长（重叠只计一次）
    public var asleepDuration: TimeInterval
    /// 醒来日（end 所在的本地日期）
    public var wakeDay: DateComponents
    /// 夜晚键：中点 − 15 小时的本地日期（PRD §4.4）
    public var nightKey: DateComponents
    public var kind: Kind
    /// 醒来时刻的 UTC 偏移（秒）
    public var timeZoneOffset: Int
    /// 合并时出现的、间隔 45–120 分钟的长清醒（分段睡眠）
    public var longAwakeGaps: [DateInterval]

    public var isMain: Bool { kind == .main }

    public init(
        start: Date,
        end: Date,
        bedtime: Date?,
        stages: [SleepStageSample],
        asleepDuration: TimeInterval,
        wakeDay: DateComponents,
        nightKey: DateComponents,
        kind: Kind,
        timeZoneOffset: Int,
        longAwakeGaps: [DateInterval]
    ) {
        self.start = start
        self.end = end
        self.bedtime = bedtime
        self.stages = stages
        self.asleepDuration = asleepDuration
        self.wakeDay = wakeDay
        self.nightKey = nightKey
        self.kind = kind
        self.timeZoneOffset = timeZoneOffset
        self.longAwakeGaps = longAwakeGaps
    }
}

/// 手动修正覆盖层（PRD §5.2 第 8 条）：只改会话的起止，不改 HealthKit 原始数据。
public struct SleepOverride: Sendable, Hashable, Codable {
    public var start: Date?
    public var end: Date?

    public init(start: Date? = nil, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

public enum SleepSessionBuilder {
    /// 来源优先级：Apple Watch（0）> iPhone（1）> 其他 App（2）。
    static func sourceRank(_ sample: SleepStageSample) -> Int {
        if sample.sourceIsWatch { return 0 }
        if sample.productType?.hasPrefix("iPhone") == true { return 1 }
        return 2
    }

    public static func sessions(
        stages: [SleepStageSample],
        inBed: [SleepStageSample] = [],
        calendar: Calendar,
        config: ScoringConfig = .default,
        overrides: [DateComponents: SleepOverride] = [:]
    ) -> [SleepSession] {
        let deduplicated = removeSameSourceOverlaps(
            applySourcePriority(stages.filter { $0.stage != .inBed })
        )
        let sorted = deduplicated.sorted { $0.start < $1.start }

        var sessions = groups(sorted, calendar: calendar, config: config)
            .compactMap { makeSession($0, inBed: inBed, calendar: calendar, config: config) }
            .filter { $0.kind == .main || $0.asleepDuration >= config.napMinDuration }
        markMainSessions(&sessions, calendar: calendar, config: config)

        for index in sessions.indices where sessions[index].isMain {
            guard let override = overrides[sessions[index].nightKey] else { continue }
            apply(override, to: &sessions[index])
        }
        return sessions.sorted { $0.start < $1.start }
    }

    // MARK: 来源优先级与去重

    /// 分期样本只保留时间上没有更高优先级来源覆盖的那一条。
    static func applySourcePriority(_ samples: [SleepStageSample]) -> [SleepStageSample] {
        samples.filter { sample in
            !samples.contains { other in
                sourceRank(other) < sourceRank(sample) && overlaps(other, sample)
            }
        }
    }

    /// 同一来源内重叠时保留较晚的一条：优先比较创建时间，缺失时比较结束时间（见 DECISIONS D-004）。
    static func removeSameSourceOverlaps(_ samples: [SleepStageSample]) -> [SleepStageSample] {
        var kept: [SleepStageSample] = []
        for sample in samples.sorted(by: { $0.start < $1.start }) {
            if let index = kept.firstIndex(where: { sameSource($0, sample) && overlaps($0, sample) }) {
                if recency(sample) > recency(kept[index]) {
                    kept[index] = sample
                }
            } else {
                kept.append(sample)
            }
        }
        return kept
    }

    private static func sameSource(_ a: SleepStageSample, _ b: SleepStageSample) -> Bool {
        sourceRank(a) == sourceRank(b) && a.sourceBundleID == b.sourceBundleID
    }

    private static func recency(_ sample: SleepStageSample) -> Date {
        sample.creationDate ?? sample.end
    }

    static func overlaps(_ a: SleepStageSample, _ b: SleepStageSample) -> Bool {
        a.start < b.end && b.start < a.end
    }

    // MARK: 合并

    /// 合并规则（PRD §5.2 第 3 条）：间隔 ≤ 45 分钟直接合并；45–120 分钟且两端都在夜间窗口内时合并并标记长清醒；其余拆分。
    private static func groups(
        _ samples: [SleepStageSample],
        calendar: Calendar,
        config: ScoringConfig
    ) -> [[SleepStageSample]] {
        var result: [[SleepStageSample]] = []
        var groupEnd = Date.distantPast
        for sample in samples {
            guard !result.isEmpty else {
                result.append([sample])
                groupEnd = sample.end
                continue
            }
            let gap = sample.start.timeIntervalSince(groupEnd)
            let inNightWindow = isNightWindow(groupEnd, calendar: calendar, config: config)
                && isNightWindow(sample.start, calendar: calendar, config: config)
            if gap <= config.sessionMergeGap || (gap <= config.segmentedSleepMaxGap && inNightWindow) {
                result[result.count - 1].append(sample)
                groupEnd = max(groupEnd, sample.end)
            } else {
                result.append([sample])
                groupEnd = sample.end
            }
        }
        return result
    }

    static func isNightWindow(_ date: Date, calendar: Calendar, config: ScoringConfig) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= config.nightWindowStartHour || hour < config.nightWindowEndHour
    }

    // MARK: 会话构造

    private static func makeSession(
        _ group: [SleepStageSample],
        inBed: [SleepStageSample],
        calendar: Calendar,
        config: ScoringConfig
    ) -> SleepSession? {
        let asleep = group.filter { $0.stage.isAsleep }
        guard let start = asleep.map(\.start).min(), let end = asleep.map(\.end).max() else {
            return nil
        }
        let stages = group.filter { $0.start >= start && $0.end <= end }
        let asleepInSession = stages.filter { $0.stage.isAsleep }
        let bedtime = inBed
            .filter { $0.end > start && $0.start < end }
            .map(\.start)
            .min()

        let gaps = longAwakeGaps(group, calendar: calendar, config: config)
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        return SleepSession(
            start: start,
            end: end,
            bedtime: bedtime,
            stages: stages,
            asleepDuration: unionDuration(asleepInSession),
            wakeDay: dayComponents(end, calendar: calendar),
            nightKey: dayComponents(midpoint.addingTimeInterval(-15 * 3600), calendar: calendar),
            kind: .nap,
            timeZoneOffset: calendar.timeZone.secondsFromGMT(for: end),
            longAwakeGaps: gaps
        )
    }

    /// 找出组内间隔在 45–120 分钟之间的段落，作为长清醒记录。
    private static func longAwakeGaps(
        _ group: [SleepStageSample],
        calendar: Calendar,
        config: ScoringConfig
    ) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var groupEnd: Date?
        for sample in group {
            if let previousEnd = groupEnd {
                let gap = sample.start.timeIntervalSince(previousEnd)
                if gap > config.sessionMergeGap, gap <= config.segmentedSleepMaxGap {
                    gaps.append(DateInterval(start: previousEnd, end: sample.start))
                }
                groupEnd = max(previousEnd, sample.end)
            } else {
                groupEnd = sample.end
            }
        }
        return gaps
    }

    /// 每个夜晚最多一个主睡眠：睡着时长 ≥ 3 小时、中点不落在 [15:00, 19:00)、且睡着时长最长。
    /// 夜班和作息颠倒时，白天的长会话同样符合这些条件，因此会被选为主睡眠（PRD §5.2 第 4 条）。
    private static func markMainSessions(_ sessions: inout [SleepSession], calendar: Calendar, config: ScoringConfig) {
        var best: [DateComponents: Int] = [:]
        for index in sessions.indices {
            let session = sessions[index]
            guard session.asleepDuration >= config.mainSleepMinDuration,
                  isEligibleMidpoint(session, calendar: calendar, config: config)
            else { continue }
            if let current = best[session.nightKey], sessions[current].asleepDuration >= session.asleepDuration {
                continue
            }
            best[session.nightKey] = index
        }
        for index in sessions.indices {
            sessions[index].kind = best[sessions[index].nightKey] == index ? .main : .nap
        }
    }

    /// 中点的本地小时不在 [napOnlyStartHour, napOnlyEndHour) 内（PRD §4.4 的夜晚归属规则）。
    private static func isEligibleMidpoint(_ session: SleepSession, calendar: Calendar, config: ScoringConfig) -> Bool {
        let midpoint = session.start.addingTimeInterval(session.end.timeIntervalSince(session.start) / 2)
        let hour = calendar.component(.hour, from: midpoint)
        return !(hour >= config.napOnlyStartHour && hour < config.napOnlyEndHour)
    }

    /// 修正覆盖层：替换主睡眠的起止，并重新计算睡着时长。
    private static func apply(_ override: SleepOverride, to session: inout SleepSession) {
        if let start = override.start { session.start = start }
        if let end = override.end { session.end = end }
        // 分期按新的起止裁剪（原始数据不变，只是这一晚的视图被裁剪）
        session.stages = session.stages.compactMap { sample in
            let start = max(sample.start, session.start)
            let end = min(sample.end, session.end)
            guard end > start else { return nil }
            var clipped = sample
            clipped.start = start
            clipped.end = end
            return clipped
        }
        session.asleepDuration = unionDuration(session.stages.filter { $0.stage.isAsleep })
    }

    // MARK: 工具

    /// 区间并集的总时长，重叠部分只计一次。
    static func unionDuration(_ samples: [SleepStageSample]) -> TimeInterval {
        let intervals = samples.map { ($0.start, $0.end) }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var run: (start: Date, end: Date)?
        for (start, end) in intervals {
            guard let current = run else {
                run = (start, end)
                continue
            }
            if start <= current.end {
                run = (current.start, max(current.end, end))
            } else {
                total += current.end.timeIntervalSince(current.start)
                run = (start, end)
            }
        }
        if let current = run {
            total += current.end.timeIntervalSince(current.start)
        }
        return total
    }

    /// 只保留年月日的本地日期键。`Calendar.dateComponents` 的结果会带上日历与时区，直接用作字典键会不相等。
    static func dayComponents(_ date: Date, calendar: Calendar) -> DateComponents {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return DateComponents(year: parts.year, month: parts.month, day: parts.day)
    }
}
