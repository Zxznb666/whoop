import Foundation

public struct SleepSession: Sendable, Hashable, Codable {
    /// 第一个“睡着”样本的开始时间
    public var start: Date
    /// 最后一个“睡着”样本的结束时间
    public var end: Date
    /// 落在 [start, end] 内的睡着与清醒样本
    public var stages: [SleepStageSample]
    /// 各睡着分期的时长之和（重叠部分只计一次）
    public var asleepDuration: TimeInterval
    /// end 所在的本地日期
    public var wakeDay: DateComponents
    public var isMain: Bool

    public init(
        start: Date,
        end: Date,
        stages: [SleepStageSample],
        asleepDuration: TimeInterval,
        wakeDay: DateComponents,
        isMain: Bool
    ) {
        self.start = start
        self.end = end
        self.stages = stages
        self.asleepDuration = asleepDuration
        self.wakeDay = wakeDay
        self.isMain = isMain
    }
}

public enum SleepSessionBuilder {
    public static func sessions(
        from samples: [SleepStageSample],
        calendar: Calendar,
        config: HRVConfig
    ) -> [SleepSession] {
        let usable = samples
            .filter { $0.sourceIsWatch && $0.stage != .inBed }
            .sorted { $0.start < $1.start }

        var sessions = groups(usable, mergeGap: config.sessionMergeGap)
            .compactMap { makeSession($0, calendar: calendar) }
        markMainSessions(&sessions)
        return sessions.sorted { $0.start < $1.start }
    }

    /// 按时间顺序合并：新样本的开始与当前组的结束之差不超过 mergeGap 时并入当前组。
    private static func groups(_ samples: [SleepStageSample], mergeGap: TimeInterval) -> [[SleepStageSample]] {
        var result: [[SleepStageSample]] = []
        var groupEnd = Date.distantPast
        for sample in samples {
            if !result.isEmpty, sample.start.timeIntervalSince(groupEnd) <= mergeGap {
                result[result.count - 1].append(sample)
                groupEnd = max(groupEnd, sample.end)
            } else {
                result.append([sample])
                groupEnd = sample.end
            }
        }
        return result
    }

    private static func makeSession(_ group: [SleepStageSample], calendar: Calendar) -> SleepSession? {
        let asleep = group.filter { $0.stage.isAsleep }
        guard let start = asleep.map(\.start).min(), let end = asleep.map(\.end).max() else {
            return nil
        }
        let stages = group.filter { sample in
            (sample.stage.isAsleep || sample.stage == .awake)
                && sample.start >= start
                && sample.end <= end
        }
        return SleepSession(
            start: start,
            end: end,
            stages: stages,
            asleepDuration: unionDuration(asleep),
            wakeDay: calendar.dateComponents([.year, .month, .day], from: end),
            isMain: false
        )
    }

    /// 区间并集的总时长，重叠部分只计一次。
    private static func unionDuration(_ samples: [SleepStageSample]) -> TimeInterval {
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

    /// 每个醒来日只有睡着时长最长的会话是主睡眠。
    private static func markMainSessions(_ sessions: inout [SleepSession]) {
        var longestByDay: [DateComponents: Int] = [:]
        for index in sessions.indices {
            let day = sessions[index].wakeDay
            if let best = longestByDay[day], sessions[best].asleepDuration >= sessions[index].asleepDuration {
                continue
            }
            longestByDay[day] = index
        }
        for index in sessions.indices {
            sessions[index].isMain = longestByDay[sessions[index].wakeDay] == index
        }
    }
}
