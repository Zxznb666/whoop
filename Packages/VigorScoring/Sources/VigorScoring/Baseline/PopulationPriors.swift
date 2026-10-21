import Foundation

/// 人群先验（PRD §5.6 冷启动，施工文档 §4.6 的占位值）。
public enum PopulationPriors {
    /// 年龄段：<30、30–39、40–49、50–59、≥60；未知时按 30–39 处理。
    public static func ageGroup(birthYear: Int?, year: Int) -> Int {
        guard let birthYear else { return 1 }
        switch year - birthYear {
        case ..<30: return 0
        case 30..<40: return 1
        case 40..<50: return 2
        case 50..<60: return 3
        default: return 4
        }
    }

    static let nightRMSSD: [Double] = [55, 45, 36, 30, 26]
    static let sdnn: [Double] = [60, 52, 45, 40, 35]

    /// 返回先验的 μ（已是模型使用的尺度，即 ln 或原始单位）与 σ。
    public static func prior(
        for metric: BaselineMetric,
        profile: UserProfile,
        year: Int
    ) -> (mu: Double?, sigma: Double) {
        let group = ageGroup(birthYear: profile.birthYear, year: year)
        switch metric {
        case .lnRMSSDNight:
            return (log(nightRMSSD[group]), 0.30)
        case .lnRMSSDMorning:
            return (log(nightRMSSD[group] * 0.8), 0.30)
        case .lnSDNN:
            return (log(sdnn[group]), 0.30)
        case .restingHeartRate:
            let mu: Double = switch profile.sex {
            case .male: 55
            case .female: 58
            case .other, .unknown: 56
            }
            return (mu, 5)
        case .respiratoryRate:
            return (14.5, 1.2)
        case .wristTemperature:
            // 手腕温度不使用先验 μ，n = 0 时 Δt 记为 0
            return (nil, 0.25)
        case .oxygenSaturation:
            return (96.5, 1.0)
        case .totalSleepHours:
            return (7.0, 0.6)
        case .restorativeHours:
            return (2.6, 0.5)
        case .sleepLatencyMinutes:
            return (15, 8)
        }
    }
}
