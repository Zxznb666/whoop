import Foundation

public enum MaxHeartRate {
    /// 初始值：208 − 0.7 × 年龄（Tanaka）。年龄未知时按 35 岁处理。
    public static func initial(birthYear: Int?, year: Int) -> Double {
        let age = birthYear.map { Double(year - $0) } ?? 35
        return 208 - 0.7 * age
    }

    /// 运动中 30 秒滑动均值的最大值（按 30 秒分桶的均值近似）。没有运动心率时为 nil。
    public static func observedPeak(workoutHeartRate: [HeartRateSample]) -> Double? {
        guard let first = workoutHeartRate.map(\.date).min() else { return nil }
        var buckets: [Int: (sum: Double, count: Int)] = [:]
        for sample in workoutHeartRate {
            let bucket = Int(sample.date.timeIntervalSince(first) / 30)
            buckets[bucket, default: (0, 0)].sum += sample.bpm
            buckets[bucket, default: (0, 0)].count += 1
        }
        return buckets.values.map { $0.sum / Double($0.count) }.max()
    }

    /// 观测到更高的心率时自动上调，但不低于初始值（§5.1）。
    public static func effective(initial: Double, observedPeak: Double?) -> Double {
        max(initial, observedPeak ?? initial)
    }
}
