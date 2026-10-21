import Foundation

/// 统计工具（PRD §5.6、施工文档 §4.7）。全部为纯函数。
public enum Statistics {
    /// 线性插值分位数，等同于 numpy 默认方法。`p` 取 0…1。
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    public static func median(_ values: [Double]) -> Double? {
        percentile(values, 0.5)
    }

    /// 加权分位数：按值排序后，取累计权重首次 ≥ 总权重 × q 的那个值（施工文档 §4.7）。
    public static func weightedQuantile(_ values: [Double], weights: [Double], q: Double) -> Double? {
        precondition(values.count == weights.count, "values 与 weights 长度必须一致")
        let pairs = zip(values, weights).filter { $0.1 > 0 }.sorted { $0.0 < $1.0 }
        let total = pairs.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        let threshold = total * q
        var cumulative = 0.0
        for (value, weight) in pairs {
            cumulative += weight
            if cumulative >= threshold {
                return value
            }
        }
        return pairs.last?.0
    }

    public static func weightedMedian(_ values: [Double], weights: [Double]) -> Double? {
        weightedQuantile(values, weights: weights, q: 0.5)
    }

    /// 加权四分位距。
    public static func weightedIQR(_ values: [Double], weights: [Double]) -> Double? {
        guard let q1 = weightedQuantile(values, weights: weights, q: 0.25),
              let q3 = weightedQuantile(values, weights: weights, q: 0.75)
        else { return nil }
        return q3 - q1
    }

    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// 总体标准差。
    public static func standardDeviation(_ values: [Double]) -> Double? {
        guard let m = mean(values) else { return nil }
        return (values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count)).squareRoot()
    }

    /// 中位数绝对偏差。
    public static func mad(_ values: [Double]) -> Double? {
        guard let m = median(values) else { return nil }
        return median(values.map { abs($0 - m) })
    }
}
