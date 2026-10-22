import Foundation

/// 骑行详情双轴曲线的刻度换算（M6 补完 C2）。纯函数，界面只负责画。
///
/// 左轴是功率（0 … `powerTop`）。Swift Charts 没有原生双纵轴，所以心率先线性映射到功率刻度：
/// `y = (hr − 静息) / (最大 − 静息) × powerTop`，右轴再把映射后的位置换算回 bpm 标注。
public enum RideChartScale {
    /// 功率轴上限：max(最大功率 × 1.1, FTP × 1.5)，向上取整到 50 W，至少 50 W。
    public static func powerTop(maxPower: Double, ftp: Double?) -> Double {
        let candidate = max(maxPower * 1.1, (ftp ?? 0) * 1.5)
        return max(50, (candidate / 50).rounded(.up) * 50)
    }

    /// 心率 → 功率刻度上的位置。
    public static func mappedHeartRate(_ bpm: Double, low: Double, high: Double, top: Double) -> Double {
        guard high > low else { return 0 }
        return (bpm - low) / (high - low) * top
    }

    /// 功率刻度上的位置 → 心率（右轴标注用，与 `mappedHeartRate` 互逆）。
    public static func heartRate(mapped y: Double, low: Double, high: Double, top: Double) -> Double {
        guard top > 0 else { return low }
        return low + y / top * (high - low)
    }

    /// 右轴的心率刻度：100、120、140、160、180 bpm 中落在范围内的值。
    public static func heartRateTicks(low: Double, high: Double) -> [Double] {
        stride(from: 100.0, through: 180.0, by: 20.0).filter { $0 >= low && $0 <= high }
    }
}
