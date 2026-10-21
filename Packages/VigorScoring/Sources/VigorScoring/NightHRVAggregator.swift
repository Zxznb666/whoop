import Foundation

public enum HRVMethod: String, Codable, Sendable, Hashable {
    case morning
    case overnight
    case sdnnFallback
    case none
}

public enum DataQuality: String, Codable, Sendable, Hashable {
    case high
    case medium
    case low
    case none
}

public struct NightHRV: Sendable, Hashable, Codable {
    /// ms
    public var rmssd: Double?
    public var method: HRVMethod
    /// 中点落在睡眠时段内的片段
    public var overnightSegments: [SegmentResult]
    /// 起点落在醒来后 morningWindow 内的片段
    public var morningSegments: [SegmentResult]
    public var validOvernightCount: Int
    /// 睡眠时段内 SDNN 样本的均值
    public var sdnnMean: Double?
    public var quality: DataQuality

    public init(
        rmssd: Double?,
        method: HRVMethod,
        overnightSegments: [SegmentResult],
        morningSegments: [SegmentResult],
        validOvernightCount: Int,
        sdnnMean: Double?,
        quality: DataQuality
    ) {
        self.rmssd = rmssd
        self.method = method
        self.overnightSegments = overnightSegments
        self.morningSegments = morningSegments
        self.validOvernightCount = validOvernightCount
        self.sdnnMean = sdnnMean
        self.quality = quality
    }
}

public enum NightHRVAggregator {
    public static func aggregate(
        session: SleepSession,
        segments: [SegmentResult],
        sdnn: [ValueSample],
        config: HRVConfig
    ) -> NightHRV {
        let overnight = segments.filter { segment in
            let middle = midpoint(of: segment)
            return middle >= session.start && middle <= session.end
        }
        let morning = segments.filter { segment in
            segment.start > session.end && segment.start <= session.end.addingTimeInterval(config.morningWindow)
        }
        let validOvernight = overnight.filter(\.isValid)
        let validOvernightCount = validOvernight.count

        let sdnnValues = sdnn
            .filter { $0.start >= session.start && $0.start <= session.end }
            .map(\.value)
        let sdnnMean = sdnnValues.isEmpty ? nil : sdnnValues.reduce(0, +) / Double(sdnnValues.count)

        func makeResult(rmssd: Double?, method: HRVMethod, quality: DataQuality) -> NightHRV {
            NightHRV(
                rmssd: rmssd,
                method: method,
                overnightSegments: overnight,
                morningSegments: morning,
                validOvernightCount: validOvernightCount,
                sdnnMean: sdnnMean,
                quality: quality
            )
        }

        let validMorningRMSSD = morning.filter(\.isValid).compactMap(\.rmssd)
        if let morningRMSSD = validMorningRMSSD.median {
            return makeResult(rmssd: morningRMSSD, method: .morning, quality: .high)
        }

        if validOvernightCount >= 1 {
            let sessionDuration = session.end.timeIntervalSince(session.start)
            let lateStart = session.start.addingTimeInterval(sessionDuration * 2 / 3)
            let deepStages = session.stages.filter { $0.stage == .deep }

            var weightedLogSum = 0.0
            var totalWeight = 0.0
            for segment in validOvernight {
                guard let rmssd = segment.rmssd else { continue }
                let middle = midpoint(of: segment)
                let lateFactor = middle >= lateStart ? config.lateSleepWeight : 1
                let inDeep = deepStages.contains { middle >= $0.start && middle <= $0.end }
                let deepFactor = inDeep ? config.deepSleepWeight : 1
                let weight = Double(segment.acceptedRR) * lateFactor * deepFactor
                weightedLogSum += weight * log(rmssd)
                totalWeight += weight
            }
            let quality: DataQuality = switch validOvernightCount {
            case 4...: .high
            case 2...3: .medium
            default: .low
            }
            return makeResult(rmssd: exp(weightedLogSum / totalWeight), method: .overnight, quality: quality)
        }

        if sdnnMean != nil {
            return makeResult(rmssd: nil, method: .sdnnFallback, quality: .low)
        }
        return makeResult(rmssd: nil, method: .none, quality: .none)
    }

    private static func midpoint(of segment: SegmentResult) -> Date {
        segment.start.addingTimeInterval(segment.end.timeIntervalSince(segment.start) / 2)
    }
}

extension Array where Element == Double {
    /// 偶数个时取中间两个的平均值；空数组返回 nil。
    var median: Double? {
        guard !isEmpty else { return nil }
        let sorted = self.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
