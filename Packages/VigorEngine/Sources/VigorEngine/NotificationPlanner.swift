import Foundation
import VigorScoring

/// 通知的种类（PRD §6.9）。
public enum NotificationKind: String, Sendable, Hashable, Codable {
    case recoveryReady
    case scoreUpdated
    case illness
    case bedtimeReminder
    case weeklyReport
    case journalReminder
}

public struct PlannedNotification: Sendable, Hashable {
    public var kind: NotificationKind
    /// 去重用的标识：每个周期每种通知最多一次（施工文档 §5 阶段 5 第 2 条）
    public var identifier: String
    public var title: String
    public var body: String
    public var fireDate: Date
    /// 相关的恢复分数（恢复分数已生成、已更新时有值）
    public var recoveryScore: Double?

    public init(
        kind: NotificationKind,
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        recoveryScore: Double? = nil
    ) {
        self.kind = kind
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.recoveryScore = recoveryScore
    }
}

/// 决定哪些通知需要发出。纯函数：同样的周期与已发送记录得到同样的结果。
public enum NotificationPlanner {
    /// 分数变化达到该值时发送“已更新”（PRD §5.13）
    public static let scoreUpdateThreshold = 5.0

    /// - Parameters:
    ///   - announcedRecovery: 之前发出“恢复分数已生成”时的分数（按醒来时间索引），用于判断是否需要“已更新”
    ///   - sent: 已经发送过的标识
    /// - Returns: 本次需要新发出的通知（不含 `sent` 中的标识）
    public static func plan(
        cycles: [CycleResult],
        announcedRecovery: [Date: Double],
        sent: Set<String>,
        calendar: Calendar
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []
        for cycle in cycles {
            let stamp = String(Int(cycle.wakeTime.timeIntervalSince1970))

            if let recovery = cycle.recovery {
                let ready = cycle.recoveryState == .final
                    || (cycle.recoveryState == .preliminary && cycle.quality.level.isAtLeastMedium)
                if ready {
                    planned.append(PlannedNotification(
                        kind: .recoveryReady,
                        identifier: "recoveryReady-\(stamp)",
                        title: "恢复分数已生成",
                        body: "今天的恢复 \(Int(recovery.score.rounded()))%，\(zoneText(recovery.zone))。",
                        fireDate: cycle.wakeTime,
                        recoveryScore: recovery.score
                    ))
                }
                if let announced = announcedRecovery[cycle.wakeTime],
                   abs(recovery.score - announced) >= scoreUpdateThreshold {
                    planned.append(PlannedNotification(
                        kind: .scoreUpdated,
                        identifier: "scoreUpdated-\(stamp)-\(Int(recovery.score.rounded()))",
                        title: "恢复分数已更新",
                        body: "由 \(Int(announced.rounded())) 更新为 \(Int(recovery.score.rounded()))。",
                        fireDate: cycle.wakeTime,
                        recoveryScore: recovery.score
                    ))
                }
            }

            if cycle.illness == .possiblyUnwell, !cycle.illnessConfounded {
                planned.append(PlannedNotification(
                    kind: .illness,
                    identifier: "illness-\(stamp)",
                    title: "身体信号需要留意",
                    body: "连续两晚的体温、呼吸、心率或 HRV 偏离了你的基线，今天注意休息。",
                    fireDate: cycle.wakeTime
                ))
            }
        }
        return planned.filter { !sent.contains($0.identifier) }
    }

    /// 醒来后的日志提醒（PRD §6.5）：只针对最近一次醒来；当天已经填写日志，或醒来已超过 12 小时，则不发。
    /// 触发时间晚于恢复分数通知 30 分钟，保证顺序在恢复分数之后。
    public static let journalReminderDelay: TimeInterval = 30 * 60
    public static let journalReminderWindow: TimeInterval = 12 * 3600

    /// - Parameters:
    ///   - journaledNights: 已经有日志的醒来日（本地零点）
    public static func journalReminder(
        latestWake: Date?,
        journaledNights: Set<Date>,
        sent: Set<String>,
        now: Date,
        calendar: Calendar
    ) -> [PlannedNotification] {
        guard let wake = latestWake, now.timeIntervalSince(wake) < journalReminderWindow else { return [] }
        let night = calendar.startOfDay(for: wake)
        guard !journaledNights.contains(night) else { return [] }
        let stamp = String(Int(wake.timeIntervalSince1970))
        let item = PlannedNotification(
            kind: .journalReminder,
            identifier: "journalReminder-\(stamp)",
            title: "昨天过得怎么样？",
            body: "花半分钟记录昨天的饮酒、咖啡因和状态，洞察会更准确。",
            fireDate: wake.addingTimeInterval(journalReminderDelay)
        )
        return sent.contains(item.identifier) ? [] : [item]
    }

    /// 周报推送（PRD §6.9）：每周日 20:00–21:59 之间发送一次，同一周只发一次。
    public static func weeklyReport(now: Date, sent: Set<String>, calendar: Calendar) -> [PlannedNotification] {
        guard calendar.component(.weekday, from: now) == 1 else { return [] }
        let hour = calendar.component(.hour, from: now)
        guard (20..<22).contains(hour) else { return [] }
        let sunday = calendar.startOfDay(for: now)
        let item = PlannedNotification(
            kind: .weeklyReport,
            identifier: "weeklyReport-\(Int(sunday.timeIntervalSince1970))",
            title: "本周报告已生成",
            body: "打开元气查看本周的恢复、负荷与睡眠变化。",
            fireDate: now
        )
        return sent.contains(item.identifier) ? [] : [item]
    }

    static func zoneText(_ zone: RecoveryZone) -> String {
        switch zone {
        case .green: "状态良好"
        case .yellow: "状态一般"
        case .red: "需要恢复"
        }
    }
}

extension DataQuality {
    var isAtLeastMedium: Bool { self == .high || self == .medium }
}
