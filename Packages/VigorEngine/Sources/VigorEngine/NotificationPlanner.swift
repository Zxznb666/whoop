import Foundation
import VigorScoring

/// 通知的种类（PRD §6.9）。
public enum NotificationKind: String, Sendable, Hashable, Codable {
    case recoveryReady
    case scoreUpdated
    case illness
    case bedtimeReminder
    case weeklyReport
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
