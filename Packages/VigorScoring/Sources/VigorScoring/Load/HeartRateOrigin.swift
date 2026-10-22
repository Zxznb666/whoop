import Foundation
import VigorFIT

/// 心率样本的来源优先级（施工文档 §2.3；M6 补完 C5 增加手动指定的一档）。
/// 排序由 `rank` 决定，**不要**依赖 rawValue：rawValue 已写入存储，只能新增、不能改动。
/// 全局顺序：FIT 导入 > 手动优先的来源训练期间 > Apple Watch 训练期间 > 其他 App 训练期间（含 Garmin）> Apple Watch 被动采样 > 其他。
public enum HeartRateOrigin: Int, Sendable, Hashable, Codable, Comparable {
    case other = 0
    case watchPassive = 1
    case otherWorkout = 2
    case watchWorkout = 3
    case fitImport = 4
    /// 用户在设置中把某个来源标为“优先”，且样本位于该来源自己的训练时段内（C5）
    case preferredWorkout = 5

    /// 比较用的显式排名（与 rawValue 无关）。
    public var rank: Int {
        switch self {
        case .other: 0
        case .watchPassive: 1
        case .otherWorkout: 2
        case .watchWorkout: 3
        case .preferredWorkout: 4
        case .fitImport: 5
        }
    }

    public static func < (lhs: HeartRateOrigin, rhs: HeartRateOrigin) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// 用户为某个心率来源（按 Bundle ID）指定的处理方式（M6 补完 C5）。
/// - `automatic`：按 D-130 的规则；
/// - `preferred`：该来源在自己的训练时段内的心率优先级高于 Apple Watch 训练期间，低于 FIT 导入；
/// - `ignored`：该来源的心率样本不参与分钟去重，也不作为骑行的心率；它的训练记录仍然参与骑行分组。
public enum SourcePreference: String, Sendable, Hashable, Codable, CaseIterable {
    case automatic
    case preferred
    case ignored
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
    ///
    /// `preferences`（C5）：按来源 Bundle ID 的手动设置。`ignored` 的样本直接丢弃；`preferred` 的样本只有落在
    /// **该来源自己的训练**内才升为 `preferredWorkout`，其余情况按上面的规则处理。
    public static func tag(
        _ samples: [HeartRateSample],
        workouts: [WorkoutSample],
        preferences: [String: SourcePreference] = [:]
    ) -> [TaggedHeartRate] {
        let watchWindows = mergedWindows(workouts.filter { $0.productType?.hasPrefix("Watch") == true })
        let otherWindows = mergedWindows(workouts.filter { $0.productType?.hasPrefix("Watch") != true })
        var preferredWindows: [String: [ClosedRange<Date>]] = [:]
        for (bundle, preference) in preferences where preference == .preferred {
            preferredWindows[bundle] = mergedWindows(workouts.filter { $0.sourceBundleID == bundle })
        }
        var result: [TaggedHeartRate] = []
        result.reserveCapacity(samples.count)
        for sample in samples {
            let preference = sample.sourceBundleID.flatMap { preferences[$0] } ?? .automatic
            if preference == .ignored { continue }
            if preference == .preferred, let bundle = sample.sourceBundleID,
               contains(preferredWindows[bundle] ?? [], sample.date) {
                result.append(TaggedHeartRate(date: sample.date, bpm: sample.bpm, origin: .preferredWorkout))
                continue
            }
            let isWatch = sample.productType?.hasPrefix("Watch") == true
            let origin: HeartRateOrigin
            if isWatch {
                origin = contains(watchWindows, sample.date) ? .watchWorkout : .watchPassive
            } else {
                let inAnyWorkout = contains(watchWindows, sample.date) || contains(otherWindows, sample.date)
                origin = inAnyWorkout ? .otherWorkout : .other
            }
            result.append(TaggedHeartRate(date: sample.date, bpm: sample.bpm, origin: origin))
        }
        return result
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
