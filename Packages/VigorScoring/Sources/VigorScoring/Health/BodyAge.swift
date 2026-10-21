import Foundation

/// 身体年龄（PRD §5.12.2）。系数为示意性取值，待校准；缺项按 0 计，并列出缺了哪些。
public struct BodyAgeInputs: Sendable, Hashable, Codable {
    /// 最大摄氧量（mL/kg/min）
    public var vo2Max: Double?
    /// 夜间静息心率的基线 μ（bpm）
    public var restingHeartRateBaseline: Double?
    /// 夜间 ln RMSSD 的基线 μ 与人群先验 μ
    public var lnRMSSDBaseline: Double?
    public var lnRMSSDPrior: Double?
    /// SRI（0–100）
    public var sri: Double?
    /// 日均步数
    public var dailySteps: Double?
    /// 每周 Z2 及以上心率区间的分钟数
    public var weeklyZone2PlusMinutes: Double?

    public init(
        vo2Max: Double? = nil,
        restingHeartRateBaseline: Double? = nil,
        lnRMSSDBaseline: Double? = nil,
        lnRMSSDPrior: Double? = nil,
        sri: Double? = nil,
        dailySteps: Double? = nil,
        weeklyZone2PlusMinutes: Double? = nil
    ) {
        self.vo2Max = vo2Max
        self.restingHeartRateBaseline = restingHeartRateBaseline
        self.lnRMSSDBaseline = lnRMSSDBaseline
        self.lnRMSSDPrior = lnRMSSDPrior
        self.sri = sri
        self.dailySteps = dailySteps
        self.weeklyZone2PlusMinutes = weeklyZone2PlusMinutes
    }
}

public struct BodyAgeResult: Sendable, Hashable, Codable {
    /// 偏移年数，截断在 ±15
    public var offsetYears: Double
    public var bodyAge: Double
    /// 缺少的项目名称
    public var missing: [String]

    public init(offsetYears: Double, bodyAge: Double, missing: [String]) {
        self.offsetYears = offsetYears
        self.bodyAge = bodyAge
        self.missing = missing
    }
}

public enum BodyAge {
    /// VO2max 参考值（男）：<30、30–39、40–49、50–59、≥60；女性各减 6。
    static let vo2Reference: [Double] = [45, 43, 41, 38, 35]

    public static func vo2Reference(age: Int, sex: BiologicalSex) -> Double {
        let group: Int
        switch age {
        case ..<30: group = 0
        case 30..<40: group = 1
        case 40..<50: group = 2
        case 50..<60: group = 3
        default: group = 4
        }
        let male = vo2Reference[group]
        return sex == .female ? male - 6 : male
    }

    public static func compute(chronologicalAge: Int, sex: BiologicalSex, inputs: BodyAgeInputs) -> BodyAgeResult {
        var missing: [String] = []
        let reference = vo2Reference(age: chronologicalAge, sex: sex)

        let vo2Term: Double
        if let vo2 = inputs.vo2Max { vo2Term = -0.6 * (vo2 - reference) } else { vo2Term = 0; missing.append("最大摄氧量") }

        let rhrTerm: Double
        if let rhr = inputs.restingHeartRateBaseline { rhrTerm = 0.25 * (rhr - 60) } else { rhrTerm = 0; missing.append("静息心率") }

        let hrvTerm: Double
        if let baseline = inputs.lnRMSSDBaseline, let prior = inputs.lnRMSSDPrior {
            hrvTerm = -4 * (baseline - prior)
        } else {
            hrvTerm = 0
            missing.append("HRV")
        }

        let sriTerm: Double
        if let sri = inputs.sri { sriTerm = -0.05 * (sri - 75) } else { sriTerm = 0; missing.append("睡眠规律") }

        let stepsTerm: Double
        if let steps = inputs.dailySteps { stepsTerm = -0.0004 * (steps - 8000) } else { stepsTerm = 0; missing.append("日均步数") }

        let zone2Term: Double
        if let minutes = inputs.weeklyZone2PlusMinutes { zone2Term = -0.02 * (minutes - 150) } else { zone2Term = 0; missing.append("每周 Z2+ 时长") }

        let raw = vo2Term + rhrTerm + hrvTerm + sriTerm + stepsTerm + zone2Term
        let offset = min(max(raw, -15), 15)
        return BodyAgeResult(offsetYears: offset, bodyAge: Double(chronologicalAge) + offset, missing: missing)
    }
}

/// 心肺适能趋势（PRD §5.12.2）：VO2max 的 90 天线性斜率与 1 分钟心率恢复的 90 天中位数变化。
public enum CardioFitness {
    /// 最小二乘斜率（单位：每天）。点数不足 2 个或 x 没有变化时为 nil。
    public static func slopePerDay(_ points: [(date: Date, value: Double)]) -> Double? {
        guard points.count >= 2, let first = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map(\.value)
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - mx) * (y - my)
            denominator += (x - mx) * (x - mx)
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    /// 后半段中位数减前半段中位数。
    public static func recoveryChange(_ values: [Double]) -> Double? {
        guard values.count >= 4 else { return nil }
        let half = values.count / 2
        guard let early = Statistics.median(Array(values.prefix(half))),
              let late = Statistics.median(Array(values.suffix(values.count - half)))
        else { return nil }
        return late - early
    }
}
