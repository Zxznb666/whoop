import Foundation
import SwiftUI
import VigorScoring

/// 集中的格式化函数，统一使用 zh_CN。
enum Formatters {
    static func wakeDay(_ date: Date) -> String {
        format(date, "M月d日 EEE")
    }

    static func clock(_ date: Date) -> String {
        format(date, "HH:mm")
    }

    static func clockRange(_ start: Date, _ end: Date) -> String {
        "\(clock(start))–\(clock(end))"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes / 60)小时\(minutes % 60)分"
    }

    static func rmssd(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) ms" } ?? "—"
    }

    static func bpm(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) bpm" } ?? "—"
    }

    static func number(_ value: Double?, digits: Int = 0, unit: String = "") -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", DisplayRounding.value(value, digits: digits)) + unit
    }

    /// 带正负号的数值（如 “+0.4 °C”）。接近零的值显示为 “+0.0”，不会出现 “-0.0”。
    static func signed(_ value: Double?, digits: Int = 1, unit: String = "") -> String {
        guard let value else { return "—" }
        return String(format: "%+.\(digits)f", DisplayRounding.value(value, digits: digits)) + unit
    }

    /// 输入为 0–1 的小数。
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func quality(_ quality: DataQuality) -> String {
        switch quality {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        case .none: "无"
        }
    }

    static func qualityColor(_ quality: DataQuality) -> Color {
        switch quality {
        case .high: .green
        case .medium: .yellow
        case .low: .orange
        case .none: .gray
        }
    }

    static func method(_ method: HRVMethod) -> String {
        switch method {
        case .morning: "晨测"
        case .overnight: "夜间"
        case .sdnnFallback: "SDNN 兜底"
        case .none: "无"
        }
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
