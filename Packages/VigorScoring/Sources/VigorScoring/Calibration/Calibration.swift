import Foundation

/// 岭回归（PRD §5.8.5）：以收缩项 λ 把权重拉向先验（默认权重）。小矩阵用 Cholesky 分解求解。
public enum RidgeRegression {
    /// 求解 (XᵀX + λI) β = Xᵀy + λβ₀，其中 β₀ 为收缩目标。X 的每一行为一个样本（首列不需要为 1，截距单独处理）。
    public static func fit(
        features: [[Double]],
        targets: [Double],
        lambda: Double,
        priorWeights: [Double]
    ) -> [Double]? {
        guard let first = features.first, features.count == targets.count, first.count == priorWeights.count else {
            return nil
        }
        let p = first.count
        var normal = [[Double]](repeating: [Double](repeating: 0, count: p), count: p)
        var rhs = [Double](repeating: 0, count: p)
        for (row, y) in zip(features, targets) {
            for i in 0..<p {
                rhs[i] += row[i] * y
                for j in 0..<p {
                    normal[i][j] += row[i] * row[j]
                }
            }
        }
        for i in 0..<p {
            normal[i][i] += lambda
            rhs[i] += lambda * priorWeights[i]
        }
        return choleskySolve(normal, rhs)
    }

    /// Cholesky 分解求解对称正定方程组。
    static func choleskySolve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        let n = vector.count
        var lower = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in 0...i {
                var sum = matrix[i][j]
                for k in 0..<j {
                    sum -= lower[i][k] * lower[j][k]
                }
                if i == j {
                    guard sum > 0 else { return nil }
                    lower[i][i] = sum.squareRoot()
                } else {
                    lower[i][j] = sum / lower[j][j]
                }
            }
        }
        var y = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var sum = vector[i]
            for k in 0..<i { sum -= lower[i][k] * y[k] }
            y[i] = sum / lower[i][i]
        }
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = y[i]
            for k in (i + 1)..<max(i + 1, n) { sum -= lower[k][i] * x[k] }
            x[i] = sum / lower[i][i]
        }
        return x
    }
}

/// 权重拟合的校准报告（PRD §5.8.5、§5.14）。
public struct CalibrationReport: Sendable, Hashable, Codable {
    public var trainCount: Int
    public var validationCount: Int
    public var defaultSpearman: Double?
    public var fittedSpearman: Double?
    /// 新权重在验证集上的 Spearman 提升，至少 0.05 才建议采用
    public var improvement: Double?
    public var recommended: Bool
    public var weights: [Double]

    public init(trainCount: Int, validationCount: Int, defaultSpearman: Double?, fittedSpearman: Double?, improvement: Double?, recommended: Bool, weights: [Double]) {
        self.trainCount = trainCount
        self.validationCount = validationCount
        self.defaultSpearman = defaultSpearman
        self.fittedSpearman = fittedSpearman
        self.improvement = improvement
        self.recommended = recommended
        self.weights = weights
    }
}

public enum Calibration {
    /// 至少需要的主观精力天数（PRD §5.8.5：累计 45 天以上）。
    public static let minimumDays = 45
    public static let trainFraction = 0.7
    public static let minimumImprovement = 0.05

    /// 以主观精力为因变量，各分量 z-score 与扣分为自变量，做岭回归。按时间切分：前 70% 拟合，后 30% 评估。
    /// - Parameters:
    ///   - samples: 按时间升序的 (特征, 主观精力 1–5)
    ///   - defaultWeights: 默认权重（同时作为收缩目标）
    public static func evaluate(
        samples: [(features: [Double], energy: Double)],
        defaultWeights: [Double],
        lambda: Double
    ) -> CalibrationReport? {
        guard samples.count >= minimumDays, let width = samples.first?.features.count, width == defaultWeights.count else {
            return nil
        }
        let split = Int(Double(samples.count) * trainFraction)
        let train = Array(samples.prefix(split))
        let validation = Array(samples.suffix(samples.count - split))
        guard let fitted = RidgeRegression.fit(
            features: train.map(\.features),
            targets: train.map(\.energy),
            lambda: lambda,
            priorWeights: defaultWeights
        ) else { return nil }

        let defaultScores = validation.map { dot($0.features, defaultWeights) }
        let fittedScores = validation.map { dot($0.features, fitted) }
        let energy = validation.map(\.energy)
        let defaultRho = Association.spearman(defaultScores, energy)
        let fittedRho = Association.spearman(fittedScores, energy)
        let improvement = defaultRho.flatMap { base in fittedRho.map { $0 - base } }
        return CalibrationReport(
            trainCount: train.count,
            validationCount: validation.count,
            defaultSpearman: defaultRho,
            fittedSpearman: fittedRho,
            improvement: improvement,
            recommended: (improvement ?? 0) >= minimumImprovement,
            weights: fitted
        )
    }

    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
