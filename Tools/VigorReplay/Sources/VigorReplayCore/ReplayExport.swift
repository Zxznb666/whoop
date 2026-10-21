import Foundation
import VigorScoring

/// 回放导出：把流水线的结果写成 CSV（PRD §5.14）。格式固定，便于逐行比对。
public enum ReplayExport {
    /// 黄金快照使用的关键列（施工文档 §5 阶段 5 第 4 条）。
    public static let goldenHeader = "date,recovery,strain,sleepScore,hrvRMSSD,quality"

    public static func golden(_ output: PipelineOutput, calendar: Calendar) -> String {
        var lines = [goldenHeader]
        for cycle in output.cycles {
            lines.append([
                dayString(cycle.wakeDay),
                number(cycle.recovery?.score, digits: 6),
                number(cycle.load.strain, digits: 6),
                number(cycle.sleepScore.score, digits: 6),
                number(cycle.features.hrv.displayRMSSD, digits: 6),
                cycle.quality.level.rawValue,
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func nights(_ output: PipelineOutput) -> String {
        let header = [
            "wakeDay", "wakeTime", "tst_h", "efficiency", "sri", "need_h", "debt_h", "sleep_score",
            "recovery", "zone", "z_hrv", "z_rhr", "z_resp", "temp_delta", "rhr", "rmssd",
            "quality", "illness", "exclusion", "state", "input_hash",
        ]
        var lines = [header.joined(separator: ",")]
        for cycle in output.cycles {
            lines.append([
                dayString(cycle.wakeDay),
                isoString(cycle.wakeTime),
                number(cycle.sleepMetrics.totalSleepHours, digits: 4),
                number(cycle.sleepMetrics.efficiency, digits: 4),
                number(cycle.sri, digits: 2),
                number(cycle.need.total, digits: 4),
                number(cycle.debtAfterNight, digits: 4),
                number(cycle.sleepScore.score, digits: 2),
                number(cycle.recovery?.score, digits: 2),
                cycle.recovery?.zone.rawValue ?? "",
                number(cycle.zHRV, digits: 4),
                number(cycle.zRHR, digits: 4),
                number(cycle.zResp, digits: 4),
                number(cycle.temperatureDelta, digits: 4),
                number(cycle.features.restingHeartRate.value, digits: 2),
                number(cycle.features.hrv.displayRMSSD, digits: 2),
                cycle.quality.level.rawValue,
                cycle.illness.rawValue,
                cycle.exclusion?.rawValue ?? "",
                cycle.recoveryState.rawValue,
                String(cycle.inputHash, radix: 16),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func cycles(_ output: PipelineOutput) -> String {
        let header = [
            "wakeDay", "wakeTime", "strain", "trimp", "counted_minutes", "unworn_minutes", "stress",
            "acwr", "target_lower", "target_upper", "workouts", "max_hr", "rest_hr", "model_enabled",
        ]
        var lines = [header.joined(separator: ",")]
        for cycle in output.cycles {
            lines.append([
                dayString(cycle.wakeDay),
                isoString(cycle.wakeTime),
                number(cycle.load.strain, digits: 4),
                number(cycle.load.trimp, digits: 4),
                "\(cycle.load.countedMinutes)",
                "\(cycle.load.unwornMinutes)",
                number(cycle.load.stress, digits: 4),
                number(cycle.acwr, digits: 4),
                number(cycle.loadTarget?.lower, digits: 2),
                number(cycle.loadTarget?.upper, digits: 2),
                "\(cycle.load.workouts.count)",
                number(cycle.load.maxHeartRate, digits: 1),
                number(cycle.load.restingHeartRate, digits: 2),
                cycle.load.activityModelEnabled ? "1" : "0",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func baselines(_ output: PipelineOutput) -> String {
        var lines = ["wakeDay,metric,mu,sigma,n"]
        for cycle in output.cycles {
            for metric in BaselineMetric.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let statistic = cycle.baselines[metric] else { continue }
                lines.append([
                    dayString(cycle.wakeDay),
                    metric.rawValue,
                    number(statistic.mu, digits: 6),
                    number(statistic.sigma, digits: 6),
                    "\(statistic.count)",
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 两次黄金输出之间，哪些天的分数变了、变了多少（施工文档 §5 阶段 5 第 4 条）。
    public static func goldenDiff(expected: String, actual: String) -> [String] {
        let expectedRows = expected.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let actualRows = actual.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var report: [String] = []
        if expectedRows.count != actualRows.count {
            report.append("行数不同：期望 \(expectedRows.count)，实际 \(actualRows.count)")
        }
        let names = expectedRows.first.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) } ?? []
        for (index, pair) in zip(expectedRows, actualRows).enumerated() where pair.0 != pair.1 {
            let old = pair.0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let new = pair.1.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let changed = zip(old, new).enumerated().filter { $0.element.0 != $0.element.1 }.map { entry -> String in
                let name = entry.offset < names.count ? names[entry.offset] : "列\(entry.offset)"
                return "\(name)：\(entry.element.0) → \(entry.element.1)"
            }
            report.append("第 \(index + 1) 行 \(old.first ?? "")：\(changed.joined(separator: "；"))")
        }
        return report
    }

    static func dayString(_ day: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func number(_ value: Double?, digits: Int) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(digits)f", value)
    }
}
