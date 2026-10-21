import Foundation

/// 生病预警的级别（PRD §5.12.1）。
public enum IllnessLevel: String, Sendable, Hashable, Codable {
    case none
    case attention
    case possiblyUnwell
}

/// 四个信号（相对个人基线判断）。
public struct IllnessSignals: Sendable, Hashable, Codable {
    /// T：Δt ≥ +0.5 °C
    public var temperature: Bool
    /// R：z_resp ≥ 1.5
    public var respiratory: Bool
    /// H：z_hrv ≤ −1.5
    public var hrv: Bool
    /// C：夜间静息心率 ≥ μ + 2σ
    public var restingHeartRate: Bool

    public init(temperature: Bool, respiratory: Bool, hrv: Bool, restingHeartRate: Bool) {
        self.temperature = temperature
        self.respiratory = respiratory
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
    }
}

public enum IllnessWarning {
    public static func signals(
        temperatureDelta: Double?,
        zResp: Double?,
        zHRV: Double?,
        restingHeartRate: Double?,
        restingBaseline: BaselineStatistic
    ) -> IllnessSignals {
        let rhrThreshold = restingBaseline.mu.map { $0 + 2 * restingBaseline.sigma }
        return IllnessSignals(
            temperature: (temperatureDelta ?? 0) >= 0.5,
            respiratory: (zResp ?? -.infinity) >= 1.5,
            hrv: (zHRV ?? .infinity) <= -1.5,
            restingHeartRate: restingHeartRate != nil && rhrThreshold != nil && restingHeartRate! >= rhrThreshold!
        )
    }

    /// 注意的条件：T 成立且 R、H、C 中至少一个成立；或者 T 不成立但 R、H、C 同时成立。
    public static func meetsAttentionCondition(_ signals: IllnessSignals) -> Bool {
        let any = signals.respiratory || signals.hrv || signals.restingHeartRate
        if signals.temperature {
            return any
        }
        return signals.respiratory && signals.hrv && signals.restingHeartRate
    }
}
