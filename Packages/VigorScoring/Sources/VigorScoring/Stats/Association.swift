import Foundation

/// Welch 不等方差 t 检验（PRD §6.5、施工文档 §4.7）。
public struct WelchResult: Sendable, Hashable, Codable {
    /// 两组均值之差（第一组减第二组）
    public var difference: Double
    /// 差值的 95% 置信区间（近似，使用 t 分布的 0.975 分位）
    public var confidenceLow: Double
    public var confidenceHigh: Double
    public var t: Double
    public var degreesOfFreedom: Double
    public var pValue: Double

    public init(difference: Double, confidenceLow: Double, confidenceHigh: Double, t: Double, degreesOfFreedom: Double, pValue: Double) {
        self.difference = difference
        self.confidenceLow = confidenceLow
        self.confidenceHigh = confidenceHigh
        self.t = t
        self.degreesOfFreedom = degreesOfFreedom
        self.pValue = pValue
    }
}

public enum Association {
    /// 两组样本的 Welch t 检验。每组至少需要 2 个样本，且方差不能同时为零。
    public static func welch(_ first: [Double], _ second: [Double]) -> WelchResult? {
        guard first.count >= 2, second.count >= 2,
              let meanA = Statistics.mean(first), let meanB = Statistics.mean(second)
        else { return nil }
        let varianceA = sampleVariance(first, mean: meanA)
        let varianceB = sampleVariance(second, mean: meanB)
        let seA = varianceA / Double(first.count)
        let seB = varianceB / Double(second.count)
        let standardError = (seA + seB).squareRoot()
        guard standardError > 0 else { return nil }

        let difference = meanA - meanB
        let t = difference / standardError
        let df = (seA + seB) * (seA + seB)
            / (seA * seA / Double(first.count - 1) + seB * seB / Double(second.count - 1))
        let critical = studentQuantile975(df: df)
        return WelchResult(
            difference: difference,
            confidenceLow: difference - critical * standardError,
            confidenceHigh: difference + critical * standardError,
            t: t,
            degreesOfFreedom: df,
            pValue: Distributions.twoSidedPValue(t: t, df: df)
        )
    }

    /// Spearman 秩相关：先把数值转为秩（并列取平均秩），再计算 Pearson 相关。
    public static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let rx = ranks(x)
        let ry = ranks(y)
        guard let mx = Statistics.mean(rx), let my = Statistics.mean(ry) else { return nil }
        var covariance = 0.0
        var varX = 0.0
        var varY = 0.0
        for (a, b) in zip(rx, ry) {
            covariance += (a - mx) * (b - my)
            varX += (a - mx) * (a - mx)
            varY += (b - my) * (b - my)
        }
        guard varX > 0, varY > 0 else { return nil }
        return covariance / (varX * varY).squareRoot()
    }

    static func sampleVariance(_ values: [Double], mean: Double) -> Double {
        values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
    }

    /// 并列取平均秩（1 起始）。
    static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = [Double](repeating: 0, count: values.count)
        var start = 0
        while start < order.count {
            var end = start
            while end + 1 < order.count, values[order[end + 1]] == values[order[start]] {
                end += 1
            }
            let averageRank = Double(start + end + 2) / 2
            for index in start...end {
                result[order[index]] = averageRank
            }
            start = end + 1
        }
        return result
    }

    /// t 分布 0.975 分位数：用二分法在 t 的 CDF 上求解（精度足够用于置信区间展示）。
    static func studentQuantile975(df: Double) -> Double {
        var low = 0.0
        var high = 100.0
        for _ in 0..<200 {
            let middle = (low + high) / 2
            if Distributions.studentTCDF(middle, df: df) < 0.975 {
                low = middle
            } else {
                high = middle
            }
        }
        return (low + high) / 2
    }
}
