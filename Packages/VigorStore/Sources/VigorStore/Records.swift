import Foundation
import SwiftData

/// 一个周期的记录（PRD §8.3 的 `Cycle`）。嵌套结构以 JSON 保存在 `payload` 中；需要查询的标量单独存放。
@Model
final class CycleRecord {
    @Attribute(.unique) var wakeTime: Date
    /// 醒来日，格式 yyyy-MM-dd（本地日期）
    var wakeDay: String
    var recovery: Double?
    var recoveryZone: String?
    var strain: Double
    var sleepScore: Double
    var stateRaw: String
    var qualityLevel: String
    var algorithmVersion: Int
    var configVersion: Int
    /// 输入哈希的位模式（UInt64 以 Int64 保存）
    var inputHash: Int64
    /// 锁定时刻；非空表示已锁定，只在配置版本变化或手动触发时覆盖
    var lockedAt: Date?
    var updatedAt: Date
    var payload: Data

    init(
        wakeTime: Date,
        wakeDay: String,
        recovery: Double?,
        recoveryZone: String?,
        strain: Double,
        sleepScore: Double,
        stateRaw: String,
        qualityLevel: String,
        algorithmVersion: Int,
        configVersion: Int,
        inputHash: Int64,
        lockedAt: Date?,
        updatedAt: Date,
        payload: Data
    ) {
        self.wakeTime = wakeTime
        self.wakeDay = wakeDay
        self.recovery = recovery
        self.recoveryZone = recoveryZone
        self.strain = strain
        self.sleepScore = sleepScore
        self.stateRaw = stateRaw
        self.qualityLevel = qualityLevel
        self.algorithmVersion = algorithmVersion
        self.configVersion = configVersion
        self.inputHash = inputHash
        self.lockedAt = lockedAt
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

/// 日志记录（PRD §8.3 的 `JournalEntry`）。
@Model
final class JournalRecord {
    @Attribute(.unique) var night: Date
    var energy: Int?
    var feltUnwell: Bool
    var payload: Data

    init(night: Date, energy: Int?, feltUnwell: Bool, payload: Data) {
        self.night = night
        self.energy = energy
        self.feltUnwell = feltUnwell
        self.payload = payload
    }
}

/// 算法配置的版本记录（PRD §8.3 的 `ScoringConfigRecord`）。
@Model
final class ConfigRecord {
    @Attribute(.unique) var version: Int
    var isCurrent: Bool
    var payload: Data
    var createdAt: Date

    init(version: Int, isCurrent: Bool, payload: Data, createdAt: Date) {
        self.version = version
        self.isCurrent = isCurrent
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// 手动修正的睡眠时段（PRD §5.2 第 8 条）。键为睡眠的夜晚（`nightKey`，yyyy-MM-dd），值为 `SleepOverride` 的 JSON。
/// 只改视图，不改 HealthKit 原始数据。
@Model
final class SleepOverrideRecord {
    @Attribute(.unique) var nightKey: String
    var payload: Data
    var updatedAt: Date

    init(nightKey: String, payload: Data, updatedAt: Date) {
        self.nightKey = nightKey
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// 手动排除的夜晚（PRD §5.2、设置中的“排除指定夜晚”）。键为醒来日（yyyy-MM-dd）。
@Model
final class ManualExclusionRecord {
    @Attribute(.unique) var wakeDay: String
    var createdAt: Date

    init(wakeDay: String, createdAt: Date) {
        self.wakeDay = wakeDay
        self.createdAt = createdAt
    }
}

/// 导入的 FIT 骑行（M6 §4.3）。`payload` 为解码后的 `RideStream`（JSON）；原始文件保存在 `RideFileStore` 中。
/// 去重键为 `fileID`（序列号 + 创建时间）。
@Model
final class ImportedRideRecord {
    @Attribute(.unique) var fileID: String
    var start: Date
    var importedAt: Date
    var rawFileName: String
    var payload: Data

    init(fileID: String, start: Date, importedAt: Date, rawFileName: String, payload: Data) {
        self.fileID = fileID
        self.start = start
        self.importedAt = importedAt
        self.rawFileName = rawFileName
        self.payload = payload
    }
}

/// 骑行汇总（M6 §3、§6）：分组后的每次骑行、FTP、PMC、90 天功率曲线。整体以 JSON 保存，每个存储只有一条（key 固定）。
@Model
final class CyclingSummaryRecord {
    @Attribute(.unique) var key: String
    var updatedAt: Date
    var payload: Data

    init(key: String, updatedAt: Date, payload: Data) {
        self.key = key
        self.updatedAt = updatedAt
        self.payload = payload
    }
}
