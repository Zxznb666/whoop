import Foundation

/// 质量分的四个分量（PRD §5.7）。
public struct QualityComponents: Sendable, Hashable, Codable {
    public var hrv: Double
    public var heartRate: Double
    public var sleep: Double
    public var vitals: Double

    public init(hrv: Double, heartRate: Double, sleep: Double, vitals: Double) {
        self.hrv = hrv
        self.heartRate = heartRate
        self.sleep = sleep
        self.vitals = vitals
    }
}

public struct QualityReport: Sendable, Hashable, Codable {
    /// 0–1
    public var total: Double
    /// Q_hrv = 0 时为 `.none`：不出恢复分数
    public var level: DataQuality
    public var components: QualityComponents
    /// 面向用户的原因，例如 “昨晚只有 1 段有效 HRV”
    public var reasons: [String]

    public init(total: Double, level: DataQuality, components: QualityComponents, reasons: [String]) {
        self.total = total
        self.level = level
        self.components = components
        self.reasons = reasons
    }
}

public enum DataQualityScorer {
    public static func score(_ night: NightFeatures, config: ScoringConfig = .default) -> QualityReport {
        let hrv = hrvComponent(night.hrv, config: config)
        let heartRate = heartRateComponent(night)
        let sleep = night.session.stages.contains { $0.stage.isAsleep } ? night.heartRateCoverage : 0
        let vitals = vitalsComponent(night)
        let components = QualityComponents(hrv: hrv, heartRate: heartRate, sleep: sleep, vitals: vitals)
        let total = 0.5 * hrv + 0.2 * heartRate + 0.2 * sleep + 0.1 * vitals
        let level: DataQuality = hrv == 0 ? .none : level(for: total)
        return QualityReport(
            total: total,
            level: level,
            components: components,
            reasons: reasons(for: night, components: components)
        )
    }

    /// Q_hrv（§5.7）：有晨测直接取 1.0；否则按有效段数 3 段及以上 1.0、2 段 0.7、1 段 0.4；
    /// 只有 SDNN 兜底取 0.3；段间离散度 > 0.4 时乘 0.8。
    public static func hrvComponent(_ hrv: NightHRV, config: ScoringConfig = .default) -> Double {
        if hrv.morningValidCount >= 1 { return 1 }
        var value: Double
        switch hrv.nightValidCount {
        case 3...: value = 1
        case 2: value = 0.7
        case 1: value = 0.4
        default: value = hrv.sdnnMean != nil ? 0.3 : 0
        }
        if let dispersion = hrv.dispersion, dispersion > 0.4 {
            value *= 0.8
        }
        return value
    }

    /// Q_hr：睡眠期间每小时心率点数 ÷ 6，最高为 1。
    static func heartRateComponent(_ night: NightFeatures) -> Double {
        let hours = night.session.end.timeIntervalSince(night.session.start) / 3600
        guard hours > 0 else { return 0 }
        return min(1, Double(night.heartRateCount) / hours / 6)
    }

    /// Q_vitals：呼吸率、温度、血氧三项中可用的项数 ÷ 3。
    static func vitalsComponent(_ night: NightFeatures) -> Double {
        let available = [
            night.respiratoryRate != nil,
            night.wristTemperature != nil,
            night.spo2MedianPercent != nil,
        ].filter { $0 }.count
        return Double(available) / 3
    }

    static func level(for total: Double) -> DataQuality {
        if total >= 0.75 { return .high }
        if total >= 0.5 { return .medium }
        return .low
    }

    private static func reasons(for night: NightFeatures, components: QualityComponents) -> [String] {
        var reasons: [String] = []
        if components.hrv == 0 {
            reasons.append("没有任何 HRV 数据，不出恢复分数")
        } else if night.hrv.morningValidCount == 0 {
            switch night.hrv.nightValidCount {
            case 0: reasons.append("夜间没有有效 HRV 段，使用 SDNN 估算")
            case 1: reasons.append("昨晚只有 1 段有效 HRV")
            case 2: reasons.append("昨晚只有 2 段有效 HRV")
            default: break
            }
        }
        if let dispersion = night.hrv.dispersion, dispersion > 0.4 {
            reasons.append("各段 HRV 离散度较大")
        }
        if night.partialWear {
            reasons.append("睡眠期间有超过 60 分钟未佩戴")
        }
        if night.heartRateCoverage < 0.9 {
            reasons.append("睡眠期间心率覆盖不足")
        }
        return reasons
    }
}
