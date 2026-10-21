import Foundation

/// 环形统计（PRD §5.9.2）：处理跨午夜的时刻，例如 23:50 与 00:10 的平均是 00:00。
public enum CircularStatistics {
    public struct Result: Sendable, Hashable {
        /// 环形均值，分钟（0 ≤ x < 1440）
        public var meanMinuteOfDay: Double
        /// 环形标准差，分钟
        public var standardDeviationMinutes: Double
    }

    /// 输入为一天中的分钟数（0 ≤ x < 1440）。
    public static func summarize(minutesOfDay: [Double]) -> Result? {
        guard !minutesOfDay.isEmpty else { return nil }
        let day = 1440.0
        var cosSum = 0.0
        var sinSum = 0.0
        for minute in minutesOfDay {
            let theta = 2 * Double.pi * minute / day
            cosSum += cos(theta)
            sinSum += sin(theta)
        }
        let n = Double(minutesOfDay.count)
        let meanCos = cosSum / n
        let meanSin = sinSum / n
        let r = (meanCos * meanCos + meanSin * meanSin).squareRoot()
        var mean = atan2(meanSin, meanCos) * day / (2 * Double.pi)
        if mean < 0 { mean += day }
        // R = 1 时方差为 0；数值误差可能让 R 略小于 1，夹到 [0, 1] 内
        let clamped = min(max(r, 1e-12), 1)
        let sd = (-2 * log(clamped)).squareRoot() * day / (2 * Double.pi)
        return Result(meanMinuteOfDay: mean, standardDeviationMinutes: sd)
    }
}

/// 睡眠规律指数 SRI（PRD §5.9.2）。
public enum SleepRegularity {
    /// 至少需要的有效天数
    public static let minimumDays = 5

    /// - Parameters:
    ///   - stages: 睡眠分期（睡着与清醒），只使用结束时间不晚于 `endingAt` 的样本
    ///   - endingAt: 窗口的结束时刻（通常是当晚的醒来时刻）
    /// - Returns: SRI（−100 … 100），数据不足时为 nil。对外显示为 max(0, SRI)。
    public static func sri(
        stages: [SleepStageSample],
        endingAt: Date,
        calendar: Calendar,
        days: Int = 7
    ) -> Double? {
        let minute: TimeInterval = 60
        let minutesPerDay = 1440
        let total = days * minutesPerDay
        guard let start = calendar.date(byAdding: .day, value: -days, to: endingAt) else { return nil }

        // 0 = 未知，1 = 醒着，2 = 睡着
        var state = [UInt8](repeating: 0, count: total)
        for sample in stages where sample.end <= endingAt && sample.end > start {
            let fill: UInt8
            switch sample.stage {
            case .awake: fill = 1
            case .core, .deep, .rem, .asleepUnspecified: fill = 2
            case .inBed: continue
            }
            let first = max(0, Int(sample.start.timeIntervalSince(start) / minute))
            let last = min(total, Int(ceil(sample.end.timeIntervalSince(start) / minute)))
            guard first < last else { continue }
            for index in first..<last where fill == 2 || state[index] == 0 {
                state[index] = fill
            }
        }

        var coveredDays = 0
        for day in 0..<days {
            let range = (day * minutesPerDay)..<((day + 1) * minutesPerDay)
            if state[range].contains(where: { $0 != 0 }) {
                coveredDays += 1
            }
        }
        guard coveredDays >= minimumDays else { return nil }

        var comparable = 0
        var agreeing = 0
        state.withUnsafeBufferPointer { buffer in
            for index in 0..<(total - minutesPerDay) {
                let a = buffer[index]
                let b = buffer[index + minutesPerDay]
                guard a != 0, b != 0 else { continue }
                comparable += 1
                if a == b { agreeing += 1 }
            }
        }
        guard comparable > 0 else { return nil }
        let probability = Double(agreeing) / Double(comparable)
        return -100 + 200 * probability
    }
}
