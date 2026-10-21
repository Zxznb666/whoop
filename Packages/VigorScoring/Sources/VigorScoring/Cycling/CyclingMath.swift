import Foundation

/// 骑行专项指标（施工文档 §3）。输入均为 1 Hz 序列，下标 = 距骑行开始的秒数。
/// 功率的 nil 与暂停都按 0 计入（见 `padded`）。
public enum CyclingMath {
    /// 自动估算 FTP 时乘以的系数：最近 90 天最佳 20 分钟平均功率 × 0.95
    public static let autoFTPFactor = 0.95
    /// Coggan 功率区间的上界（相对 FTP，%）：Z1 < 55，Z2 < 76，Z3 < 91，Z4 < 106，Z5 < 121，Z6 ≤ 150，Z7 > 150
    static let zoneUpperBounds: [Double] = [55, 76, 91, 106, 121, 150]

    /// 1 Hz 功率：暂停区间与缺失值都按 0 填充，长度为 `duration`。
    public static func padded(_ power: [Int?], pauses: [Range<Int>], duration: Int) -> [Double] {
        var values = [Double](repeating: 0, count: max(0, duration))
        for index in values.indices where index < power.count {
            values[index] = Double(power[index] ?? 0)
        }
        for pause in pauses {
            for index in pause where index >= 0 && index < values.count {
                values[index] = 0
            }
        }
        return values
    }

    /// 30 秒滑动平均，从第 30 秒开始：结果第 j 项对应第 j + 29 秒。少于 30 秒时为空。
    public static func rollingAverage30(_ power: [Double]) -> [Double] {
        guard power.count >= 30 else { return [] }
        var sum = power[0..<30].reduce(0, +)
        var result = [sum / 30]
        for index in 30..<power.count {
            sum += power[index] - power[index - 30]
            result.append(sum / 30)
        }
        return result
    }

    /// 标准化功率（NP）：30 秒滑动平均的四次方均值再开四次方。少于 30 秒时为 nil。
    public static func normalizedPower(_ power: [Double]) -> Double? {
        normalizedPower(smoothed: rollingAverage30(power))
    }

    /// 已经做过 30 秒滑动平均的序列（`rollingAverage30` 的结果）上的 NP。
    public static func normalizedPower(smoothed: [Double]) -> Double? {
        guard !smoothed.isEmpty else { return nil }
        let fourth = smoothed.withUnsafeBufferPointer { values -> Double in
            var total = 0.0
            for value in values {
                let square = value * value
                total += square * square
            }
            return total
        } / Double(smoothed.count)
        return pow(fourth, 0.25)
    }

    /// 强度系数 IF = NP / FTP。
    public static func intensityFactor(normalizedPower: Double, ftp: Double) -> Double {
        normalizedPower / ftp
    }

    /// 训练压力 TSS = (时长秒 × NP × IF) / (FTP × 3600) × 100。
    public static func tss(durationSeconds: Double, normalizedPower: Double, ftp: Double) -> Double {
        let intensity = intensityFactor(normalizedPower: normalizedPower, ftp: ftp)
        return durationSeconds * normalizedPower * intensity / (ftp * 3600) * 100
    }

    /// 机械功（kJ）= Σ 功率 × Δt / 1000，Δt = 1 秒。
    public static func mechanicalWorkKJ(_ power: [Double]) -> Double {
        power.reduce(0, +) / 1000
    }

    /// 七个功率区间的秒数（Z1…Z7）。暂停的 0 瓦计入 Z1，调用方应传入暂停已剔除的序列。
    public static func zoneSeconds(_ power: [Double], ftp: Double) -> [Int] {
        var zones = [Int](repeating: 0, count: 7)
        zones.withUnsafeMutableBufferPointer { counts in
            for watts in power where watts > 0 {
                let percent = watts / ftp * 100
                let zone: Int
                if percent < 55 { zone = 0 } else if percent < 76 { zone = 1 } else if percent < 91 { zone = 2 }
                else if percent < 106 { zone = 3 } else if percent < 121 { zone = 4 } else if percent <= 150 { zone = 5 } else { zone = 6 }
                counts[zone] += 1
            }
        }
        return zones
    }

    /// 指定时长的最佳平均功率；序列不够长时为 nil。
    public static func bestAverage(_ power: [Double], seconds: Int) -> Double? {
        guard seconds > 0, power.count >= seconds else { return nil }
        return power.withUnsafeBufferPointer { values -> Double in
            var sum = 0.0
            for index in 0..<seconds { sum += values[index] }
            var best = sum
            var index = seconds
            while index < values.count {
                sum += values[index] - values[index - seconds]
                if sum > best { best = sum }
                index += 1
            }
            return best / Double(seconds)
        }
    }

    /// 功率曲线：指定时长（秒）的最佳平均功率，序列不够长的时长不出现在结果中。
    public static func powerCurve(_ power: [Double], durations: [Int] = PowerCurve.standardDurations) -> [Int: Double] {
        var curve: [Int: Double] = [:]
        for duration in durations {
            if let value = bestAverage(power, seconds: duration) { curve[duration] = value }
        }
        return curve
    }

    /// 自动估算 FTP：最近 90 天最佳 20 分钟平均功率 × 0.95。
    public static func estimatedFTP(bestTwentyMinutePower: Double) -> Double {
        bestTwentyMinutePower * autoFTPFactor
    }

    /// 有氧效率 EF = NP / 平均心率。
    public static func efficiencyFactor(normalizedPower: Double, averageHeartRate: Double) -> Double {
        normalizedPower / averageHeartRate
    }

    /// 有氧解耦（%）= (EF前 − EF后) / EF前 × 100。
    public static func aerobicDecoupling(firstHalfEF: Double, secondHalfEF: Double) -> Double {
        (firstHalfEF - secondHalfEF) / firstHalfEF * 100
    }
}

/// 功率曲线的标准时长（秒）：5 秒、1 分钟、5 分钟、20 分钟、60 分钟。
public enum PowerCurve {
    public static let standardDurations = [5, 60, 300, 1200, 3600]
}
