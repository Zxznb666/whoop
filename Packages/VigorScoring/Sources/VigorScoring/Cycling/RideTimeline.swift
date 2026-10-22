import Foundation
import VigorFIT

/// 骑行详情曲线的一个点（施工文档 M6 补完 C1）。界面不直接处理原始样本。
public struct RideTimelinePoint: Sendable, Hashable, Codable {
    /// 距骑行开始的秒数（桶的中点）
    public var offset: TimeInterval
    /// 桶内平均；没有测量时为 nil
    public var heartRate: Double?
    /// 桶内平均；没有测量时为 nil（不是 0）
    public var power: Double?
    /// 桶内超过一半的秒处于暂停
    public var paused: Bool

    public init(offset: TimeInterval, heartRate: Double?, power: Double?, paused: Bool) {
        self.offset = offset
        self.heartRate = heartRate
        self.power = power
        self.paused = paused
    }
}

public struct RideTimeline: Sendable, Hashable, Codable {
    public var points: [RideTimelinePoint]
    public var heartRateSource: HeartRateOrigin?
    public var powerSource: PowerSource
    /// 分圈（只有导入的 FIT 才有；没有分圈时为空数组）
    public var laps: [RideLapSummary]

    public init(points: [RideTimelinePoint], heartRateSource: HeartRateOrigin?, powerSource: PowerSource, laps: [RideLapSummary]) {
        self.points = points
        self.heartRateSource = heartRateSource
        self.powerSource = powerSource
        self.laps = laps
    }
}

/// 分圈摘要。`index` 从 1 开始（界面的圈号）。
public struct RideLapSummary: Sendable, Hashable, Codable {
    public var index: Int
    public var start: Date
    /// 有效骑行秒（不含暂停）
    public var durationSeconds: Int
    public var distanceMeters: Double?
    public var averagePower: Double?
    /// 只在 ≥ 30 秒时计算
    public var normalizedPower: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?

    public init(
        index: Int,
        start: Date,
        durationSeconds: Int,
        distanceMeters: Double?,
        averagePower: Double?,
        normalizedPower: Double?,
        averageHeartRate: Double?,
        maxHeartRate: Double?
    ) {
        self.index = index
        self.start = start
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averagePower = averagePower
        self.normalizedPower = normalizedPower
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
    }
}

public enum RideTimelineBuilder {
    /// HealthKit 功率样本之间不超过这个秒数的空档，沿用前一个测量值（与 D-128 一致）；更长的空档为 nil。
    static let shortGapSeconds = 5

    public static func build(
        ride: RideResult,
        snapshot: HealthSnapshot,
        importedRides: [RideStream],
        maxPoints: Int = 600
    ) -> RideTimeline {
        let duration = max(0, Int(ceil(ride.end.timeIntervalSince(ride.start))))
        guard duration > 0 else {
            return RideTimeline(points: [], heartRateSource: nil, powerSource: .none, laps: [])
        }
        let fits = matchingStreams(ride: ride, importedRides: importedRides)

        var heartRate = [Double?](repeating: nil, count: duration)
        var power = [Double?](repeating: nil, count: duration)
        var distance = [Double?](repeating: nil, count: duration)
        var paused = [Bool](repeating: false, count: duration)
        var heartRateSource: HeartRateOrigin?
        var powerSource = PowerSource.none

        if fits.isEmpty {
            // 心率：快照中落在骑行窗口内的样本，按 D-130 的来源优先级逐分钟去重（复用分钟网格）
            let window = ride.start.addingTimeInterval(-120)...ride.end.addingTimeInterval(120)
            let samples = snapshot.heartRate.filter { window.contains($0.date) }
            let workouts = snapshot.workouts.filter { $0.end >= window.lowerBound && $0.start <= window.upperBound }
            let tagged = HeartRateOriginClassifier.tag(samples, workouts: workouts)
            let grid = MinuteGrid.build(origin: ride.start, end: ride.end, taggedHeartRate: tagged, activeEnergy: [], steps: [])
            heartRateSource = grid.heartRateOrigin.compactMap { $0 }.max()
            for second in 0..<duration {
                let minute = grid.index(of: ride.start.addingTimeInterval(Double(second)))
                guard minute >= 0, minute < grid.count else { continue }
                let bpm = grid.heartRate[minute]
                heartRate[second] = bpm.isNaN ? nil : bpm
            }
            // 功率：快照中的样本按真实时间区间展开
            for sample in snapshot.cyclingPower where sample.end > ride.start && sample.start < ride.end {
                let first = max(0, Int(floor(sample.start.timeIntervalSince(ride.start))))
                let last = min(duration, max(first + 1, Int(ceil(sample.end.timeIntervalSince(ride.start)))))
                guard first < last else { continue }
                for second in first..<last {
                    power[second] = sample.value
                }
            }
            fillShortGaps(&power, maxGap: shortGapSeconds)
            if power.contains(where: { $0 != nil }) { powerSource = .healthKit }
        } else {
            // FIT：心率、功率、距离、暂停都用逐秒数组
            for stream in fits {
                let offset = Int(stream.start.timeIntervalSince(ride.start).rounded())
                for (index, value) in stream.heartRate.enumerated() {
                    let second = offset + index
                    guard let value, second >= 0, second < duration else { continue }
                    heartRate[second] = Double(value)
                }
                for (index, value) in stream.power.enumerated() {
                    let second = offset + index
                    guard let value, second >= 0, second < duration else { continue }
                    power[second] = Double(value)
                }
                for (index, value) in stream.distance.enumerated() {
                    let second = offset + index
                    guard let value, second >= 0, second < duration else { continue }
                    distance[second] = value
                }
                for pause in stream.pauses {
                    for index in pause {
                        let second = offset + index
                        guard second >= 0, second < duration else { continue }
                        paused[second] = true
                    }
                }
            }
            if heartRate.contains(where: { $0 != nil }) { heartRateSource = .fitImport }
            if power.contains(where: { $0 != nil }) { powerSource = .fit }
        }

        let points = downsample(duration: duration, maxPoints: maxPoints, heartRate: heartRate, power: power, paused: paused, rideStart: ride.start)
        let laps = fits.isEmpty ? [] : lapSummaries(
            fits: fits,
            rideStart: ride.start,
            duration: duration,
            heartRate: heartRate,
            power: power,
            distance: distance,
            paused: paused
        )
        return RideTimeline(points: points, heartRateSource: heartRateSource, powerSource: powerSource, laps: laps)
    }

    /// 成员中的导入骑行（`RideResult.id` 中 `fit-<fileID>` 的部分）。
    static func matchingStreams(ride: RideResult, importedRides: [RideStream]) -> [RideStream] {
        let ids = Set(ride.id.split(separator: "|").compactMap { part -> String? in
            part.hasPrefix("fit-") ? String(part.dropFirst(4)) : nil
        })
        guard !ids.isEmpty else { return [] }
        return importedRides.filter { ids.contains($0.fileID) }.sorted { $0.start < $1.start }
    }

    /// 只填补不超过 `maxGap` 秒的空档（沿用前一个测量值），更长的空档保持 nil。
    static func fillShortGaps(_ values: inout [Double?], maxGap: Int) {
        var index = 0
        var lastIndex: Int?
        while index < values.count {
            if values[index] != nil {
                if let last = lastIndex, index - last > 1, index - last - 1 <= maxGap, let value = values[last] {
                    for gap in (last + 1)..<index { values[gap] = value }
                }
                lastIndex = index
            }
            index += 1
        }
    }

    /// 把 1 秒序列按 `min(maxPoints, 总秒数)` 个等宽桶平均；桶内没有测量值时为 nil，线会在那里断开。
    static func downsample(
        duration: Int,
        maxPoints: Int,
        heartRate: [Double?],
        power: [Double?],
        paused: [Bool],
        rideStart: Date
    ) -> [RideTimelinePoint] {
        let buckets = min(maxPoints, duration)
        guard buckets > 0 else { return [] }
        var points: [RideTimelinePoint] = []
        points.reserveCapacity(buckets)
        for bucket in 0..<buckets {
            let lower = bucket * duration / buckets
            let upper = (bucket + 1) * duration / buckets
            var hrSum = 0.0, hrCount = 0
            var pwSum = 0.0, pwCount = 0
            var pausedCount = 0
            for second in lower..<upper {
                if let bpm = heartRate[second] { hrSum += bpm; hrCount += 1 }
                if let watts = power[second] { pwSum += watts; pwCount += 1 }
                if paused[second] { pausedCount += 1 }
            }
            points.append(RideTimelinePoint(
                offset: (Double(lower) + Double(upper)) / 2,
                heartRate: hrCount > 0 ? hrSum / Double(hrCount) : nil,
                power: pwCount > 0 ? pwSum / Double(pwCount) : nil,
                paused: pausedCount * 2 > (upper - lower)
            ))
        }
        return points
    }

    static func lapSummaries(
        fits: [RideStream],
        rideStart: Date,
        duration: Int,
        heartRate: [Double?],
        power: [Double?],
        distance: [Double?],
        paused: [Bool]
    ) -> [RideLapSummary] {
        // 分圈 NP 与整次骑行同一口径（D-128）：短空档沿用前值、长空档用本次平均功率、暂停为 0；
        // 整次骑行的功率覆盖率不足 50%（D-129）时，分圈也不出 NP。
        let present = power.map { $0 != nil }
        let movingSeconds = paused.filter { !$0 }.count
        let measuredSeconds = present.indices.filter { present[$0] && !paused[$0] }.count
        let powerUsable = movingSeconds > 0 && Double(measuredSeconds) / Double(movingSeconds) >= 0.5
        var filledPower = power.map { $0 ?? 0 }
        GroupSeries.fillGaps(&filledPower, present: present, paused: paused)
        let laps = fits.flatMap(\.laps).compactMap { lap -> (Date, Date)? in
            guard let start = lap.startTime, let end = lap.endTime, end > start else { return nil }
            return (start, end)
        }.sorted { $0.0 < $1.0 }
        return laps.enumerated().map { offset, bounds in
            let lower = min(duration, max(0, Int(floor(bounds.0.timeIntervalSince(rideStart)))))
            let upper = min(duration, max(lower, Int(ceil(bounds.1.timeIntervalSince(rideStart)))))
            let seconds = lower..<upper
            let watts = seconds.compactMap { power[$0] }
            let bpm = seconds.compactMap { heartRate[$0] }
            let meters = seconds.compactMap { distance[$0] }
            let padded = seconds.map { paused[$0] ? 0 : filledPower[$0] }
            return RideLapSummary(
                index: offset + 1,
                start: bounds.0,
                durationSeconds: seconds.filter { !paused[$0] }.count,
                distanceMeters: meters.count >= 2 ? (meters.max() ?? 0) - (meters.min() ?? 0) : nil,
                averagePower: watts.isEmpty ? nil : watts.reduce(0, +) / Double(watts.count),
                normalizedPower: powerUsable && !watts.isEmpty ? CyclingMath.normalizedPower(padded) : nil,
                averageHeartRate: bpm.isEmpty ? nil : bpm.reduce(0, +) / Double(bpm.count),
                maxHeartRate: bpm.max()
            )
        }
    }
}
