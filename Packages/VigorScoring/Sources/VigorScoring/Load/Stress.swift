import Foundation

/// 压力（0–3）（PRD §5.12.2）。
public enum Stress {
    /// 每个符合条件的 15 分钟窗口：elev = (平均心率 − 夜间静息心率 μ) ÷ μ；stress = clamp(elev ÷ 0.10, 0, 3)。
    public static func windowStress(meanHeartRate: Double, restingHeartRate: Double) -> Double {
        guard restingHeartRate > 0 else { return 0 }
        let elevation = (meanHeartRate - restingHeartRate) / restingHeartRate
        return min(max(elevation / 0.10, 0), 3)
    }

    /// 当日压力：符合条件的窗口的平均值；当 z_hrv < −1 时每个窗口加 0.5（上限仍为 3）。没有符合条件的窗口时为 nil。
    public static func daily(windowStresses: [Double], zHRV: Double?) -> Double? {
        guard !windowStresses.isEmpty else { return nil }
        let mean = windowStresses.reduce(0, +) / Double(windowStresses.count)
        let adjusted = (zHRV ?? 0) < -1 ? mean + 0.5 : mean
        return min(adjusted, 3)
    }
}
