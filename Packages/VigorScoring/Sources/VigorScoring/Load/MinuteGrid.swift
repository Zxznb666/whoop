import Foundation

/// 分钟网格：把心率、活动能量与步数对齐到整分钟，供负荷时间线使用（PRD §5.10 第 1 条）。
/// 一次构建覆盖整个历史；每个周期只读取自己的分钟区间。
public struct MinuteGrid: Sendable {
    /// 第 0 分钟的起点（整分钟）
    public let origin: Date
    public let count: Int
    /// 每分钟的平均心率（bpm）；NaN 表示没有测量
    public private(set) var heartRate: [Double]
    /// 每分钟的活动能量（kcal）；NaN 表示没有记录
    public private(set) var kilocalories: [Double]
    /// 每分钟的步数；NaN 表示没有记录
    public private(set) var steps: [Double]
    /// 当前或之前最近一个有心率测量的分钟，-1 表示没有
    public private(set) var previousMeasured: [Int]
    /// 每分钟被采用的心率来源（分钟级去重的结果）；没有测量时为 nil
    public private(set) var heartRateOrigin: [HeartRateOrigin?]
    /// 当前或之后最近一个有心率测量的分钟，-1 表示没有
    public private(set) var nextMeasured: [Int]
    /// 心率与活动能量同时存在的分钟的前缀和：n、Σx、Σy、Σxy、Σx²、Σy²，用于空窗回归的 O(1) 查询
    private var prefix: [[Double]]

    /// 无来源信息的心率按“其他”处理。
    public static func build(
        origin: Date,
        end: Date,
        heartRate samples: [HeartRateSample],
        activeEnergy: [ValueSample],
        steps stepSamples: [ValueSample]
    ) -> MinuteGrid {
        build(
            origin: origin,
            end: end,
            taggedHeartRate: samples.map { TaggedHeartRate(date: $0.date, bpm: $0.bpm, origin: .other) },
            activeEnergy: activeEnergy,
            steps: stepSamples
        )
    }

    /// 分钟级去重（施工文档 §2.3）：同一分钟有多个来源时只取优先级最高的来源的均值，绝不相加或混合平均。
    public static func build(
        origin: Date,
        end: Date,
        taggedHeartRate samples: [TaggedHeartRate],
        activeEnergy: [ValueSample],
        steps stepSamples: [ValueSample]
    ) -> MinuteGrid {
        let start = Date(timeIntervalSince1970: (origin.timeIntervalSince1970 / 60).rounded(.down) * 60)
        let count = max(0, Int(ceil(end.timeIntervalSince(start) / 60)))
        var bestOrigin = [HeartRateOrigin?](repeating: nil, count: count)
        var hrSum = [Double](repeating: 0, count: count)
        var hrCount = [Int](repeating: 0, count: count)
        for sample in samples {
            let index = Int(sample.date.timeIntervalSince(start) / 60)
            guard index >= 0, index < count else { continue }
            if let current = bestOrigin[index], sample.origin < current { continue }
            if bestOrigin[index] != sample.origin {
                bestOrigin[index] = sample.origin
                hrSum[index] = 0
                hrCount[index] = 0
            }
            hrSum[index] += sample.bpm
            hrCount[index] += 1
        }
        let heartRate = (0..<count).map { hrCount[$0] > 0 ? hrSum[$0] / Double(hrCount[$0]) : Double.nan }

        let kilocalories = spread(activeEnergy, start: start, count: count)
        let steps = spread(stepSamples, start: start, count: count)

        var previous = [Int](repeating: -1, count: count)
        var last = -1
        for index in 0..<count {
            if !heartRate[index].isNaN { last = index }
            previous[index] = last
        }
        var next = [Int](repeating: -1, count: count)
        var upcoming = -1
        for index in stride(from: count - 1, through: 0, by: -1) {
            if !heartRate[index].isNaN { upcoming = index }
            next[index] = upcoming
        }

        var prefix = [[Double]](repeating: [Double](repeating: 0, count: count + 1), count: 6)
        for index in 0..<count {
            let x = kilocalories[index]
            let y = heartRate[index]
            let both = !x.isNaN && !y.isNaN
            let (dn, dx, dy) = both ? (1.0, x, y) : (0, 0, 0)
            prefix[0][index + 1] = prefix[0][index] + dn
            prefix[1][index + 1] = prefix[1][index] + dx
            prefix[2][index + 1] = prefix[2][index] + dy
            prefix[3][index + 1] = prefix[3][index] + dx * dy
            prefix[4][index + 1] = prefix[4][index] + dx * dx
            prefix[5][index + 1] = prefix[5][index] + dy * dy
        }

        return MinuteGrid(
            origin: start,
            count: count,
            heartRate: heartRate,
            kilocalories: kilocalories,
            steps: steps,
            previousMeasured: previous,
            heartRateOrigin: bestOrigin,
            nextMeasured: next,
            prefix: prefix
        )
    }

    /// 把区间型样本（如 5 分钟的活动能量）平均摊到各分钟上；同一分钟的多个样本相加。
    private static func spread(_ samples: [ValueSample], start: Date, count: Int) -> [Double] {
        var values = [Double](repeating: Double.nan, count: count)
        for sample in samples {
            let first = Int(sample.start.timeIntervalSince(start) / 60)
            let last = max(first + 1, Int(ceil(sample.end.timeIntervalSince(start) / 60)))
            let lower = max(0, first)
            let upper = min(count, last)
            guard lower < upper else { continue }
            let perMinute = sample.value / Double(last - first)
            for index in lower..<upper {
                values[index] = (values[index].isNaN ? 0 : values[index]) + perMinute
            }
        }
        return values
    }

    /// 分钟索引（相对于 origin）。
    public func index(of date: Date) -> Int {
        Int(floor(date.timeIntervalSince(origin) / 60))
    }

    /// 最近 `windowMinutes` 分钟内（不含 `end`）拟合 HR = a + b·kcal/min。
    public func activityModel(endingBefore end: Int, windowMinutes: Int = 28 * 24 * 60) -> ActivityModel? {
        let upper = min(max(end, 0), count)
        let lower = max(0, upper - windowMinutes)
        guard upper > lower else { return nil }
        func sum(_ row: Int) -> Double { prefix[row][upper] - prefix[row][lower] }
        return ActivityModel.fit(
            count: sum(0),
            sumX: sum(1),
            sumY: sum(2),
            sumXY: sum(3),
            sumXX: sum(4),
            sumYY: sum(5)
        )
    }
}
