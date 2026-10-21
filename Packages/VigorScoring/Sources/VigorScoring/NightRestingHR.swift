import Foundation

public enum NightRestingHR {
    private static let windowLength: TimeInterval = 300
    private static let minimumSampleCount = 10

    /// 睡眠时段内，每个样本起的 5 分钟窗口均值的最小值。
    public static func compute(heartRate: [HeartRateSample], session: SleepSession) -> Double? {
        let samples = heartRate
            .filter { $0.date >= session.start && $0.date <= session.end }
            .sorted { $0.date < $1.date }
        guard samples.count >= minimumSampleCount else { return nil }

        var lowest: Double?
        for index in samples.indices {
            let windowEnd = samples[index].date.addingTimeInterval(windowLength)
            let window = samples[index...].prefix { $0.date <= windowEnd }
            let mean = window.reduce(0) { $0 + $1.bpm } / Double(window.count)
            lowest = min(lowest ?? mean, mean)
        }
        return lowest
    }
}
