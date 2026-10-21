import Foundation

/// 基线适用的指标（PRD §5.6）。
public enum BaselineMetric: String, Sendable, Hashable, Codable, CaseIterable {
    case lnRMSSDNight
    case lnRMSSDMorning
    case lnSDNN
    case restingHeartRate
    case respiratoryRate
    case wristTemperature
    case oxygenSaturation
    case totalSleepHours
    case restorativeHours
    case sleepLatencyMinutes
}

/// 某一指标在某一晚的基线：μ 与 σ。`mu` 为 nil 时表示没有可用的先验（手腕温度且无样本）。
public struct BaselineStatistic: Sendable, Hashable, Codable {
    public var mu: Double?
    public var sigma: Double
    /// 窗口内的有效样本数 n
    public var count: Int

    /// 有效夜数少于 4 晚时为“校准期”（PRD §5.6）
    public var isCalibrating: Bool { count < 4 }

    public init(mu: Double?, sigma: Double, count: Int) {
        self.mu = mu
        self.sigma = sigma
        self.count = count
    }
}

/// 个人基线（PRD §5.6、施工文档 §4.6）。
public enum Baseline {
    /// 窗口：第 N 晚之前最近的 30 个有效夜晚
    public static let windowSize = 30
    /// 冷启动收缩的先验权重 n₀
    public static let priorWeight = 7.0

    /// - Parameters:
    ///   - values: 第 N 晚之前的有效值，按时间升序（只取最后 30 个）
    ///   - prior: 人群先验（μ 可为空，σ 必填）
    ///   - sigmaFloor: σ 下限
    public static func statistic(
        values: [Double],
        prior: (mu: Double?, sigma: Double),
        sigmaFloor: Double
    ) -> BaselineStatistic {
        let window = Array(values.suffix(windowSize))
        let n = window.count
        let personalMu = Statistics.median(window)
        let personalSigma = 1.4826 * (Statistics.mad(window) ?? 0)

        var mu: Double?
        var sigma: Double
        if n >= windowSize {
            mu = personalMu
            sigma = personalSigma
        } else {
            // 冷启动收缩：μ = (n₀ μ_先验 + n μ_个人) / (n₀ + n)，σ 同理
            let k = priorWeight
            let personal = personalMu ?? 0
            if let priorMu = prior.mu {
                mu = (k * priorMu + Double(n) * personal) / (k + Double(n))
            } else {
                mu = n == 0 ? nil : personal
            }
            sigma = (k * prior.sigma + Double(n) * personalSigma) / (k + Double(n))
        }
        return BaselineStatistic(mu: mu, sigma: max(sigma, sigmaFloor), count: n)
    }

    /// 每个指标的 σ 下限（PRD §5.6 表格）。时长类指标的下限是本项目的取值（PRD 未给出），见 DECISIONS。
    public static func sigmaFloor(for metric: BaselineMetric) -> Double {
        switch metric {
        case .lnRMSSDNight, .lnRMSSDMorning, .lnSDNN: 0.06
        case .restingHeartRate: 1.5
        case .respiratoryRate: 0.3
        case .wristTemperature: 0.15
        case .oxygenSaturation: 0.5
        case .totalSleepHours: 0.1
        case .restorativeHours: 0.1
        case .sleepLatencyMinutes: 2
        }
    }
}
