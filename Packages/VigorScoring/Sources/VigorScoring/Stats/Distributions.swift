import Foundation

/// 分布函数（施工文档 §4.7）：Student t 分布的双侧 p 值，经正则化不完全 Beta 函数计算。
public enum Distributions {
    /// 正则化不完全 Beta 函数 I_x(a, b)，使用 Lentz 连分式（Numerical Recipes 形式）。
    public static func regularizedIncompleteBeta(x: Double, a: Double, b: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        let logFront = lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log(1 - x)
        let front = exp(logFront)
        if x < (a + 1) / (a + b + 2) {
            return front * continuedFraction(x: x, a: a, b: b) / a
        }
        return 1 - front * continuedFraction(x: 1 - x, a: b, b: a) / b
    }

    private static func continuedFraction(x: Double, a: Double, b: Double) -> Double {
        let tiny = 1e-300
        let epsilon = 3e-14
        let qab = a + b
        let qap = a + 1
        let qam = a - 1
        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        for m in 1...10_000 {
            let mD = Double(m)
            let m2 = 2 * mD
            var aa = mD * (b - mD) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d
            if abs(d) < tiny { d = tiny }
            c = 1 + aa / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            h *= d * c
            aa = -(a + mD) * (qab + mD) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d
            if abs(d) < tiny { d = tiny }
            c = 1 + aa / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            h *= delta
            if abs(delta - 1) < epsilon { break }
        }
        return h
    }

    /// Student t 分布的累积分布函数。
    public static func studentTCDF(_ t: Double, df: Double) -> Double {
        let x = df / (df + t * t)
        let tail = 0.5 * regularizedIncompleteBeta(x: x, a: df / 2, b: 0.5)
        return t >= 0 ? 1 - tail : tail
    }

    /// 双侧 p 值：2 · P(T ≥ |t|)。
    public static func twoSidedPValue(t: Double, df: Double) -> Double {
        let x = df / (df + t * t)
        return regularizedIncompleteBeta(x: x, a: df / 2, b: 0.5)
    }
}
