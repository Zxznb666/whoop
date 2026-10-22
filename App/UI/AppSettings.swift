import Foundation

/// 设置（PRD §6.12）。保存在本机的 UserDefaults 中，并直接影响评分流水线。
enum AppSettings {
    private static let baseNeedKey = "vigor.settings.baseSleepNeed"
    private static let maxHeartRateKey = "vigor.settings.maxHeartRate"
    private static let targetWakeKey = "vigor.settings.targetWakeMinutes"
    private static let manualFTPKey = "vigor.settings.manualFTP"

    static var baseSleepNeedHours: Double {
        get {
            let value = UserDefaults.standard.double(forKey: baseNeedKey)
            return value > 0 ? value : 7.5
        }
        set { UserDefaults.standard.set(min(max(newValue, 6.5), 9.5), forKey: baseNeedKey) }
    }

    /// 为 0 或未设置时由年龄自动确定。
    static var maxHeartRateOverride: Double? {
        get {
            let value = UserDefaults.standard.double(forKey: maxHeartRateKey)
            return value > 0 ? value : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: maxHeartRateKey) }
    }

    /// 目标起床时间，一天中的分钟数，默认 07:30。
    static var targetWakeMinutes: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: targetWakeKey) as? Int
            return stored ?? 450
        }
        set { UserDefaults.standard.set(newValue, forKey: targetWakeKey) }
    }

    /// 手动设置的 FTP（瓦）；为 0 或未设置时使用 HealthKit 或自动估算（M6 §3）。
    static var manualFTP: Double? {
        get {
            let value = UserDefaults.standard.double(forKey: manualFTPKey)
            return value > 0 ? value : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: manualFTPKey) }
    }
}
