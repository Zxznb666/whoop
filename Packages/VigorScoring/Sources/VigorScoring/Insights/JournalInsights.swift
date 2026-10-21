import Foundation

/// 一条影响洞察（PRD §6.5）：某个行为做了与没做时，结果的差异。
public struct JournalInsight: Sendable, Hashable, Codable, Identifiable {
    public enum Outcome: String, Sendable, Hashable, Codable {
        case recovery
        case hrv
        case sleepPerformance
    }

    public var id: String { "\(behavior)-\(outcome.rawValue)" }
    public var behavior: String
    public var outcome: Outcome
    /// 做了 − 没做
    public var difference: Double
    public var confidenceLow: Double
    public var confidenceHigh: Double
    public var pValue: Double
    public var treatedCount: Int
    public var controlCount: Int
    /// 通俗文案，例如“饮酒后次日恢复平均低 14 分，差异明显”
    public var sentence: String

    public init(
        behavior: String,
        outcome: Outcome,
        difference: Double,
        confidenceLow: Double,
        confidenceHigh: Double,
        pValue: Double,
        treatedCount: Int,
        controlCount: Int,
        sentence: String
    ) {
        self.behavior = behavior
        self.outcome = outcome
        self.difference = difference
        self.confidenceLow = confidenceLow
        self.confidenceHigh = confidenceHigh
        self.pValue = pValue
        self.treatedCount = treatedCount
        self.controlCount = controlCount
        self.sentence = sentence
    }
}

/// 影响洞察（PRD §6.5）。日志的醒来日与周期的醒来日对齐：某行为之后醒来时的恢复、HRV 与睡眠表现，就是它的“次日”结果。
public enum JournalInsights {
    public static let minimumPerGroup = 5

    /// 按效应量（差值的绝对值）从大到小排序。每组至少需要 `minimumPerGroup` 个样本，并且能算出 Welch 检验。
    public static func compute(cycles: [CycleResult], journal: [JournalEntry], calendar: Calendar) -> [JournalInsight] {
        let byDay = Dictionary(
            cycles.map { (SleepSessionBuilder.dayComponents($0.wakeTime, calendar: calendar), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var insights: [JournalInsight] = []
        let behaviors = Set(journal.flatMap { $0.behaviors.keys }).sorted()
        for behavior in behaviors {
            var treated: [CycleResult] = []
            var control: [CycleResult] = []
            for entry in journal {
                guard let value = entry.behaviors[behavior],
                      let cycle = byDay[SleepSessionBuilder.dayComponents(entry.night, calendar: calendar)]
                else { continue }
                if value { treated.append(cycle) } else { control.append(cycle) }
            }
            guard treated.count >= minimumPerGroup, control.count >= minimumPerGroup else { continue }
            let outcomes: [(JournalInsight.Outcome, (CycleResult) -> Double?)] = [
                (.recovery, { $0.recovery?.score }),
                (.hrv, { $0.features.hrv.nightRMSSD }),
                (.sleepPerformance, { $0.sleepScore.performance }),
            ]
            for (outcome, value) in outcomes {
                let a = treated.compactMap(value)
                let b = control.compactMap(value)
                guard a.count >= minimumPerGroup, b.count >= minimumPerGroup,
                      let welch = Association.welch(a, b)
                else { continue }
                insights.append(JournalInsight(
                    behavior: behavior,
                    outcome: outcome,
                    difference: welch.difference,
                    confidenceLow: welch.confidenceLow,
                    confidenceHigh: welch.confidenceHigh,
                    pValue: welch.pValue,
                    treatedCount: a.count,
                    controlCount: b.count,
                    sentence: sentence(behavior: behavior, outcome: outcome, difference: welch.difference, pValue: welch.pValue)
                ))
            }
        }
        return insights.sorted { abs($0.difference) > abs($1.difference) }
    }

    static func sentence(behavior: String, outcome: JournalInsight.Outcome, difference: Double, pValue: Double) -> String {
        let subject = name(of: behavior)
        let direction = difference >= 0 ? "高" : "低"
        let magnitude: String
        switch outcome {
        case .recovery: magnitude = String(format: "%.0f 分", abs(difference))
        case .hrv: magnitude = String(format: "%.0f ms", abs(difference))
        case .sleepPerformance: magnitude = String(format: "%.0f 个百分点", abs(difference))
        }
        let clarity = pValue < 0.05 ? "差异明显" : "差异不明显"
        return "\(subject)后次日\(outcomeName(outcome))平均\(direction) \(magnitude)，\(clarity)。"
    }

    static func name(of behavior: String) -> String {
        switch behavior {
        case "alcohol": "饮酒"
        case "lateDinner": "晚餐过晚"
        case "caffeineAfter2pm": "14 点后摄入咖啡因"
        case "screenBeforeBed": "睡前看屏幕"
        case "sauna": "桑拿"
        case "lateTraining": "晚间训练"
        case "stress": "压力大"
        case "travel": "旅行"
        default: behavior
        }
    }

    static func outcomeName(_ outcome: JournalInsight.Outcome) -> String {
        switch outcome {
        case .recovery: "恢复"
        case .hrv: "HRV"
        case .sleepPerformance: "睡眠表现"
        }
    }
}
