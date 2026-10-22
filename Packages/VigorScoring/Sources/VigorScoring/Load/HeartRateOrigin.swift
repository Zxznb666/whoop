import Foundation
import VigorFIT

/// 心率样本的来源优先级（施工文档 §2.3）。数值越大优先级越高。
/// 全局顺序：FIT 导入 > Apple Watch 训练期间 > 其他 App 训练期间（含 Garmin）> Apple Watch 被动采样 > 其他。
public enum HeartRateOrigin: Int, Sendable, Hashable, Codable, Comparable {
    case other = 0
    case watchPassive = 1
    case otherWorkout = 2
    case watchWorkout = 3
    case fitImport = 4

    public static func < (lhs: HeartRateOrigin, rhs: HeartRateOrigin) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 带来源标签的心率测量。
public struct TaggedHeartRate: Sendable, Hashable {
    public var date: Date
    public var bpm: Double
    public var origin: HeartRateOrigin

    public init(date: Date, bpm: Double, origin: HeartRateOrigin) {
        self.date = date
        self.bpm = bpm
        self.origin = origin
    }
}

public enum HeartRateOriginClassifier {
    /// 给 HealthKit 心率样本打标签（M6 §2.3）：
    /// - 手表样本落在**手表自己的训练**时段内 → `watchWorkout`；
    /// - 其他来源（如 Garmin 写入）落在任何训练时段内 → `otherWorkout`；
    /// - 手表样本落在其他 App 的训练时段内，或不在任何训练中 → `watchPassive`；
    /// - 其余 → `other`。
    /// 训练区间按来源分别合并为不相交区间后二分查找，避免对长历史做 样本数 × 训练数 的扫描。
    public static func tag(_ samples: [HeartRateSample], workouts: [WorkoutSample]) -> [TaggedHeartRate] {
        let watchWindows = mergedWindows(workouts.filter { $0.productType?.hasPrefix("Watch") == true })
        let otherWindows = mergedWindows(workouts.filter { $0.productType?.hasPrefix("Watch") != true })
        return samples.map { sample in
            let isWatch = sample.productType?.hasPrefix("Watch") == true
            let origin: HeartRateOrigin
            if isWatch {
                origin = contains(watchWindows, sample.date) ? .watchWorkout : .watchPassive
            } else {
                let inAnyWorkout = contains(watchWindows, sample.date) || contains(otherWindows, sample.date)
                origin = inAnyWorkout ? .otherWorkout : .other
            }
            return TaggedHeartRate(date: sample.date, bpm: sample.bpm, origin: origin)
        }
    }

    static func mergedWindows(_ workouts: [WorkoutSample]) -> [ClosedRange<Date>] {
        let sorted = workouts.map { $0.start...max($0.start, $0.end) }.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Date>] = []
        for window in sorted {
            if let last = merged.last, window.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                merged.append(window)
            }
        }
        return merged
    }

    static func contains(_ windows: [ClosedRange<Date>], _ date: Date) -> Bool {
        var low = 0
        var high = windows.count
        while low < high {
            let middle = (low + high) / 2
            if windows[middle].lowerBound <= date { low = middle + 1 } else { high = middle }
        }
        return low > 0 && windows[low - 1].contains(date)
    }

    /// 导入的骑行：FIT 心率按分钟求平均后作为 FIT 导入来源。
    /// 分钟网格本来就按分钟取平均，因此按分钟预先求平均得到的网格与逐秒输入完全相同，但样本数减少两个数量级。
    /// 逐秒的心率仍然保留在 `RideStream` 中，供骑行的 1 Hz 计算使用。
    public static func fitSamples(_ rides: [RideStream]) -> [TaggedHeartRate] {
        var result: [TaggedHeartRate] = []
        for ride in rides {
            var minuteSum: [Int: (sum: Double, count: Int)] = [:]
            let origin = ride.start.timeIntervalSince1970
            for (index, value) in ride.heartRate.enumerated() {
                guard let value else { continue }
                let minute = Int(floor((origin + Double(index)) / 60))
                let current = minuteSum[minute] ?? (0, 0)
                minuteSum[minute] = (current.sum + Double(value), current.count + 1)
            }
            for (minute, aggregate) in minuteSum.sorted(by: { $0.key < $1.key }) {
                let date = Date(timeIntervalSince1970: Double(minute) * 60 + 30)
                result.append(TaggedHeartRate(date: date, bpm: aggregate.sum / Double(aggregate.count), origin: .fitImport))
            }
        }
        return result
    }
}
