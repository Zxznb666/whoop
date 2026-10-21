import Foundation

/// 一段心跳序列的分析结果（PRD §5.3.3、§8.3 的 `HRVWindow`）。
/// 夜间的上下文（分期、位置）与权重由 `NightHRVAggregator` 填入。
public struct HRVWindow: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID { seriesID }
    public var seriesID: UUID
    public var start: Date
    public var end: Date
    /// 中点所处的睡眠分期（仅夜间窗口）
    public var stage: SleepStage?
    /// 夜间位置：0 = 入睡，1 = 醒来；晨测为 nil
    public var position: Double?
    public var isMorning: Bool
    /// 可计算出的 RR 候选数（不含间隙）
    public var candidateCount: Int
    public var acceptedCount: Int
    public var rejectedCount: Int
    public var rejectRate: Double
    /// ms
    public var rmssd: Double?
    /// 由被接受 RR 的平均值换算：60000 / mean(RR)
    public var meanHeartRate: Double?
    /// ms
    public var sdnn: Double?
    public var durationSeconds: TimeInterval
    /// 被接受的 RR（ms）及其对应拍的时间（距序列开始的秒数）
    public var acceptedRR: [Double]
    public var acceptedBeatTimes: [TimeInterval]
    /// 被剔除的拍的时间，用于实验室页的伪迹标色
    public var rejectedBeatTimes: [TimeInterval]
    /// nil 表示有效；否则为原因
    public var invalidReason: String?
    /// 段权重 w = q × p × s（§5.3.4），未参与合成时为 0
    public var weight: Double
    /// 是否被采用进当晚的 HRV
    public var adopted: Bool

    public var isValid: Bool { invalidReason == nil }

    public init(
        seriesID: UUID,
        start: Date,
        end: Date,
        stage: SleepStage? = nil,
        position: Double? = nil,
        isMorning: Bool = false,
        candidateCount: Int,
        acceptedCount: Int,
        rejectedCount: Int,
        rejectRate: Double,
        rmssd: Double?,
        meanHeartRate: Double?,
        sdnn: Double?,
        durationSeconds: TimeInterval,
        acceptedRR: [Double],
        acceptedBeatTimes: [TimeInterval],
        rejectedBeatTimes: [TimeInterval],
        invalidReason: String?,
        weight: Double = 0,
        adopted: Bool = false
    ) {
        self.seriesID = seriesID
        self.start = start
        self.end = end
        self.stage = stage
        self.position = position
        self.isMorning = isMorning
        self.candidateCount = candidateCount
        self.acceptedCount = acceptedCount
        self.rejectedCount = rejectedCount
        self.rejectRate = rejectRate
        self.rmssd = rmssd
        self.meanHeartRate = meanHeartRate
        self.sdnn = sdnn
        self.durationSeconds = durationSeconds
        self.acceptedRR = acceptedRR
        self.acceptedBeatTimes = acceptedBeatTimes
        self.rejectedBeatTimes = rejectedBeatTimes
        self.invalidReason = invalidReason
        self.weight = weight
        self.adopted = adopted
    }
}

public enum RRProcessor {
    public static let reasonInsufficientRR = "有效 RR 不足"
    public static let reasonHighRejectRate = "伪迹比例过高"
    public static let reasonTooShort = "时长不足 45 秒"
    public static let reasonNoDifference = "无相邻 RR"
    public static let reasonDisturbed = "扰动（心率高于静息的 1.15 倍）"

    /// 一个 RR 候选：RR_i = t_i − t_(i−1)，仅当第 i 拍不是间隙后的第一拍时成立。
    private struct Candidate {
        var rr: Double
        var beatTime: TimeInterval
        /// 同一个 run 内的候选彼此相邻；遇到间隙则换 run
        var run: Int
    }

    public static func analyze(_ series: HeartbeatSeries, config: ScoringConfig = .default) -> HRVWindow {
        let candidates = makeCandidates(series.beats)
        let rejected = filter(candidates, config: config)

        var accepted: [Int] = []
        var rejectedTimes: [TimeInterval] = []
        for index in candidates.indices {
            if rejected[index] {
                rejectedTimes.append(candidates[index].beatTime)
            } else {
                accepted.append(index)
            }
        }

        // 只使用原本相邻、且都被接受的两个 RR 计算差值；被删除的 RR 不插值。
        var squaredDiffs: [Double] = []
        for index in candidates.indices.dropFirst() where !rejected[index] && !rejected[index - 1] {
            guard candidates[index].run == candidates[index - 1].run else { continue }
            let diff = candidates[index].rr - candidates[index - 1].rr
            squaredDiffs.append(diff * diff)
        }
        let rmssd: Double? = squaredDiffs.isEmpty ? nil : (squaredDiffs.reduce(0, +) / Double(squaredDiffs.count)).squareRoot()

        let acceptedRR = accepted.map { candidates[$0].rr }
        let meanRR = Statistics.mean(acceptedRR)
        let sdnn = Statistics.standardDeviation(acceptedRR)
        let candidateCount = candidates.count
        let rejectRate = candidateCount == 0 ? 1 : Double(rejectedTimes.count) / Double(candidateCount)
        let duration = (series.beats.last?.t ?? 0) - (series.beats.first?.t ?? 0)

        let reason = invalidReason(
            accepted: accepted.count,
            rejectRate: rejectRate,
            duration: duration,
            hasRMSSD: rmssd != nil,
            config: config
        )

        return HRVWindow(
            seriesID: series.id,
            start: series.start,
            end: series.end,
            candidateCount: candidateCount,
            acceptedCount: accepted.count,
            rejectedCount: rejectedTimes.count,
            rejectRate: rejectRate,
            rmssd: rmssd,
            meanHeartRate: meanRR.map { 60_000 / $0 },
            sdnn: sdnn,
            durationSeconds: duration,
            acceptedRR: acceptedRR,
            acceptedBeatTimes: accepted.map { candidates[$0].beatTime },
            rejectedBeatTimes: rejectedTimes,
            invalidReason: reason
        )
    }

    /// 扰动检测（§5.3.3）：段内平均心率超过夜间静息心率的 1.15 倍时整段丢弃。
    /// 需要先算出夜间静息心率，所以单独成为一步。
    public static func applyDisturbance(_ window: inout HRVWindow, restingHeartRate: Double?, config: ScoringConfig) {
        guard window.isValid, let resting = restingHeartRate, let heartRate = window.meanHeartRate else { return }
        if heartRate > resting * config.disturbanceFactor {
            window.invalidReason = reasonDisturbed
        }
    }

    static func invalidReason(
        accepted: Int,
        rejectRate: Double,
        duration: TimeInterval,
        hasRMSSD: Bool,
        config: ScoringConfig
    ) -> String? {
        if accepted < config.minAcceptedRR { return reasonInsufficientRR }
        if rejectRate > config.maxRejectRate { return reasonHighRejectRate }
        if duration < config.minSegmentSeconds { return reasonTooShort }
        if !hasRMSSD { return reasonNoDifference }
        return nil
    }

    private static func makeCandidates(_ beats: [Beat]) -> [Candidate] {
        guard beats.count > 1 else { return [] }
        var candidates: [Candidate] = []
        var run = 0
        for index in beats.indices.dropFirst() {
            if beats[index].precededByGap {
                run += 1
                continue
            }
            let rr = (beats[index].t - beats[index - 1].t) * 1000
            candidates.append(Candidate(rr: rr, beatTime: beats[index].t, run: run))
        }
        return candidates
    }

    /// 返回每个候选是否被剔除。三层规则（§5.3.2）：生理范围 → 局部中位数 → 早搏成对剔除。
    private static func filter(_ candidates: [Candidate], config: ScoringConfig) -> [Bool] {
        var rejected = candidates.map { $0.rr < config.minRRms || $0.rr > config.maxRRms }

        // 局部中位数：同一 run 内、前后各 5 拍（只统计仍然通过生理范围的拍）
        var localMedian = [Double](repeating: 0, count: candidates.count)
        for index in candidates.indices where !rejected[index] {
            let lower = max(candidates.startIndex, index - config.localWindowHalfSize)
            let upper = min(candidates.endIndex - 1, index + config.localWindowHalfSize)
            let window = (lower...upper)
                .filter { candidates[$0].run == candidates[index].run && !(candidates[$0].rr < config.minRRms || candidates[$0].rr > config.maxRRms) }
                .map { candidates[$0].rr }
            localMedian[index] = Statistics.median(window) ?? candidates[index].rr
            if abs(candidates[index].rr - localMedian[index]) / localMedian[index] > config.localMedianTolerance {
                rejected[index] = true
            }
        }

        // 早搏：短拍 < 局部中位数 × 0.8，紧随的长拍 > 局部中位数 × 1.2，两拍都剔除
        for index in candidates.indices.dropLast() where !rejected[index] && !rejected[index + 1] {
            guard candidates[index].run == candidates[index + 1].run else { continue }
            let short = candidates[index].rr < localMedian[index] * config.ectopicShortFactor
            let long = candidates[index + 1].rr > localMedian[index + 1] * config.ectopicLongFactor
            if short && long {
                rejected[index] = true
                rejected[index + 1] = true
            }
        }
        return rejected
    }
}
