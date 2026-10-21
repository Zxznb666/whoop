import Foundation
import UserNotifications
import VigorEngine

/// 本地通知（PRD §6.9）。去重记录保存在本机，每个周期每种通知最多发送一次。
@MainActor
enum NotificationScheduler {
    private static let sentKey = "vigor.notifications.sent"
    private static let announcedKey = "vigor.notifications.announced"

    static var sent: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: sentKey) ?? [])
    }

    /// 已发出“恢复分数已生成”时的分数，按醒来时间的时间戳索引；用于判断“已更新”。
    static var announcedRecovery: [Date: Double] {
        let raw = UserDefaults.standard.dictionary(forKey: announcedKey) as? [String: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Double(key).map { (Date(timeIntervalSince1970: $0), value) }
        })
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            DiagnosticsLog.record("通知授权失败：\(error.localizedDescription)")
            return false
        }
    }

    static func schedule(_ planned: [PlannedNotification]) async {
        var sent = Self.sent
        for item in planned where !sent.contains(item.identifier) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
                sent.insert(item.identifier)
                if item.kind == .recoveryReady || item.kind == .scoreUpdated {
                    rememberAnnouncement(item)
                }
            } catch {
                DiagnosticsLog.record("通知发送失败（\(item.kind.rawValue)）：\(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(Array(sent), forKey: sentKey)
    }

    /// 只记录“恢复分数已生成”那次的分数；之后的“已更新”以它为基准比较。标识格式：<类型>-<醒来时间戳>[-<分数>]。
    private static func rememberAnnouncement(_ item: PlannedNotification) {
        guard item.kind == .recoveryReady, let score = item.recoveryScore else { return }
        var raw = UserDefaults.standard.dictionary(forKey: announcedKey) as? [String: Double] ?? [:]
        let stamp = item.identifier.split(separator: "-").dropFirst().first.map(String.init) ?? ""
        raw[stamp] = score
        UserDefaults.standard.set(raw, forKey: announcedKey)
    }
}
