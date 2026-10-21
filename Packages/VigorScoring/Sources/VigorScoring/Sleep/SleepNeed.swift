import Foundation

/// 睡眠需求的构成（PRD §5.9.3）。时长单位：小时。
public struct SleepNeedComponents: Sendable, Hashable, Codable {
    public var base: Double
    public var loadAddition: Double
    /// 小睡抵扣（负数，减少当晚需求）
    public var napCredit: Double
    /// 负债偿还 min(2, ρ · D_(t−1))
    public var debtRepayment: Double
    /// N0：当晚“本来就该睡”的量（不含还债）
    public var baseNeed: Double

    public var total: Double { baseNeed + debtRepayment }

    public init(base: Double, loadAddition: Double, napCredit: Double, debtRepayment: Double, baseNeed: Double) {
        self.base = base
        self.loadAddition = loadAddition
        self.napCredit = napCredit
        self.debtRepayment = debtRepayment
        self.baseNeed = baseNeed
    }
}

public enum SleepNeed {
    /// λ：负债衰减系数（半衰期约 3 晚）
    public static let debtDecay = 0.8
    /// ρ：负债偿还比例
    public static let repaymentRate = 0.3
    public static let maxDebtHours = 10.0
    public static let maxRepaymentHours = 2.0

    /// 负荷追加：4 分钟 × max(0, 昨日负荷 − 8)，最多 52 分钟（PRD §5.9.3）。返回小时。
    public static func loadAdditionHours(previousStrain: Double?) -> Double {
        guard let strain = previousStrain else { return 0 }
        return min(52, 4 * max(0, strain - 8)) / 60
    }

    /// 小睡抵扣：本周期内小睡睡着时长 × 0.8（返回小时，正数表示抵扣量）。
    public static func napCreditHours(napAsleepHours: Double) -> Double {
        napAsleepHours * 0.8
    }

    /// 构成需求的各部分。
    /// - Parameters:
    ///   - previousDebt: D(t−1)，小时
    public static func components(
        base: Double,
        loadAddition: Double,
        napCredit: Double,
        previousDebt: Double
    ) -> SleepNeedComponents {
        let n0 = base + loadAddition - napCredit
        let repayment = min(maxRepaymentHours, repaymentRate * previousDebt)
        return SleepNeedComponents(
            base: base,
            loadAddition: loadAddition,
            napCredit: -napCredit,
            debtRepayment: repayment,
            baseNeed: n0
        )
    }

    /// 逐晚递推：D_t = clamp(λ·D_(t−1) + (N0_t − TST_t), 0, 10)。
    /// 用 N0（不含还债）作为参照，避免循环依赖（PRD §5.9.3）。
    public static func nextDebt(previousDebt: Double, baseNeed: Double, totalSleep: Double) -> Double {
        min(max(debtDecay * previousDebt + (baseNeed - totalSleep), 0), maxDebtHours)
    }
}

/// 分段线性回归的拐点（网格搜索，PRD §5.9.3 方法 B）。
public enum PiecewiseLinear {
    /// 拟合 y = a + b·x + c·max(0, x − k)，返回使残差平方和最小的 k。
    /// 样本太少或 x 没有变化时返回 nil。
    public static func knee(x: [Double], y: [Double], grid: ClosedRange<Double>, step: Double) -> Double? {
        guard x.count == y.count, x.count >= 6, let minX = x.min(), let maxX = x.max(), maxX > minX else {
            return nil
        }
        var best: (knee: Double, sse: Double)?
        var k = grid.lowerBound
        while k <= grid.upperBound + 1e-12 {
            if k > minX, k < maxX, let sse = residualSum(x: x, y: y, knee: k) {
                if best == nil || sse < best!.sse {
                    best = (k, sse)
                }
            }
            k += step
        }
        return best?.knee
    }

    static func residualSum(x: [Double], y: [Double], knee: Double) -> Double? {
        // 设计矩阵 [1, x, max(0, x−k)]，解正规方程 (XᵀX) β = Xᵀy
        var xtx = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var xty = [Double](repeating: 0, count: 3)
        for (xi, yi) in zip(x, y) {
            let row = [1, xi, max(0, xi - knee)]
            for i in 0..<3 {
                xty[i] += row[i] * yi
                for j in 0..<3 {
                    xtx[i][j] += row[i] * row[j]
                }
            }
        }
        guard let beta = solve(xtx, xty) else { return nil }
        var sse = 0.0
        for (xi, yi) in zip(x, y) {
            let fitted = beta[0] + beta[1] * xi + beta[2] * max(0, xi - knee)
            sse += (yi - fitted) * (yi - fitted)
        }
        return sse
    }

    /// 3×3 高斯消元（部分选主元）。
    static func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        var a = matrix
        var b = vector
        let n = b.count
        for column in 0..<n {
            guard let pivot = (column..<n).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }),
                  abs(a[pivot][column]) > 1e-12
            else { return nil }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)
            for row in (column + 1)..<n {
                let factor = a[row][column] / a[column][column]
                for k in column..<n {
                    a[row][k] -= factor * a[column][k]
                }
                b[row] -= factor * b[column]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n {
                sum -= a[row][k] * x[k]
            }
            x[row] = sum / a[row][row]
        }
        return x
    }
}

/// 基础睡眠需求的个性化（PRD §5.9.3，积累 60 晚以后每月更新一次）。
public struct PersonalizedNeed: Sendable, Hashable, Codable {
    /// 方法 A：自然睡眠长度（小时）
    public var methodA: Double?
    /// 方法 B：TST 与次日 z_hrv 的拐点（小时）
    public var methodB: Double?
    /// 候选值 = (A + B) / 2，限制在 6.5–9.5 之间
    public var candidate: Double?
    /// 平滑更新后的基础需求；A、B 相差超过 1 小时时不更新
    public var updatedBase: Double
    /// 提示文字（例如本月不更新）
    public var hint: String?

    public init(methodA: Double?, methodB: Double?, candidate: Double?, updatedBase: Double, hint: String?) {
        self.methodA = methodA
        self.methodB = methodB
        self.candidate = candidate
        self.updatedBase = updatedBase
        self.hint = hint
    }

    /// - Parameters:
    ///   - totalSleepHours: 按时间升序的 TST（小时）
    ///   - previousDebts: 与 TST 对齐的前两晚负债 (D(t−1), D(t−2))，用于方法 A 的“连续两晚负债都 < 30 分钟”
    ///   - isFreeDay: 与 TST 对齐，是否为自由日（默认以周末近似）
    ///   - nextZHRV: 与 TST 对齐，次日的 z_hrv（缺失为 nil）
    public static func make(
        currentBase: Double,
        totalSleepHours: [Double],
        previousDebts: [(Double, Double)],
        isFreeDay: [Bool],
        nextZHRV: [Double?]
    ) -> PersonalizedNeed {
        // 方法 A：自由日中，前两晚负债都 < 0.5 小时的夜晚 TST 的中位数
        var freeSleep: [Double] = []
        for index in totalSleepHours.indices where isFreeDay[index] {
            let (d1, d2) = previousDebts[index]
            if d1 < 0.5, d2 < 0.5 {
                freeSleep.append(totalSleepHours[index])
            }
        }
        let methodA = Statistics.median(freeSleep)

        // 方法 B：TST → 次日 z_hrv 的折线拐点
        var xs: [Double] = []
        var ys: [Double] = []
        for index in totalSleepHours.indices {
            if let z = nextZHRV[index] {
                xs.append(totalSleepHours[index])
                ys.append(z)
            }
        }
        let methodB = PiecewiseLinear.knee(x: xs, y: ys, grid: 5...10, step: 0.1)

        guard let a = methodA, let b = methodB else {
            return PersonalizedNeed(methodA: methodA, methodB: methodB, candidate: nil, updatedBase: currentBase, hint: "数据不足，本月不更新")
        }
        if abs(a - b) > 1 {
            return PersonalizedNeed(
                methodA: a,
                methodB: b,
                candidate: nil,
                updatedBase: currentBase,
                hint: "两种方法相差超过 1 小时，本月不更新，请检查数据"
            )
        }
        let candidate = min(max((a + b) / 2, 6.5), 9.5)
        let updated = 0.7 * currentBase + 0.3 * candidate
        return PersonalizedNeed(methodA: a, methodB: b, candidate: candidate, updatedBase: updated, hint: nil)
    }
}
