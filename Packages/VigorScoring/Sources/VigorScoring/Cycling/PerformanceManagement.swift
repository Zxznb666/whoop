import Foundation

/// 体能管理（PMC）的一天（施工文档 §3）。按自然日计算，没骑车的日子 TSS 为 0。
public struct PMCPoint: Sendable, Hashable, Codable {
    /// 当天 0 点（本地时区）
    public var day: Date
    public var tss: Double
    /// CTL_t = CTL_{t−1} + (TSS_t − CTL_{t−1}) / 42
    public var ctl: Double
    /// ATL_t = ATL_{t−1} + (TSS_t − ATL_{t−1}) / 7
    public var atl: Double
    /// TSB_t = CTL_{t−1} − ATL_{t−1}：当天开始时的状态
    public var tsb: Double

    public init(day: Date, tss: Double, ctl: Double, atl: Double, tsb: Double) {
        self.day = day
        self.tss = tss
        self.ctl = ctl
        self.atl = atl
        self.tsb = tsb
    }
}

public enum PerformanceManagement {
    public static let ctlTimeConstant = 42.0
    public static let atlTimeConstant = 7.0

    /// 从 `from` 所在的那天到 `through` 所在的那天（含）逐日计算。`tssByDay` 的键为当天 0 点。
    public static func series(
        tssByDay: [Date: Double],
        from: Date,
        through: Date,
        calendar: Calendar
    ) -> [PMCPoint] {
        var day = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: through)
        var ctl = 0.0
        var atl = 0.0
        var points: [PMCPoint] = []
        while day <= last {
            let tss = tssByDay[day] ?? 0
            let tsb = ctl - atl
            ctl += (tss - ctl) / ctlTimeConstant
            atl += (tss - atl) / atlTimeConstant
            points.append(PMCPoint(day: day, tss: tss, ctl: ctl, atl: atl, tsb: tsb))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    /// 状态文案（施工文档 §6 负荷页）：TSB < −20 疲劳累积；−10 至 +5 训练适宜；> +15 状态新鲜；其余为平稳。
    public static func statusText(tsb: Double) -> String {
        if tsb < -20 { return "疲劳累积" }
        if tsb > 15 { return "状态新鲜" }
        if tsb >= -10 && tsb <= 5 { return "训练适宜" }
        return "状态平稳"
    }
}
