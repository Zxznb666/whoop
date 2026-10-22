import Foundation
import VigorFIT

/// 功率的来源（界面的来源徽章用）。
public enum PowerSource: String, Sendable, Hashable, Codable {
    case none
    /// 手表或其他 App 写入的 `cyclingPower`
    case healthKit
    /// 导入的 FIT 文件
    case fit
}

public enum FTPSource: String, Sendable, Hashable, Codable {
    case manual
    case healthKit
    case estimated
}

public struct FTPEstimate: Sendable, Hashable, Codable {
    public var watts: Double
    public var source: FTPSource

    public init(watts: Double, source: FTPSource) {
        self.watts = watts
        self.source = source
    }
}

/// 一次骑行（分组后）的指标（施工文档 §3、§6）。
public struct RideResult: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var start: Date
    public var end: Date
    /// 合并的成员来源标签，例如 “Apple Watch”、“Garmin 写入”、“FIT 导入”
    public var sourceLabels: [String]
    public var memberCount: Int
    /// 有效骑行秒数（剔除暂停）
    public var movingSeconds: Int
    public var heartRateOrigin: HeartRateOrigin?
    public var powerSource: PowerSource
    /// 有效功率覆盖率（有测量的秒 ÷ 有效骑行秒）；没有功率来源时为 nil。低于 50% 时不计算功率指标。
    public var powerCoverage: Double?
    public var normalizedPower: Double?
    public var intensityFactor: Double?
    public var tss: Double?
    public var mechanicalWorkKJ: Double?
    public var wattsPerKilogram: Double?
    public var averageHeartRate: Double?
    public var efficiencyFactor: Double?
    /// 有氧解耦（%），只对 ≥ 60 分钟的骑行计算
    public var aerobicDecoupling: Double?
    /// 功率区间秒数（Z1…Z7）
    public var zoneSeconds: [Int]?
    public var powerCurve: [Int: Double]
    /// 因心率缺失而补偿的分钟数
    public var compensatedMinutes: Int
    /// 心率缺失且无法补偿：负荷可能低估
    public var loadMayBeUnderestimated: Bool
    /// 本次 TRIMP（只统计有心率的分钟，不含补偿）；用于拟合 k
    public var measuredTRIMP: Double
}

public struct CyclingInput: Sendable {
    public var workouts: [WorkoutSample]
    public var importedRides: [RideStream]
    public var cyclingPower: [ValueSample]
    public var ftpSamples: [ValueSample]
    public var manualFTP: Double?
    public var weightKilograms: Double?
    public var restingHeartRate: Double
    public var maxHeartRate: Double
    public var sex: BiologicalSex
    public var now: Date
    public var calendar: Calendar

    public init(
        workouts: [WorkoutSample] = [],
        importedRides: [RideStream] = [],
        cyclingPower: [ValueSample] = [],
        ftpSamples: [ValueSample] = [],
        manualFTP: Double? = nil,
        weightKilograms: Double? = nil,
        restingHeartRate: Double,
        maxHeartRate: Double,
        sex: BiologicalSex,
        now: Date,
        calendar: Calendar
    ) {
        self.workouts = workouts
        self.importedRides = importedRides
        self.cyclingPower = cyclingPower
        self.ftpSamples = ftpSamples
        self.manualFTP = manualFTP
        self.weightKilograms = weightKilograms
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
        self.sex = sex
        self.now = now
        self.calendar = calendar
    }
}

public struct CyclingOutput: Sendable, Codable, Equatable {
    public var rides: [RideResult]
    public var ftp: FTPEstimate?
    public var powerModel: PowerHeartModel?
    /// k = 历史骑行 TRIMP ÷ TSS 的中位数（至少 5 次骑行）
    public var trimpPerTSS: Double?
    /// 分钟索引 → 替代该分钟心率负荷的 TRIMP；0 表示按空窗处理（负荷可能低估）
    public var compensation: [Int: Double]
    /// 体能管理序列（从第一次骑行那天到 `now` 所在的那天）
    public var pmc: [PMCPoint]
    /// 最近 90 天每个标准时长的最佳平均功率
    public var powerCurve90: [Int: Double]

    public init(
        rides: [RideResult],
        ftp: FTPEstimate?,
        powerModel: PowerHeartModel?,
        trimpPerTSS: Double?,
        compensation: [Int: Double],
        pmc: [PMCPoint],
        powerCurve90: [Int: Double]
    ) {
        self.rides = rides
        self.ftp = ftp
        self.powerModel = powerModel
        self.trimpPerTSS = trimpPerTSS
        self.compensation = compensation
        self.pmc = pmc
        self.powerCurve90 = powerCurve90
    }

    public static let empty = CyclingOutput(
        rides: [], ftp: nil, powerModel: nil, trimpPerTSS: nil, compensation: [:], pmc: [], powerCurve90: [:]
    )
}

public enum CyclingAnalysis {
    /// 心率缺失达到这个分钟数才启用功率补偿（§2.4）
    public static let compensationMinutes = 5
    /// 自动估算 FTP 的回看窗口（天）
    public static let autoFTPWindowDays = 90
    /// 计入 k 拟合的最少骑行次数
    public static let minimumRidesForK = 5

    public static func run(_ input: CyclingInput, grid: MinuteGrid) -> CyclingOutput {
        let candidates = candidatesFrom(input)
        let groups = RideGrouping.group(candidates)
        let importedByID = Dictionary(input.importedRides.map { ($0.fileID, $0) }, uniquingKeysWith: { first, _ in first })

        let sortedPower = input.cyclingPower.sorted { $0.start < $1.start }
        var series: [GroupSeries] = []
        for group in groups {
            if var built = GroupSeries.build(group, grid: grid, input: input, sortedPower: sortedPower, importedByID: importedByID) {
                built.measuredTRIMP = measuredTRIMP(built, grid: grid, input: input)
                series.append(built)
            }
        }
        guard !series.isEmpty else { return .empty }

        let ftp = resolveFTP(input, series: series)
        let trimpPerTSS = ftp.flatMap { trimpRatio(series: series, grid: grid, ftp: $0.watts, input: input) }

        let model = PowerHeartModelFit.fit(series: series, grid: grid)

        var compensation: [Int: Double] = [:]
        var compensatedCounts: [Int] = []
        var underestimated: [Bool] = []
        for item in series {
            let result = compensate(item, grid: grid, model: model, ftp: ftp?.watts, k: trimpPerTSS, input: input)
            for (minute, value) in result.minuteTRIMP { compensation[minute] = value }
            compensatedCounts.append(result.minutes)
            underestimated.append(result.flagged)
        }

        var rides: [RideResult] = []
        for (index, item) in series.enumerated() {
            rides.append(rideResult(item, grid: grid, ftp: ftp?.watts, input: input, compensatedMinutes: compensatedCounts[index], underestimated: underestimated[index]))
        }

        var tssByDay: [Date: Double] = [:]
        for ride in rides {
            if let tss = ride.tss {
                tssByDay[input.calendar.startOfDay(for: ride.start), default: 0] += tss
            }
        }
        let pmc: [PMCPoint]
        if let first = rides.map(\.start).min() {
            pmc = PerformanceManagement.series(tssByDay: tssByDay, from: first, through: input.now, calendar: input.calendar)
        } else {
            pmc = []
        }

        let windowStart = input.now.addingTimeInterval(-Double(autoFTPWindowDays) * 86_400)
        var curve: [Int: Double] = [:]
        for item in series where item.end >= windowStart && item.powerUsable {
            for (duration, value) in item.powerCurve {
                curve[duration] = max(curve[duration] ?? 0, value)
            }
        }

        return CyclingOutput(
            rides: rides,
            ftp: ftp,
            powerModel: model,
            trimpPerTSS: trimpPerTSS,
            compensation: compensation,
            pmc: pmc,
            powerCurve90: curve
        )
    }

    static func candidatesFrom(_ input: CyclingInput) -> [RideCandidate] {
        var candidates = input.workouts
            .filter { $0.activityType == "cycling" }
            .map { RideCandidate(source: .workout($0.uuid, productType: $0.productType, sourceBundleID: $0.sourceBundleID), start: $0.start, end: $0.end) }
        candidates += input.importedRides
            .filter { $0.sport == nil || $0.sport == 2 }
            .map { RideCandidate(source: .imported($0.fileID), start: $0.start, end: $0.start.addingTimeInterval(Double($0.durationSeconds))) }
        return candidates
    }

    /// FTP：手动设置 > HealthKit 的 `cyclingFunctionalThresholdPower` > 最近 90 天最佳 20 分钟 × 0.95。
    static func resolveFTP(_ input: CyclingInput, series: [GroupSeries]) -> FTPEstimate? {
        if let manual = input.manualFTP, manual > 0 {
            return FTPEstimate(watts: manual, source: .manual)
        }
        if let latest = input.ftpSamples.max(by: { $0.end < $1.end }), latest.value > 0 {
            return FTPEstimate(watts: latest.value, source: .healthKit)
        }
        let windowStart = input.now.addingTimeInterval(-Double(autoFTPWindowDays) * 86_400)
        let best = series
            .filter { $0.end >= windowStart && $0.powerUsable }
            .compactMap { $0.powerCurve[1200] }
            .max()
        guard let best else { return nil }
        return FTPEstimate(watts: CyclingMath.estimatedFTP(bestTwentyMinutePower: best), source: .estimated)
    }

    /// k：有 FTP 与心率的骑行中，TRIMP ÷ TSS 的中位数。
    static func trimpRatio(series: [GroupSeries], grid: MinuteGrid, ftp: Double, input: CyclingInput) -> Double? {
        var ratios: [Double] = []
        for item in series {
            let tss = CyclingMath.tss(durationSeconds: Double(item.movingSeconds), normalizedPower: item.normalizedPower ?? 0, ftp: ftp)
            let trimp = item.measuredTRIMP
            if tss > 0, trimp > 0 { ratios.append(trimp / tss) }
        }
        guard ratios.count >= minimumRidesForK else { return nil }
        return Statistics.median(ratios)
    }

    static func measuredTRIMP(_ item: GroupSeries, grid: MinuteGrid, input: CyclingInput) -> Double {
        var total = 0.0
        for minute in item.lowerMinute..<item.upperMinute {
            let bpm = grid.heartRate[minute]
            guard !bpm.isNaN else { continue }
            let hrr = Strain.hrr(heartRate: bpm, restingHeartRate: input.restingHeartRate, maxHeartRate: input.maxHeartRate)
            total += Strain.trimpPerMinute(hrr: hrr, sex: input.sex)
        }
        return total
    }

    struct Compensation {
        var minuteTRIMP: [Int: Double] = [:]
        var minutes = 0
        var flagged = false
    }

    /// 心率缺失补偿（§2.4）：连续 ≥ 5 分钟无心率且有功率时，优先用回归模型估算心率，其次用 k·TSS，都不满足则按空窗处理并标记。
    static func compensate(
        _ item: GroupSeries,
        grid: MinuteGrid,
        model: PowerHeartModel?,
        ftp: Double?,
        k: Double?,
        input: CyclingInput
    ) -> Compensation {
        var result = Compensation()
        // 功率数据不足的骑行不做补偿：功率序列不可靠，补偿会放大错误
        guard item.powerUsable else { return result }
        var runStart: Int?
        for minute in item.lowerMinute...item.upperMinute {
            let hasGap = minute < item.upperMinute
                && grid.heartRate[minute].isNaN
                && item.minutePowerPresent[minute - item.lowerMinute]
            if hasGap {
                if runStart == nil { runStart = minute }
                continue
            }
            if let start = runStart, minute - start >= compensationMinutes {
                fill(start..<minute, item: item, p30: item.p30, model: model, ftp: ftp, k: k, input: input, into: &result)
            }
            runStart = nil
        }
        return result
    }

    private static func fill(
        _ minutes: Range<Int>,
        item: GroupSeries,
        p30: [Double],
        model: PowerHeartModel?,
        ftp: Double?,
        k: Double?,
        input: CyclingInput,
        into result: inout Compensation
    ) {
        result.minutes += minutes.count
        for minute in minutes {
            let seconds = (minute - item.lowerMinute) * 60..<((minute - item.lowerMinute) * 60 + 60)
            if let model {
                var trimp = 0.0
                for second in seconds where second < item.power.count {
                    let lagged = second - PowerHeartModel.lagSeconds
                    let x = lagged >= 0 && lagged < p30.count ? p30[lagged] : 0
                    let bpm = min(max(model.predict(p30: x), input.restingHeartRate), input.maxHeartRate)
                    let hrr = Strain.hrr(heartRate: bpm, restingHeartRate: input.restingHeartRate, maxHeartRate: input.maxHeartRate)
                    trimp += Strain.trimpPerMinute(hrr: hrr, sex: input.sex) / 60
                }
                result.minuteTRIMP[minute] = trimp
            } else if let ftp, let k {
                var tss = 0.0
                for second in seconds where second < item.power.count {
                    let ratio = item.power[second] / ftp
                    tss += ratio * ratio * 100 / 3600
                }
                result.minuteTRIMP[minute] = k * tss
            } else {
                result.minuteTRIMP[minute] = 0
                result.flagged = true
            }
        }
    }

    /// 每秒的滑动平均：第 t 项为 [t − window + 1, t] 的平均（不足时取可用部分）。
    static func rollingWindowAverage(_ values: [Double], window: Int) -> [Double] {
        values.withUnsafeBufferPointer { input -> [Double] in
            let count = input.count
            var result = [Double](repeating: 0, count: count)
            result.withUnsafeMutableBufferPointer { output in
                var sum = 0.0
                let head = min(window, count)
                for index in 0..<head {
                    sum += input[index]
                    output[index] = sum / Double(index + 1)
                }
                let divisor = Double(window)
                var index = head
                while index < count {
                    sum += input[index] - input[index - window]
                    output[index] = sum / divisor
                    index += 1
                }
            }
            return result
        }
    }

    static func rideResult(
        _ item: GroupSeries,
        grid: MinuteGrid,
        ftp: Double?,
        input: CyclingInput,
        compensatedMinutes: Int,
        underestimated: Bool
    ) -> RideResult {
        // 没有任何功率数据的骑行（例如只有 HealthKit 心率的训练）不计算功率指标，避免把全零序列当作真实功率
        let hasPower = item.powerUsable
        let np = hasPower ? item.normalizedPower : nil
        let moving = max(0, item.power.count - item.pausedSeconds)
        var result = RideResult(
            id: item.group.members.map(\.idKey).sorted().joined(separator: "|"),
            start: item.group.start,
            end: item.group.end,
            sourceLabels: item.group.members.map(\.sourceLabel).uniqued(),
            memberCount: item.group.members.count,
            movingSeconds: moving,
            heartRateOrigin: item.heartRateOrigin,
            powerSource: item.powerSource,
            powerCoverage: item.powerSource == .none ? nil : item.powerCoverage,
            normalizedPower: np,
            intensityFactor: nil,
            tss: nil,
            mechanicalWorkKJ: hasPower ? CyclingMath.mechanicalWorkKJ(item.power) : nil,
            wattsPerKilogram: nil,
            averageHeartRate: item.averageHeartRate,
            efficiencyFactor: nil,
            aerobicDecoupling: nil,
            zoneSeconds: nil,
            powerCurve: hasPower ? item.powerCurve : [:],
            compensatedMinutes: compensatedMinutes,
            loadMayBeUnderestimated: underestimated,
            measuredTRIMP: item.measuredTRIMP
        )
        if let np, let weight = input.weightKilograms, weight > 0 {
            result.wattsPerKilogram = np / weight
        }
        if let np, let average = item.averageHeartRate, average > 0 {
            result.efficiencyFactor = CyclingMath.efficiencyFactor(normalizedPower: np, averageHeartRate: average)
        }
        if let ftp, ftp > 0, hasPower, let np {
            result.intensityFactor = CyclingMath.intensityFactor(normalizedPower: np, ftp: ftp)
            result.tss = CyclingMath.tss(durationSeconds: Double(moving), normalizedPower: np, ftp: ftp)
            result.zoneSeconds = CyclingMath.zoneSeconds(item.power, ftp: ftp)
        }
        if hasPower, item.power.count >= 3600, moving >= 3600 {
            result.aerobicDecoupling = decoupling(item, grid: grid)
        }
        return result
    }

    /// 有氧解耦：按时长对半分（分钟粒度），分别计算 NP 与平均心率。
    static func decoupling(_ item: GroupSeries, grid: MinuteGrid) -> Double? {
        let middle = (item.upperMinute - item.lowerMinute) / 2
        guard middle > 0 else { return nil }
        let firstPower = Array(item.power[0..<(middle * 60)])
        let secondPower = Array(item.power[(middle * 60)...])
        let firstHR = (item.lowerMinute..<(item.lowerMinute + middle)).map { grid.heartRate[$0] }.filter { !$0.isNaN }
        let secondHR = ((item.lowerMinute + middle)..<item.upperMinute).map { grid.heartRate[$0] }.filter { !$0.isNaN }
        guard let npFirst = CyclingMath.normalizedPower(firstPower),
              let npSecond = CyclingMath.normalizedPower(secondPower),
              let hrFirst = Statistics.mean(firstHR), let hrSecond = Statistics.mean(secondHR),
              hrFirst > 0, hrSecond > 0 else { return nil }
        return CyclingMath.aerobicDecoupling(
            firstHalfEF: CyclingMath.efficiencyFactor(normalizedPower: npFirst, averageHeartRate: hrFirst),
            secondHalfEF: CyclingMath.efficiencyFactor(normalizedPower: npSecond, averageHeartRate: hrSecond)
        )
    }
}

/// 一组骑行在分钟网格上的 1 Hz 序列。下标 0 = 所在分钟的整点。
struct GroupSeries {
    var group: RideGroup
    var lowerMinute: Int
    var upperMinute: Int
    var start: Date
    var end: Date
    /// 1 Hz 功率，暂停与缺失为 0
    var power: [Double]
    /// 每秒是否有功率测量（缺失的 0 为 false）
    var powerPresent: [Bool]
    var pausedSeconds: Int
    var powerSource: PowerSource
    /// 有效功率覆盖率（有测量的秒 ÷ 有效骑行秒）
    var powerCoverage: Double = 0
    /// 覆盖率 ≥ 50% 时为真；否则不计算 NP、功率区间、功率曲线与功率补偿
    var powerSufficient: Bool = false
    var heartRateOrigin: HeartRateOrigin?
    var averageHeartRate: Double?
    /// FIT 导入的逐秒心率（组内下标）；没有 FIT 心率时为 nil。其余秒使用分钟网格的去重值。
    var fitHeartRate: [Int?]?
    /// 每个分钟（相对 `lowerMinute`）内是否有功率测量
    var minutePowerPresent: [Bool]
    /// 30 秒滑动平均功率（与 `power` 同长）
    var p30: [Double]
    /// 只统计有心率分钟的 TRIMP（不含补偿）
    var measuredTRIMP: Double = 0
    /// 整段骑行的 NP（暂停为 0）与功率曲线，构建时计算一次
    var normalizedPower: Double?
    var powerCurve: [Int: Double] = [:]
    var movingSeconds: Int { power.count - pausedSeconds }
    /// 功率可用于指标：有功率来源且覆盖率足够
    var powerUsable: Bool { powerSource != .none && powerSufficient }

    /// 缺失的秒（非暂停）：不超过 5 秒的空档沿用前一个测量值；更长的空档用本次骑行的平均功率。暂停保持 0。
    static func fillGaps(_ power: inout [Double], present: [Bool], paused: [Bool], shortGapSeconds: Int = 5) {
        let measured = present.indices.filter { present[$0] }
        guard !measured.isEmpty else { return }
        let mean = measured.reduce(0.0) { $0 + power[$1] } / Double(measured.count)
        var lastValue = power[measured[0]]
        var index = 0
        while index < power.count {
            if present[index] {
                lastValue = power[index]
                index += 1
                continue
            }
            if paused[index] {
                index += 1
                continue
            }
            var end = index
            while end < power.count, !present[end], !paused[end] { end += 1 }
            let fill = (end - index) <= shortGapSeconds ? lastValue : mean
            for second in index..<end { power[second] = fill }
            index = end
        }
    }

    /// 组内第 `second` 秒的心率：FIT 逐秒优先，否则为分钟网格的去重值；没有测量时为 nil。
    static func heartRate(second: Int, fit: [Int?]?, lower: Int, minuteHeartRate: [Double]) -> Double? {
        if let fit, second < fit.count, let bpm = fit[second] { return Double(bpm) }
        let minute = lower + second / 60
        guard minute < minuteHeartRate.count else { return nil }
        let bpm = minuteHeartRate[minute]
        return bpm.isNaN ? nil : bpm
    }

    /// 组内的平均心率。没有 FIT 心率时，每个有测量的分钟恰好含 60 秒，因此直接按分钟加权（与逐秒平均相同）。
    static func averageHeartRate(fit: [Int?]?, lower: Int, upper: Int, grid: MinuteGrid) -> Double? {
        if fit == nil {
            var sum = 0.0
            var minutes = 0
            for minute in lower..<upper where !grid.heartRate[minute].isNaN {
                sum += grid.heartRate[minute]
                minutes += 1
            }
            return minutes > 0 ? sum / Double(minutes) : nil
        }
        var sum = 0.0
        var count = 0
        for second in 0..<((upper - lower) * 60) {
            if let bpm = heartRate(second: second, fit: fit, lower: lower, minuteHeartRate: grid.heartRate) {
                sum += bpm
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : nil
    }

    /// 组内第 `second` 秒的心率（实例方法，供回归使用）。
    func heartRate(second: Int, minuteHeartRate: [Double]) -> Double? {
        GroupSeries.heartRate(second: second, fit: fitHeartRate, lower: lowerMinute, minuteHeartRate: minuteHeartRate)
    }

    /// 已按开始时间排序的功率样本中，与 [from, to) 可能重叠的样本（下界回退一格，覆盖跨越窗口起点的样本）。
    static func powerWindow(_ sorted: [ValueSample], from: Date, to: Date) -> ArraySlice<ValueSample> {
        let low = max(0, firstIndex(sorted, from: from) { $0.start } - 1)
        var upper = low
        while upper < sorted.count, sorted[upper].start < to { upper += 1 }
        return sorted[low..<upper]
    }

    /// 第一个键值不小于 `from` 的下标。
    static func firstIndex<T>(_ sorted: [T], from: Date, key: (T) -> Date) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if key(sorted[middle]) < from { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// 分钟 `minute`（绝对分钟索引）内是否有任何功率测量
    func hasPower(minute: Int, lower: Int) -> Bool {
        let first = (minute - lower) * 60
        guard first >= 0 else { return false }
        return (first..<min(first + 60, powerPresent.count)).contains { powerPresent[$0] }
    }

    static func build(
        _ group: RideGroup,
        grid: MinuteGrid,
        input: CyclingInput,
        sortedPower: [ValueSample],
        importedByID: [String: RideStream]
    ) -> GroupSeries? {
        let lower = max(0, grid.index(of: group.start))
        let upper = min(grid.count, max(lower + 1, grid.index(of: group.end)))
        guard lower < upper else { return nil }
        let origin = grid.origin.addingTimeInterval(Double(lower) * 60)
        let seconds = (upper - lower) * 60
        func secondIndex(_ date: Date) -> Int {
            Int(floor(date.timeIntervalSince(origin)))
        }

        var power = [Double](repeating: 0, count: seconds)
        var present = [Bool](repeating: false, count: seconds)
        var powerSource = PowerSource.none
        let windowEnd = origin.addingTimeInterval(Double(seconds))

        // HealthKit 功率：样本覆盖的真实时间区间内的秒取该值；区间之外的秒不做任何改动（空档不是 0 W）。
        // 只考虑与本组窗口有重叠的样本，避免把窗口之前的样本写进第 0 秒。
        for sample in powerWindow(sortedPower, from: origin, to: windowEnd) where sample.end > origin && sample.start < windowEnd {
            let first = max(0, Int(floor(sample.start.timeIntervalSince(origin))))
            let last = min(seconds, max(first + 1, Int(ceil(sample.end.timeIntervalSince(origin)))))
            for second in first..<last {
                power[second] = sample.value
                present[second] = true
            }
            powerSource = .healthKit
        }

        // 导入的 FIT：整段覆盖 HealthKit 的功率（FIT 优先）；暂停区间为 0
        var pausedFlags = [Bool](repeating: false, count: seconds)
        for member in group.members {
            guard case .imported(let fileID) = member.source, let ride = importedByID[fileID] else { continue }
            let rideOffset = secondIndex(ride.start)
            var hasFITPower = false
            for (index, value) in ride.power.enumerated() {
                let second = rideOffset + index
                guard second >= 0, second < seconds else { continue }
                power[second] = Double(value ?? 0)
                present[second] = value != nil
                if value != nil { hasFITPower = true }
            }
            for pause in ride.pauses {
                for index in pause {
                    let second = rideOffset + index
                    guard second >= 0, second < seconds else { continue }
                    power[second] = 0
                    present[second] = false
                    pausedFlags[second] = true
                }
            }
            if hasFITPower { powerSource = .fit }
        }

        // 覆盖率：有测量的秒 ÷ 有效骑行秒（暂停不计入）。低于 50% 时功率指标不可用。
        let pausedCount = pausedFlags.reduce(0) { $0 + ($1 ? 1 : 0) }
        let validCount = present.reduce(0) { $0 + ($1 ? 1 : 0) }
        let movingCount = seconds - pausedCount
        let coverage = movingCount > 0 ? Double(validCount) / Double(movingCount) : 0
        let sufficient = powerSource != .none && validCount > 0 && coverage >= 0.5
        if sufficient {
            fillGaps(&power, present: present, paused: pausedFlags)
        }

        // 心率：FIT 的逐秒心率优先，其次分钟网格（已去重）。分钟网格部分在使用时按需读取，避免为每组建 1 Hz 数组。
        var fitHeartRate: [Int?]?
        for member in group.members {
            guard case .imported(let fileID) = member.source, let ride = importedByID[fileID] else { continue }
            let rideOffset = secondIndex(ride.start)
            for (index, value) in ride.heartRate.enumerated() {
                let second = rideOffset + index
                guard let value, second >= 0, second < seconds else { continue }
                if fitHeartRate == nil { fitHeartRate = [Int?](repeating: nil, count: seconds) }
                fitHeartRate?[second] = value
            }
        }
        let importedHasHeartRate = fitHeartRate != nil
        let average = averageHeartRate(fit: fitHeartRate, lower: lower, upper: upper, grid: grid)

        let p30 = CyclingAnalysis.rollingWindowAverage(power, window: 30)
        var minutePowerPresent = [Bool](repeating: false, count: upper - lower)
        minutePowerPresent.withUnsafeMutableBufferPointer { flags in
            present.withUnsafeBufferPointer { seen in
                for second in seen.indices where seen[second] {
                    flags[second / 60] = true
                }
            }
        }
        let gridOrigins = grid.heartRateOrigin[lower..<upper].compactMap { $0 }
        let heartRateOrigin = (gridOrigins + (importedHasHeartRate ? [HeartRateOrigin.fitImport] : [])).max()

        return GroupSeries(
            group: group,
            lowerMinute: lower,
            upperMinute: upper,
            start: group.start,
            end: group.end,
            power: power,
            powerPresent: present,
            pausedSeconds: pausedCount,
            powerSource: powerSource,
            powerCoverage: coverage,
            powerSufficient: sufficient,
            heartRateOrigin: heartRateOrigin,
            averageHeartRate: average,
            fitHeartRate: fitHeartRate,
            minutePowerPresent: minutePowerPresent,
            p30: p30,
            normalizedPower: sufficient ? CyclingMath.normalizedPower(smoothed: p30) : nil,
            powerCurve: sufficient ? CyclingMath.powerCurve(power) : [:]
        )
    }
}

/// 回归模型的拟合：用全部骑行中同时有心率与功率的秒（P30 滞后 20 秒）。
enum PowerHeartModelFit {
    static func fit(series: [GroupSeries], grid: MinuteGrid) -> PowerHeartModel? {
        var sums = PowerHeartModel.Sums()
        let minuteHeartRate = grid.heartRate
        for item in series where item.powerUsable {
            for second in item.power.indices where second >= PowerHeartModel.lagSeconds {
                guard item.powerPresent[second], let bpm = item.heartRate(second: second, minuteHeartRate: minuteHeartRate) else { continue }
                sums.add(x: item.p30[second - PowerHeartModel.lagSeconds], y: bpm)
            }
        }
        return PowerHeartModel.fit(sums)
    }
}

private extension RideCandidate {
    var idKey: String {
        switch source {
        case .workout(let uuid, _, _): uuid.uuidString
        case .imported(let fileID): "fit-\(fileID)"
        }
    }

    var sourceLabel: String {
        switch source {
        case .workout(_, let productType, let bundle):
            if productType?.hasPrefix("Watch") == true { return "Apple Watch" }
            if bundle?.hasPrefix("com.garmin") == true { return "Garmin 写入" }
            return "其他 App"
        case .imported:
            return "FIT 导入"
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
