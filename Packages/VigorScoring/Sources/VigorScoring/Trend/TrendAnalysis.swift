import Foundation

public enum TrendState: String, Sendable, Hashable, Codable {
    /// 7 天均值高于正常范围上沿：适应良好
    case adaptedWell
    case normal
    /// 7 天均值低于正常范围下沿：疲劳累积
    case fatigueAccumulating
}

/// 双时间尺度趋势（PRD §5.6）：7 天均值对比 60 天正常范围；7 天 CV 判断适应不良。
public struct TrendSummary: Sendable, Hashable, Codable {
    public var state: TrendState
    public var sevenDayMean: Double
    public var normalLow: Double
    public var normalHigh: Double
    public var sevenDayCV: Double
    public var sixtyDayCVMedian: Double?
    /// 7 天 CV 超过个人 60 天中位数的 1.5 倍、且均值在下降
    public var maladaptation: Bool

    public init(
        state: TrendState,
        sevenDayMean: Double,
        normalLow: Double,
        normalHigh: Double,
        sevenDayCV: Double,
        sixtyDayCVMedian: Double?,
        maladaptation: Bool
    ) {
        self.state = state
        self.sevenDayMean = sevenDayMean
        self.normalLow = normalLow
        self.normalHigh = normalHigh
        self.sevenDayCV = sevenDayCV
        self.sixtyDayCVMedian = sixtyDayCVMedian
        self.maladaptation = maladaptation
    }
}

public enum TrendAnalysis {
    /// - Parameter lnRMSSD: 有效夜晚的 ln RMSSD，按时间升序，最后一个是当前夜。
    public static func summarize(lnRMSSD: [Double]) -> TrendSummary? {
        guard lnRMSSD.count >= 7 else { return nil }
        let recent = Array(lnRMSSD.suffix(7))
        let sixty = Array(lnRMSSD.suffix(60))
        guard let mean7 = Statistics.mean(recent), let median60 = Statistics.median(sixty),
              let sigma60 = Statistics.mad(sixty).map({ 1.4826 * $0 })
        else { return nil }

        let low = median60 - 0.5 * sigma60
        let high = median60 + 0.5 * sigma60
        let state: TrendState = mean7 > high ? .adaptedWell : (mean7 < low ? .fatigueAccumulating : .normal)

        let cv7 = coefficientOfVariation(recent)
        // 个人 60 天中位数的 CV：对 60 天内每个滑动的 7 天窗口求 CV，取中位数
        var windowCVs: [Double] = []
        if sixty.count >= 7 {
            for end in 7...sixty.count {
                windowCVs.append(coefficientOfVariation(Array(sixty[(end - 7)..<end])))
            }
        }
        let cvMedian = Statistics.median(windowCVs)

        let previous = lnRMSSD.count >= 14 ? Array(lnRMSSD[(lnRMSSD.count - 14)..<(lnRMSSD.count - 7)]) : nil
        let declining = previous.flatMap { Statistics.mean($0) }.map { mean7 < $0 } ?? false
        let maladaptation = cvMedian.map { cv7 > 1.5 * $0 && declining } ?? false

        return TrendSummary(
            state: state,
            sevenDayMean: mean7,
            normalLow: low,
            normalHigh: high,
            sevenDayCV: cv7,
            sixtyDayCVMedian: cvMedian,
            maladaptation: maladaptation
        )
    }

    static func coefficientOfVariation(_ values: [Double]) -> Double {
        guard let mean = Statistics.mean(values), let sd = Statistics.standardDeviation(values), mean != 0 else {
            return 0
        }
        return sd / abs(mean)
    }
}
