import Foundation

public struct SegmentResult: Sendable, Hashable, Codable {
    public var seriesID: UUID
    public var start: Date
    public var end: Date
    /// 可计算出的 RR 总数
    public var candidateRR: Int
    public var acceptedRR: Int
    public var rejectedRR: Int
    /// ms
    public var rmssd: Double?
    public var isValid: Bool
    public var invalidReason: String?
    public var acceptedRRms: [Double]
    /// 每个被接受 RR 对应的 beat 时间（秒）
    public var acceptedRRTimes: [TimeInterval]

    public init(
        seriesID: UUID,
        start: Date,
        end: Date,
        candidateRR: Int,
        acceptedRR: Int,
        rejectedRR: Int,
        rmssd: Double?,
        isValid: Bool,
        invalidReason: String?,
        acceptedRRms: [Double],
        acceptedRRTimes: [TimeInterval]
    ) {
        self.seriesID = seriesID
        self.start = start
        self.end = end
        self.candidateRR = candidateRR
        self.acceptedRR = acceptedRR
        self.rejectedRR = rejectedRR
        self.rmssd = rmssd
        self.isValid = isValid
        self.invalidReason = invalidReason
        self.acceptedRRms = acceptedRRms
        self.acceptedRRTimes = acceptedRRTimes
    }
}

public enum RRProcessor {
    public static func analyze(_ series: HeartbeatSeries, config: HRVConfig) -> SegmentResult {
        let beats = series.beats
        var candidate = 0
        var accepted = 0
        var rejected = 0
        var acceptedRRms: [Double] = []
        var acceptedRRTimes: [TimeInterval] = []
        var squaredDiffSum = 0.0
        var diffCount = 0
        /// 上一个被接受的 RR（ms）
        var previous: Double?
        /// previous 与当前 RR 之间没有发生打断
        var connected = false

        for index in beats.indices.dropFirst() {
            let beat = beats[index]
            if beat.precededByGap {
                connected = false
                continue
            }
            candidate += 1
            let rr = (beat.t - beats[index - 1].t) * 1000

            guard rr >= config.minRRms, rr <= config.maxRRms else {
                rejected += 1
                connected = false
                continue
            }
            if let previous, connected, abs(rr - previous) / previous > config.maxSuccessiveChange {
                rejected += 1
                connected = false
                continue
            }
            if let previous, connected {
                let diff = rr - previous
                squaredDiffSum += diff * diff
                diffCount += 1
            }
            accepted += 1
            acceptedRRms.append(rr)
            acceptedRRTimes.append(beat.t)
            previous = rr
            connected = true
        }

        let rmssd: Double? = diffCount > 0 ? (squaredDiffSum / Double(diffCount)).squareRoot() : nil
        let isValid = accepted >= config.minValidRR
            && candidate > 0
            && Double(rejected) / Double(candidate) <= config.maxRejectRate
            && rmssd != nil

        var invalidReason: String?
        if !isValid {
            invalidReason = (accepted < config.minValidRR || rmssd == nil) ? "有效 RR 不足" : "伪迹比例过高"
        }

        return SegmentResult(
            seriesID: series.id,
            start: series.start,
            end: series.end,
            candidateRR: candidate,
            acceptedRR: accepted,
            rejectedRR: rejected,
            rmssd: rmssd,
            isValid: isValid,
            invalidReason: invalidReason,
            acceptedRRms: acceptedRRms,
            acceptedRRTimes: acceptedRRTimes
        )
    }
}
