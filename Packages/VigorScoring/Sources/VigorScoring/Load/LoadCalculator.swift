import Foundation

/// 分钟心率的来源（PRD §2.2 约束 B）。
public enum MinuteSource: String, Sendable, Hashable, Codable {
    /// 有测量（运动或日间心率点）
    case measured
    /// 相邻测量的间隔 ≤ 15 分钟，线性插值
    case interpolated
    /// 空窗 15–60 分钟，用活动能量回归估算
    case estimated
    /// 空窗且无法估算，按静息心率处理
    case resting
    /// 超过 60 分钟没有心率，视为未佩戴，不计入负荷
    case unworn
}

public struct MinuteSample: Sendable, Hashable {
    public var index: Int
    public var bpm: Double?
    public var source: MinuteSource
}

public struct WorkoutLoad: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var activityType: String
    public var start: Date
    public var end: Date
    public var trimp: Double
    public var strain: Double
    /// 五个心率区间的分钟数（Z1…Z5）
    public var zoneMinutes: [Int]
    public var meanHeartRate: Double?
    public var peakHeartRate: Double?
    /// 1 分钟心率恢复（bpm），部分运动后产生
    public var recoveryOneMinute: Double?

    public init(
        id: UUID,
        activityType: String,
        start: Date,
        end: Date,
        trimp: Double,
        strain: Double,
        zoneMinutes: [Int],
        meanHeartRate: Double?,
        peakHeartRate: Double?,
        recoveryOneMinute: Double?
    ) {
        self.id = id
        self.activityType = activityType
        self.start = start
        self.end = end
        self.trimp = trimp
        self.strain = strain
        self.zoneMinutes = zoneMinutes
        self.meanHeartRate = meanHeartRate
        self.peakHeartRate = peakHeartRate
        self.recoveryOneMinute = recoveryOneMinute
    }
}

/// 一个周期（醒来 → 下一次主睡眠入睡）的负荷。
public struct CycleLoad: Sendable, Hashable, Codable {
    public var trimp: Double
    public var strain: Double
    public var countedMinutes: Int
    public var unwornMinutes: Int
    public var zoneMinutes: [Int]
    public var maxHeartRate: Double
    public var restingHeartRate: Double
    /// 活动能量回归是否启用（用于空窗估算）
    public var activityModelEnabled: Bool
    public var workouts: [WorkoutLoad]
    /// 当日压力（0–3）；没有符合条件的窗口时为 nil
    public var stress: Double?

    public init(
        trimp: Double,
        strain: Double,
        countedMinutes: Int,
        unwornMinutes: Int,
        zoneMinutes: [Int],
        maxHeartRate: Double,
        restingHeartRate: Double,
        activityModelEnabled: Bool,
        workouts: [WorkoutLoad],
        stress: Double?
    ) {
        self.trimp = trimp
        self.strain = strain
        self.countedMinutes = countedMinutes
        self.unwornMinutes = unwornMinutes
        self.zoneMinutes = zoneMinutes
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.activityModelEnabled = activityModelEnabled
        self.workouts = workouts
        self.stress = stress
    }
}

public enum LoadCalculator {
    public static let interpolationGapMinutes = 15
    public static let unwornGapMinutes = 60

    /// 分钟时间线（PRD §5.10 第 1 条）：测量 → 插值（≤15 分钟）→ 估算或静息（15–60 分钟）→ 未佩戴（>60 分钟）。
    public static func timeline(
        grid: MinuteGrid,
        from lower: Int,
        to upper: Int,
        restingHeartRate: Double,
        maxHeartRate: Double,
        model: ActivityModel?
    ) -> [MinuteSample] {
        let lo = max(0, lower)
        let hi = min(grid.count, upper)
        guard lo < hi else { return [] }
        return (lo..<hi).map { index in
            let measured = grid.heartRate[index]
            if !measured.isNaN {
                return MinuteSample(index: index, bpm: measured, source: .measured)
            }
            let previous = grid.previousMeasured[index]
            let next = grid.nextMeasured[index]
            guard previous >= 0, next >= 0 else {
                return MinuteSample(index: index, bpm: nil, source: .unworn)
            }
            let gap = next - previous
            if gap <= interpolationGapMinutes {
                let fraction = Double(index - previous) / Double(gap)
                let start = grid.heartRate[previous]
                let end = grid.heartRate[next]
                return MinuteSample(index: index, bpm: start + (end - start) * fraction, source: .interpolated)
            }
            if gap > unwornGapMinutes {
                return MinuteSample(index: index, bpm: nil, source: .unworn)
            }
            let kcal = grid.kilocalories[index]
            if let model, !kcal.isNaN {
                let predicted = min(max(model.predict(kilocaloriesPerMinute: kcal), restingHeartRate), maxHeartRate)
                return MinuteSample(index: index, bpm: predicted, source: .estimated)
            }
            return MinuteSample(index: index, bpm: restingHeartRate, source: .resting)
        }
    }

    /// 计算一个周期的负荷、运动详情与压力。
    /// - Parameters:
    ///   - window: 分钟索引区间 [lower, upper)
    ///   - workouts: 与该周期相关的训练（起点在周期内）
    ///   - recoveries: 心率恢复样本，用于取 1 分钟心率恢复
    ///   - quietWindowMeans: 周期内符合条件的安静窗口平均心率（见 `quietWindowMeans`）
    ///   - stressBaseline: 日间安静心率基线 μ_day（见 `Stress.daytimeBaseline`）
    ///   - zHRV: 当日 z_hrv，用于压力的 +0.5 修正
    public static func cycleLoad(
        grid: MinuteGrid,
        window lower: Int,
        upper: Int,
        workouts: [WorkoutSample],
        recoveries: [ValueSample],
        restingHeartRate: Double,
        maxHeartRate: Double,
        sex: BiologicalSex,
        model: ActivityModel?,
        quietWindowMeans: [Double],
        stressBaseline: Double,
        zHRV: Double?,
        config: ScoringConfig,
        compensation: [Int: Double] = [:]
    ) -> CycleLoad {
        let samples = timeline(
            grid: grid, from: lower, to: upper,
            restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate, model: model
        )
        var trimp = 0.0
        var counted = 0
        var unworn = 0
        var zones = [0, 0, 0, 0, 0]
        for sample in samples {
            // 骑行中心率缺失时的功率补偿（M6 §2.4）：替代该分钟的心率负荷；0 表示空窗
            if let replacement = compensation[sample.index] {
                if replacement > 0 {
                    trimp += replacement
                    counted += 1
                } else {
                    unworn += 1
                }
                continue
            }
            guard sample.source != .unworn, let bpm = sample.bpm else {
                unworn += 1
                continue
            }
            counted += 1
            let hrr = Strain.hrr(heartRate: bpm, restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate)
            trimp += Strain.trimpPerMinute(hrr: hrr, sex: sex)
            if let zone = Strain.zoneIndex(hrr: hrr) {
                zones[zone] += 1
            }
        }

        let workoutLoads = workouts.map { workout in
            workoutLoad(
                workout,
                grid: grid,
                recoveries: recoveries,
                restingHeartRate: restingHeartRate,
                maxHeartRate: maxHeartRate,
                sex: sex,
                model: model
            )
        }

        let stress = Stress.daily(
            windowStresses: quietWindowMeans.map { Stress.windowStress(meanHeartRate: $0, daytimeBaseline: stressBaseline) },
            zHRV: zHRV
        )

        return CycleLoad(
            trimp: trimp,
            strain: Strain.strain(fromTRIMP: trimp),
            countedMinutes: counted,
            unwornMinutes: unworn,
            zoneMinutes: zones,
            maxHeartRate: maxHeartRate,
            restingHeartRate: restingHeartRate,
            activityModelEnabled: model != nil,
            workouts: workoutLoads,
            stress: stress
        )
    }

    static func workoutLoad(
        _ workout: WorkoutSample,
        grid: MinuteGrid,
        recoveries: [ValueSample],
        restingHeartRate: Double,
        maxHeartRate: Double,
        sex: BiologicalSex,
        model: ActivityModel?
    ) -> WorkoutLoad {
        let lower = grid.index(of: workout.start)
        let upper = max(lower + 1, grid.index(of: workout.end))
        let samples = timeline(
            grid: grid, from: lower, to: upper,
            restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate, model: model
        )
        var trimp = 0.0
        var zones = [0, 0, 0, 0, 0]
        var bpms: [Double] = []
        for sample in samples where sample.source != .unworn {
            guard let bpm = sample.bpm else { continue }
            bpms.append(bpm)
            let hrr = Strain.hrr(heartRate: bpm, restingHeartRate: restingHeartRate, maxHeartRate: maxHeartRate)
            trimp += Strain.trimpPerMinute(hrr: hrr, sex: sex)
            if let zone = Strain.zoneIndex(hrr: hrr) {
                zones[zone] += 1
            }
        }
        let recovery = recoveries.first {
            $0.start >= workout.end && $0.start <= workout.end.addingTimeInterval(120)
        }?.value
        return WorkoutLoad(
            id: workout.uuid,
            activityType: workout.activityType,
            start: workout.start,
            end: workout.end,
            trimp: trimp,
            strain: Strain.strain(fromTRIMP: trimp),
            zoneMinutes: zones,
            meanHeartRate: Statistics.mean(bpms),
            peakHeartRate: bpms.max(),
            recoveryOneMinute: recovery
        )
    }

    /// 压力的候选窗口（PRD §5.12.2）：醒着的周期内每 15 分钟一个窗口，不含训练、步数 < 100、至少有 2 个心率测量点。
    /// 返回符合条件窗口的平均心率；日间安静心率与压力都由它推出。
    public static func quietWindowMeans(grid: MinuteGrid, window: Range<Int>, workouts: [WorkoutSample]) -> [Double] {
        let workoutRanges = workouts.map { (grid.index(of: $0.start), max(grid.index(of: $0.start) + 1, grid.index(of: $0.end))) }
        var means: [Double] = []
        var start = max(0, window.lowerBound)
        let end = min(grid.count, window.upperBound)
        while start + 15 <= end {
            let range = start..<(start + 15)
            start += 15
            if workoutRanges.contains(where: { $0.0 < range.upperBound && range.lowerBound < $0.1 }) { continue }
            let steps = range.reduce(0.0) { total, index in
                let value = grid.steps[index]
                return value.isNaN ? total : total + value
            }
            guard steps < 100 else { continue }
            let measured = range.compactMap { grid.heartRate[$0].isNaN ? nil : grid.heartRate[$0] }
            guard measured.count >= 2, let mean = Statistics.mean(measured) else { continue }
            means.append(mean)
        }
        return means
    }
}
