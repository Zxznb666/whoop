import Foundation

public enum HRVMethod: String, Codable, Sendable, Hashable {
    /// 当晚有夜间 heartbeat 序列得到的 RMSSD
    case overnight
    /// 没有夜间 RMSSD，但有通过验收的晨测
    case morning
    /// 只有 Apple 的 SDNN（兜底）
    case sdnnFallback
    case none
}

/// 当晚的 HRV，三种模式分别输出（PRD §5.3.5：分别建基线，不混在一起算）。
public struct NightHRV: Sendable, Hashable, Codable {
    /// ms，夜间加权合并
    public var nightRMSSD: Double?
    /// 夜间有效段数（权重 > 0）
    public var nightValidCount: Int
    /// 夜间候选段总数（中点在睡眠时段内）
    public var nightTotalCount: Int
    /// ms，晨测
    public var morningRMSSD: Double?
    public var morningValidCount: Int
    /// 睡眠时段内 Apple SDNN 的均值（ms）
    public var sdnnMean: Double?
    /// 段间离散度：加权 IQR（ln 单位）
    public var dispersion: Double?
    /// 当晚的主要来源：夜间 > 晨测 > SDNN 兜底
    public var method: HRVMethod

    /// 界面展示的 RMSSD（毫秒）：夜间优先，其次晨测
    public var displayRMSSD: Double? { nightRMSSD ?? morningRMSSD }

    public init(
        nightRMSSD: Double?,
        nightValidCount: Int,
        nightTotalCount: Int,
        morningRMSSD: Double?,
        morningValidCount: Int,
        sdnnMean: Double?,
        dispersion: Double?,
        method: HRVMethod
    ) {
        self.nightRMSSD = nightRMSSD
        self.nightValidCount = nightValidCount
        self.nightTotalCount = nightTotalCount
        self.morningRMSSD = morningRMSSD
        self.morningValidCount = morningValidCount
        self.sdnnMean = sdnnMean
        self.dispersion = dispersion
        self.method = method
    }
}

public enum NightHRVAggregator {
    /// 把序列归入当晚的夜间窗口或晨测窗口（PRD §5.3.1、§4.5）。
    /// - 夜间：中点落在睡眠时段内
    /// - 晨测：起点在 (醒来, 醒来 + 60 分钟] 内，且与某条正念记录重叠
    /// - 其余忽略（既不算夜间，也不算晨测）
    public static func classify(
        session: SleepSession,
        analyzed: [HRVWindow],
        mindfulSessions: [ValueSample],
        config: ScoringConfig = .default
    ) -> (overnight: [HRVWindow], morning: [HRVWindow]) {
        var overnight: [HRVWindow] = []
        var morning: [HRVWindow] = []
        for var window in analyzed {
            let middle = window.start.addingTimeInterval(window.end.timeIntervalSince(window.start) / 2)
            if middle >= session.start && middle <= session.end {
                let duration = session.end.timeIntervalSince(session.start)
                window.position = min(max(middle.timeIntervalSince(session.start) / duration, 0), 1)
                window.stage = stage(at: middle, in: session)
                overnight.append(window)
            } else if window.start > session.end,
                      window.start <= session.end.addingTimeInterval(config.morningWindow),
                      mindfulSessions.contains(where: { overlaps(window, $0) }) {
                window.isMorning = true
                morning.append(window)
            }
        }
        return (overnight, morning)
    }

    /// 合成当晚的 HRV，并回写每段的权重与是否采用。
    /// 夜间：w = q × p × s（§5.3.4）；有效段 ≥ 3 取加权中位数，= 2 取加权平均，= 1 直接采用。
    /// 晨测：有效晨测的 RMSSD 取中位数（不做夜间加权）。
    public static func aggregate(
        session: SleepSession,
        overnight: inout [HRVWindow],
        morning: inout [HRVWindow],
        sdnn: [ValueSample],
        config: ScoringConfig = .default
    ) -> NightHRV {
        for index in overnight.indices {
            overnight[index].weight = 0
            overnight[index].adopted = false
            guard overnight[index].isValid, let rmssd = overnight[index].rmssd, rmssd > 0 else { continue }
            let stage = overnight[index].stage ?? .core
            let stageFactor = stageWeight(stage, config: config)
            guard stageFactor > 0 else { continue }
            let quality = min(1, Double(overnight[index].acceptedCount) / config.fullQualityBeats)
                * (1 - overnight[index].rejectRate)
            let position = overnight[index].position ?? 0.5
            let positionFactor = position < 1.0 / 3.0
                ? config.earlyNightWeight
                : (position < 2.0 / 3.0 ? config.middleNightWeight : config.lateNightWeight)
            overnight[index].weight = quality * positionFactor * stageFactor
        }

        let valid = overnight.indices.filter { overnight[$0].weight > 0 }
        let logs = valid.map { log(overnight[$0].rmssd!) }
        let weights = valid.map { overnight[$0].weight }
        var nightRMSSD: Double?
        var dispersion: Double?
        switch valid.count {
        case 0:
            break
        case 1:
            nightRMSSD = overnight[valid[0]].rmssd
        case 2:
            nightRMSSD = exp(zip(logs, weights).reduce(0) { $0 + $1.0 * $1.1 } / weights.reduce(0, +))
        default:
            nightRMSSD = Statistics.weightedMedian(logs, weights: weights).map { exp($0) }
        }
        if valid.count >= 2 {
            dispersion = Statistics.weightedIQR(logs, weights: weights)
        }
        for index in valid {
            overnight[index].adopted = true
        }

        let validMorning = morning.indices.filter { morning[$0].isValid && morning[$0].rmssd != nil }
        for index in morning.indices {
            morning[index].weight = 0
            morning[index].adopted = false
        }
        let morningRMSSD = Statistics.median(validMorning.map { morning[$0].rmssd! })
        for index in validMorning {
            morning[index].weight = min(1, Double(morning[index].acceptedCount) / config.fullQualityBeats)
            morning[index].adopted = true
        }

        let sdnnValues = sdnn
            .filter { $0.start >= session.start && $0.start <= session.end }
            .map(\.value)
        let sdnnMean = Statistics.mean(sdnnValues)

        let method: HRVMethod = nightRMSSD != nil ? .overnight
            : (morningRMSSD != nil ? .morning : (sdnnMean != nil ? .sdnnFallback : .none))

        return NightHRV(
            nightRMSSD: nightRMSSD,
            nightValidCount: valid.count,
            nightTotalCount: overnight.count,
            morningRMSSD: morningRMSSD,
            morningValidCount: validMorning.count,
            sdnnMean: sdnnMean,
            dispersion: dispersion,
            method: method
        )
    }

    static func stageWeight(_ stage: SleepStage, config: ScoringConfig) -> Double {
        switch stage {
        case .deep: config.deepStageWeight
        case .core: config.coreStageWeight
        case .rem: config.remStageWeight
        case .awake: 0
        case .inBed, .asleepUnspecified: config.coreStageWeight
        }
    }

    static func stage(at date: Date, in session: SleepSession) -> SleepStage? {
        session.stages.first { $0.start <= date && date < $0.end }?.stage
    }

    private static func overlaps(_ window: HRVWindow, _ sample: ValueSample) -> Bool {
        window.start < sample.end && sample.start < window.end
    }
}
