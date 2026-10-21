import Foundation

/// 功率补偿的个人回归模型：HR(t) = a + b · P30(t − 20)（施工文档 §2.4）。
public struct PowerHeartModel: Sendable, Hashable, Codable {
    /// 心率相对功率的滞后秒数
    public static let lagSeconds = 20
    /// 启用条件：配对秒数 ≥ 1200 且 R² ≥ 0.5
    public static let minimumPairs = 1200
    public static let minimumRSquared = 0.5

    public var intercept: Double
    public var slope: Double
    public var rSquared: Double
    public var pairCount: Int

    public init(intercept: Double, slope: Double, rSquared: Double, pairCount: Int) {
        self.intercept = intercept
        self.slope = slope
        self.rSquared = rSquared
        self.pairCount = pairCount
    }

    public func predict(p30: Double) -> Double {
        intercept + slope * p30
    }

    /// 最小二乘拟合。不满足启用条件时返回 nil。
    public static func fit(x: [Double], y: [Double]) -> PowerHeartModel? {
        var sums = Sums()
        for index in 0..<min(x.count, y.count) {
            sums.add(x: x[index], y: y[index])
        }
        return fit(sums)
    }

    /// 累加器：避免为数十万个配对秒保存数组。
    public struct Sums: Sendable {
        public private(set) var count = 0
        var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0, sumYY = 0.0

        public init() {}

        public mutating func add(x: Double, y: Double) {
            count += 1
            sumX += x
            sumY += y
            sumXY += x * y
            sumXX += x * x
            sumYY += y * y
        }
    }

    public static func fit(_ sums: Sums) -> PowerHeartModel? {
        let n = Double(sums.count)
        guard sums.count >= minimumPairs else { return nil }
        let varianceX = n * sums.sumXX - sums.sumX * sums.sumX
        let varianceY = n * sums.sumYY - sums.sumY * sums.sumY
        guard varianceX > 0, varianceY > 0 else { return nil }
        let covariance = n * sums.sumXY - sums.sumX * sums.sumY
        let slope = covariance / varianceX
        let intercept = (sums.sumY - slope * sums.sumX) / n
        let rSquared = covariance * covariance / (varianceX * varianceY)
        guard rSquared >= minimumRSquared else { return nil }
        return PowerHeartModel(intercept: intercept, slope: slope, rSquared: rSquared, pairCount: sums.count)
    }
}
