import Foundation

/// 负荷的数学部分（PRD §5.10、§5.11）。
public enum Strain {
    /// Banister TRIMP 的每分钟负荷：只计 HRR% ≥ 0.25 的分钟（§5.10 第 2 条）。
    /// 男性 x · 0.64 · e^(1.92x)，女性 x · 0.86 · e^(1.67x)；其他与未知取两者的平均。
    public static func trimpPerMinute(hrr: Double, sex: BiologicalSex) -> Double {
        guard hrr >= 0.25 else { return 0 }
        let x = min(max(hrr, 0), 1)
        let male = x * 0.64 * exp(1.92 * x)
        let female = x * 0.86 * exp(1.67 * x)
        switch sex {
        case .male: return male
        case .female: return female
        case .other, .unknown: return (male + female) / 2
        }
    }

    /// 对数映射：Strain = min(21, 5.3 · ln(1 + TRIMP / 10))。
    public static func strain(fromTRIMP trimp: Double) -> Double {
        min(21, 5.3 * log(1 + max(trimp, 0) / 10))
    }

    /// 心率储备百分比：(HR − RHR) / (HRmax − RHR)，截断在 [0, 1]（§5.1）。
    public static func hrr(heartRate: Double, restingHeartRate: Double, maxHeartRate: Double) -> Double {
        let reserve = maxHeartRate - restingHeartRate
        guard reserve > 0 else { return 0 }
        return min(max((heartRate - restingHeartRate) / reserve, 0), 1)
    }

    /// 心率区间（§5.1）：Z1 50–60%、Z2 60–70%、Z3 70–80%、Z4 80–90%、Z5 90–100%。返回 0…4，低于 50% 为 nil。
    public static func zoneIndex(hrr: Double) -> Int? {
        switch hrr {
        case 0.9...: 4
        case 0.8..<0.9: 3
        case 0.7..<0.8: 2
        case 0.6..<0.7: 1
        case 0.5..<0.6: 0
        default: nil
        }
    }
}

/// 负荷目标与负荷平衡（PRD §5.11）。
public struct LoadTarget: Sendable, Hashable, Codable {
    public var lower: Double
    public var upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }
}

public enum LoadTargets {
    /// 由恢复分区决定的初始目标：绿 14–18，黄 10–14，红 0–10。
    public static func baseTarget(for zone: RecoveryZone) -> LoadTarget {
        switch zone {
        case .green: LoadTarget(lower: 14, upper: 18)
        case .yellow: LoadTarget(lower: 10, upper: 14)
        case .red: LoadTarget(lower: 0, upper: 10)
        }
    }

    /// ACWR > 1.3 时区间下调 2（两端都下调，下限不低于 0）。
    public static func target(zone: RecoveryZone, acwr: Double?) -> LoadTarget {
        let base = baseTarget(for: zone)
        guard let acwr, acwr > 1.3 else { return base }
        return LoadTarget(lower: max(0, base.lower - 2), upper: max(0, base.upper - 2))
    }

    /// ACWR = 最近 7 天平均 TRIMP ÷ 最近 28 天平均 TRIMP。输入按时间升序，最后一个是“昨天及之前”的最近一天。
    public static func acwr(recentTRIMP: [Double]) -> Double? {
        guard recentTRIMP.count >= 7 else { return nil }
        let acute = Array(recentTRIMP.suffix(7))
        let chronic = Array(recentTRIMP.suffix(28))
        guard let chronicMean = Statistics.mean(chronic), chronicMean > 0,
              let acuteMean = Statistics.mean(acute)
        else { return nil }
        return acuteMean / chronicMean
    }
}
