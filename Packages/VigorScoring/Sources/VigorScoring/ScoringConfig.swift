import Foundation

/// 算法参数，带版本号（PRD §5.0、施工文档 §4.7）。同样的特征与参数得到同样的结果。
public struct ScoringConfig: Sendable, Hashable, Codable {
    public var configVersion = 1

    // MARK: RR 清洗（PRD §5.3.2）
    public var minRRms = 300.0
    public var maxRRms = 2000.0
    /// 局部中位数窗口：前后各 5 拍
    public var localWindowHalfSize = 5
    /// 与局部中位数相差超过该比例即剔除
    public var localMedianTolerance = 0.20
    /// 早搏：短拍 < 局部中位数 × 0.8，紧随的长拍 > 局部中位数 × 1.2
    public var ectopicShortFactor = 0.8
    public var ectopicLongFactor = 1.2
    /// 整段验收（§5.3.2）
    public var minAcceptedRR = 40
    public var maxRejectRate = 0.20
    public var minSegmentSeconds: TimeInterval = 45

    // MARK: 段权重（PRD §5.3.4）
    /// 质量 q 中“有效拍数 / 60”的满分拍数
    public var fullQualityBeats = 60.0
    public var earlyNightWeight = 0.7
    public var middleNightWeight = 1.0
    public var lateNightWeight = 1.5
    public var deepStageWeight = 1.3
    public var coreStageWeight = 1.0
    public var remStageWeight = 0.8

    /// 扰动：段内平均心率超过夜间静息心率的倍数
    public var disturbanceFactor = 1.15

    // MARK: 晨测（PRD §5.3.5）
    /// 醒来后多长时间内的序列算作晨测
    public var morningWindow: TimeInterval = 3600

    // MARK: 睡眠会话（PRD §5.2，施工文档 §4.4）
    /// 间隔 ≤ 该值时直接合并
    public var sessionMergeGap: TimeInterval = 45 * 60
    /// 间隔在 sessionMergeGap 与该值之间、且两端都在夜间窗口内时合并，并标记长清醒
    public var segmentedSleepMaxGap: TimeInterval = 120 * 60
    /// 夜间窗口：19:00 到次日 11:00（本地小时）
    public var nightWindowStartHour = 19
    public var nightWindowEndHour = 11
    /// 中点落在 [15:00, 19:00) 的会话不能成为主睡眠
    public var napOnlyStartHour = 15
    public var napOnlyEndHour = 19
    public var mainSleepMinDuration: TimeInterval = 3 * 3600
    public var napMinDuration: TimeInterval = 15 * 60
    /// 觉醒计数：持续 ≥ 该时长的清醒段才算一次觉醒
    public var awakeningMinDuration: TimeInterval = 120
    /// hypnogram 显示：不足该时长的分期并入相邻较长片段（只影响显示）
    public var hypnogramMinDuration: TimeInterval = 60
    /// 佩戴：主睡眠内连续无心率点超过该时长标记为部分未佩戴
    public var wearGapMinutes: TimeInterval = 60

    // MARK: 心率（PRD §5.4）
    public var restingWindowSeconds: TimeInterval = 900
    public var restingMinSampleCount = 10
    public var restingPercentile = 0.10
    /// 持续 ≥ 该时长的清醒段内的心率点不计入静息心率样本池（PRD §5.4）
    public var restingExcludeAwakeSeconds: TimeInterval = 300

    // MARK: 生命体征（PRD §5.5）
    public var respiratoryMinSamples = 3
    public var oxygenMinSamples = 3
    public var oxygenLowThresholdPercent = 90.0
    /// 呼吸紊乱“升高”阈值（单位以快照中保存的单位字符串为准，待真实数据校准）
    public var breathingDisturbanceElevated = 10.0

    public static let `default` = ScoringConfig()

    public init() {}
}
