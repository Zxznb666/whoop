import Foundation

/// 压力（0–3）（PRD §5.12.2）。
///
/// 基线是**日间**安静心率，而不是夜间静息心率：白天安静时的心率通常比睡眠时高 20%–40%，
/// 用夜间基线会让压力几乎总是满格（D-047）。
public enum Stress {
    /// 日间基线取最近的周期数
    public static let baselineCycles = 14
    /// 日间基线需要的最少有效天数；不足时退回到夜间静息心率 × `fallbackMultiplier`
    public static let minimumBaselineDays = 3
    public static let fallbackMultiplier = 1.15

    /// 每个符合条件的 15 分钟窗口：elev = (窗口平均心率 − μ_day) ÷ μ_day；stress = clamp(elev ÷ 0.10, 0, 3)。
    public static func windowStress(meanHeartRate: Double, daytimeBaseline: Double) -> Double {
        guard daytimeBaseline > 0 else { return 0 }
        let elevation = (meanHeartRate - daytimeBaseline) / daytimeBaseline
        return min(max(elevation / 0.10, 0), 3)
    }

    /// 某天的日间安静心率：当天所有安静窗口平均心率的 P20。没有安静窗口时为 nil。
    public static func daytimeQuietHeartRate(windowMeans: [Double]) -> Double? {
        Statistics.percentile(windowMeans, 0.20)
    }

    /// 日间基线 μ_day：之前最多 `baselineCycles` 个周期的日间安静心率中位数。
    /// - Parameter priorDaytime: **只能包含当天之前**的日间安静心率（按时间升序），不得包含当天或之后的数据。
    /// - Parameter restingHeartRate: 当天的夜间静息心率 μ；有效天数不足时用它 × 1.15 代替。
    public static func daytimeBaseline(priorDaytime: [Double], restingHeartRate: Double) -> Double {
        let recent = Array(priorDaytime.suffix(baselineCycles))
        if recent.count >= minimumBaselineDays, let median = Statistics.median(recent) {
            return median
        }
        return restingHeartRate * fallbackMultiplier
    }

    /// 当日压力：符合条件的窗口的平均值；当 z_hrv < −1 时加 0.5（上限仍为 3）。没有符合条件的窗口时为 nil。
    public static func daily(windowStresses: [Double], zHRV: Double?) -> Double? {
        guard !windowStresses.isEmpty else { return nil }
        let mean = windowStresses.reduce(0, +) / Double(windowStresses.count)
        let adjusted = (zHRV ?? 0) < -1 ? mean + 0.5 : mean
        return min(adjusted, 3)
    }
}
