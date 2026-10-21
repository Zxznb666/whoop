import Foundation

/// 空窗估算的线性模型 HR = a + b · (kcal/min)（PRD §2.2、§5.10）。
public struct ActivityModel: Sendable, Hashable, Codable {
    public var intercept: Double
    public var slope: Double
    public var rSquared: Double
    public var sampleCount: Int

    public init(intercept: Double, slope: Double, rSquared: Double, sampleCount: Int) {
        self.intercept = intercept
        self.slope = slope
        self.rSquared = rSquared
        self.sampleCount = sampleCount
    }

    public func predict(kilocaloriesPerMinute: Double) -> Double {
        intercept + slope * kilocaloriesPerMinute
    }

    /// 只有样本 ≥ 500 且 R² ≥ 0.3 时才启用（施工文档 §4.7）。
    public static func fit(
        count n: Double,
        sumX: Double,
        sumY: Double,
        sumXY: Double,
        sumXX: Double,
        sumYY: Double
    ) -> ActivityModel? {
        guard n >= 500 else { return nil }
        let varianceX = n * sumXX - sumX * sumX
        let varianceY = n * sumYY - sumY * sumY
        guard varianceX > 0, varianceY > 0 else { return nil }
        let covariance = n * sumXY - sumX * sumY
        let slope = covariance / varianceX
        let intercept = (sumY - slope * sumX) / n
        let rSquared = covariance * covariance / (varianceX * varianceY)
        guard rSquared >= 0.3 else { return nil }
        return ActivityModel(intercept: intercept, slope: slope, rSquared: rSquared, sampleCount: Int(n))
    }
}
