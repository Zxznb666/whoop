import Foundation

/// 夜间静息心率（PRD §5.4）。
public struct RestingHeartRate: Sendable, Hashable, Codable {
    public enum Source: String, Codable, Sendable, Hashable {
        /// 样本池的第 10 百分位
        case sampledP10
        /// 样本不足，退回 Apple 的 restingHeartRate
        case appleFallback
        case none
    }

    /// bpm
    public var value: Double?
    public var source: Source
    public var sampleCount: Int
    /// 夜间平均心率
    public var meanHeartRate: Double?
    /// 15 分钟滑动中位数最低点的时刻在夜间的位置（0–1）
    public var lowestTimePosition: Double?

    public init(
        value: Double?,
        source: Source,
        sampleCount: Int,
        meanHeartRate: Double?,
        lowestTimePosition: Double?
    ) {
        self.value = value
        self.source = source
        self.sampleCount = sampleCount
        self.meanHeartRate = meanHeartRate
        self.lowestTimePosition = lowestTimePosition
    }
}

public enum NightRestingHR {
    /// - Parameters:
    ///   - seriesMeanHeartRates: 有效 heartbeat 序列的平均心率，加入样本池（§5.4 的“后者能明显提高夜间的采样密度”）
    ///   - appleRestingHeartRate: 当天 Apple 的静息心率，样本不足时的兜底
    public static func compute(
        heartRate: [HeartRateSample],
        session: SleepSession,
        seriesMeanHeartRates: [Double],
        appleRestingHeartRate: Double?,
        config: ScoringConfig = .default
    ) -> RestingHeartRate {
        let awakeRuns = session.stages.filter { sample in
            sample.stage == .awake && sample.end.timeIntervalSince(sample.start) >= config.restingExcludeAwakeSeconds
        }
        let points = heartRate
            .filter { $0.date >= session.start && $0.date <= session.end }
            .filter { point in !awakeRuns.contains { point.date >= $0.start && point.date <= $0.end } }
            .sorted { $0.date < $1.date }

        let pool = points.map(\.bpm) + seriesMeanHeartRates
        let mean = Statistics.mean(pool)
        let lowest = lowestTimePosition(points, session: session, config: config)

        if pool.count >= config.restingMinSampleCount,
           let p10 = Statistics.percentile(pool, config.restingPercentile) {
            return RestingHeartRate(
                value: p10,
                source: .sampledP10,
                sampleCount: pool.count,
                meanHeartRate: mean,
                lowestTimePosition: lowest
            )
        }
        if let apple = appleRestingHeartRate {
            return RestingHeartRate(
                value: apple,
                source: .appleFallback,
                sampleCount: pool.count,
                meanHeartRate: mean,
                lowestTimePosition: lowest
            )
        }
        return RestingHeartRate(
            value: nil,
            source: .none,
            sampleCount: pool.count,
            meanHeartRate: mean,
            lowestTimePosition: lowest
        )
    }

    /// 15 分钟（居中）滑动中位数的最低点所在的时刻，换算为夜间位置。点数不足 3 个的窗口跳过。
    static func lowestTimePosition(_ points: [HeartRateSample], session: SleepSession, config: ScoringConfig) -> Double? {
        let half = config.restingWindowSeconds / 2
        let duration = session.end.timeIntervalSince(session.start)
        guard duration > 0 else { return nil }

        var lowest: (value: Double, time: Date)?
        for point in points {
            let window = points
                .filter { abs($0.date.timeIntervalSince(point.date)) <= half }
                .map(\.bpm)
            guard window.count >= 3, let median = Statistics.median(window) else { continue }
            if lowest == nil || median < lowest!.value {
                lowest = (median, point.date)
            }
        }
        guard let time = lowest?.time else { return nil }
        return min(max(time.timeIntervalSince(session.start) / duration, 0), 1)
    }
}
