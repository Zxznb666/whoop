import Foundation

/// 导出（PRD §6.11）：每日汇总 CSV、夜间特征 JSON。纯函数，文件写入由 App 负责。
public enum DailyExport {
    public static let csvHeader = [
        "wakeDay", "recovery", "recoveryZone", "recoveryState", "strain", "sleepScore",
        "zHRV", "zRHR", "zSleep", "nightRMSSD", "restingHeartRate", "sleepHours",
        "debtAfterNight", "illness", "exclusion", "configVersion", "algorithmVersion",
    ].joined(separator: ",")

    /// 每个周期一行，加表头。数值保留两位小数；缺失的字段留空。
    public static func csv(cycles: [CycleResult], calendar: Calendar) -> String {
        var lines = [csvHeader]
        for cycle in cycles {
            let day = cycle.wakeDay
            let date = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
            lines.append([
                date,
                number(cycle.recovery?.score),
                cycle.recovery?.zone.rawValue ?? "",
                cycle.recoveryState.rawValue,
                number(cycle.load.strain),
                number(cycle.sleepScore.score),
                number(cycle.zHRV),
                number(cycle.zRHR),
                number(cycle.recovery?.zSleep),
                number(cycle.features.hrv.nightRMSSD),
                number(cycle.features.restingHeartRate.value),
                number(cycle.sleepMetrics.totalSleepHours),
                number(cycle.debtAfterNight),
                cycle.illness.rawValue,
                cycle.exclusion.map { "\($0)" } ?? "",
                String(cycle.configVersion),
                String(cycle.algorithmVersion),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 夜间特征（`NightFeatures`）的 JSON，用于离线分析与调试。
    public static func featuresJSON(cycles: [CycleResult]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(cycles.map(\.features))
    }

    static func number(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? ""
    }
}
