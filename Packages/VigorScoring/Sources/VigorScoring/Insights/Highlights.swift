import Foundation

/// 亮点（D-067）：由固定规则从周期结果生成的短句，不使用模型，任何设备都能生成。
public struct Highlight: Sendable, Hashable, Identifiable {
    public enum Tone: String, Sendable, Hashable {
        case positive
        case neutral
        case caution
    }

    /// 规则标识，固定不变（测试与排序使用）
    public var id: String
    public var tone: Tone
    public var title: String
    public var detail: String

    public init(id: String, tone: Tone, title: String, detail: String) {
        self.id = id
        self.tone = tone
        self.title = title
        self.detail = detail
    }
}

/// 亮点规则。按固定顺序返回触发的规则；未触发的不返回。
public enum Highlights {
    /// 全部规则的标识（至少 8 条，覆盖 HRV 趋势、睡眠负债、负荷平衡、一致性、生病预警、校准期、数据质量与未佩戴）
    public static let ruleIDs = [
        "hrvTrend", "sleepDebt", "loadBalance", "regularity",
        "illness", "calibration", "dataQuality", "wear",
    ]

    /// 基线建立需要的周期数（与基线的冷启动收缩一致，见 `BaselineHistory`）
    public static let calibrationCycles = 14

    public static func make(cycles: [CycleResult]) -> [Highlight] {
        guard let today = cycles.last else { return [] }
        var highlights: [Highlight] = []

        // HRV 趋势：近 7 晚与近 28 晚的 RMSSD 均值之比
        let rmssd = cycles.compactMap(\.features.hrv.nightRMSSD)
        if rmssd.count >= 14 {
            let recent = mean(Array(rmssd.suffix(7)))
            let longer = mean(Array(rmssd.suffix(28)))
            if let recent, let longer, longer > 0 {
                let ratio = recent / longer
                if ratio >= 1.1 {
                    highlights.append(Highlight(id: "hrvTrend", tone: .positive, title: "HRV 高于近四周", detail: "近 7 晚的 RMSSD 比近 28 晚高 \(percent(ratio - 1))。"))
                } else if ratio <= 0.9 {
                    highlights.append(Highlight(id: "hrvTrend", tone: .caution, title: "HRV 低于近四周", detail: "近 7 晚的 RMSSD 比近 28 晚低 \(percent(1 - ratio))，注意休息。"))
                }
            }
        }

        if today.debtAfterNight >= 2 {
            highlights.append(Highlight(id: "sleepDebt", tone: .caution, title: "睡眠负债偏高", detail: String(format: "当前负债 %.1f 小时，今晚尽量早睡。", today.debtAfterNight)))
        } else if today.debtAfterNight <= 0.5 {
            highlights.append(Highlight(id: "sleepDebt", tone: .positive, title: "睡眠债已还清", detail: "睡眠负债接近零。"))
        }

        if let acwr = today.acwr {
            if acwr > 1.5 {
                highlights.append(Highlight(id: "loadBalance", tone: .caution, title: "近期负荷偏高", detail: String(format: "急性 / 慢性负荷比 %.2f，超过 1.5。", acwr)))
            } else if (0.8...1.3).contains(acwr) {
                highlights.append(Highlight(id: "loadBalance", tone: .positive, title: "负荷平衡", detail: String(format: "急性 / 慢性负荷比 %.2f，处于 0.8–1.3 的理想区间。", acwr)))
            }
        }

        if let sri = today.sri {
            if sri >= 80 {
                highlights.append(Highlight(id: "regularity", tone: .positive, title: "作息规律", detail: "睡眠规律性 \(Int(sri.rounded())) 分。"))
            } else if sri < 60 {
                highlights.append(Highlight(id: "regularity", tone: .caution, title: "作息不规律", detail: "睡眠规律性 \(Int(sri.rounded())) 分，入睡与醒来时间波动较大。"))
            }
        }

        if today.illness == .possiblyUnwell, !today.illnessConfounded {
            highlights.append(Highlight(id: "illness", tone: .caution, title: "身体信号需要留意", detail: "连续两晚的体温、呼吸、心率或 HRV 偏离基线，今天以休息为主。"))
        } else if today.illness == .attention {
            highlights.append(Highlight(id: "illness", tone: .neutral, title: "有一项信号偏离", detail: "再观察一晚；若连续偏离会提示。"))
        }

        if cycles.count < calibrationCycles {
            highlights.append(Highlight(id: "calibration", tone: .neutral, title: "基线仍在建立", detail: "已有 \(cycles.count) 晚，满 \(calibrationCycles) 晚后分数会更稳定。"))
        }

        if today.quality.level == .low {
            highlights.append(Highlight(id: "dataQuality", tone: .caution, title: "数据质量偏低", detail: "昨晚的有效数据不足，今天的分数仅供参考。"))
        }

        if today.features.partialWear {
            highlights.append(Highlight(id: "wear", tone: .caution, title: "昨晚佩戴不完整", detail: "睡眠中有超过 60 分钟没有心率记录，相关分数已降低可信度。"))
        }

        return highlights
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((abs(fraction) * 100).rounded()))%"
    }
}
