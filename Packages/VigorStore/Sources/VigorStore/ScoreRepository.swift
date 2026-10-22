import Foundation
import SwiftData
import VigorFIT
import VigorScoring

public enum ScoreRepositoryError: LocalizedError {
    case decodingFailed(Date)

    public var errorDescription: String? {
        switch self {
        case .decodingFailed(let date):
            "无法读取 \(date) 的周期记录，可能是数据结构已经变化。"
        }
    }
}

/// 所有写操作都在 `@ModelActor` 中完成（施工文档 §2.2）。
@ModelActor
public actor ScoreRepository {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    /// 写入一批周期。已锁定且配置版本未变化的记录保持不动，除非 `force` 为真（用户手动触发重算）。
    /// - Returns: 实际写入（新增或覆盖）的周期数
    @discardableResult
    public func upsert(_ cycles: [CycleResult], force: Bool = false, now: Date = Date()) throws -> Int {
        var written = 0
        for cycle in cycles {
            let wake = cycle.wakeTime
            let existing = try modelContext.fetch(
                FetchDescriptor<CycleRecord>(predicate: #Predicate { $0.wakeTime == wake })
            ).first

            if let existing, existing.lockedAt != nil, existing.configVersion == cycle.configVersion, !force {
                continue
            }
            let record = existing ?? CycleRecord(
                wakeTime: cycle.wakeTime,
                wakeDay: Self.dayString(cycle.wakeDay),
                recovery: nil,
                recoveryZone: nil,
                strain: 0,
                sleepScore: 0,
                stateRaw: "",
                qualityLevel: "",
                algorithmVersion: 0,
                configVersion: 0,
                inputHash: 0,
                lockedAt: nil,
                updatedAt: now,
                payload: Data()
            )
            record.wakeDay = Self.dayString(cycle.wakeDay)
            record.recovery = cycle.recovery?.score
            record.recoveryZone = cycle.recovery?.zone.rawValue
            record.strain = cycle.load.strain
            record.sleepScore = cycle.sleepScore.score
            record.stateRaw = cycle.recoveryState.rawValue
            record.qualityLevel = cycle.quality.level.rawValue
            record.algorithmVersion = cycle.algorithmVersion
            record.configVersion = cycle.configVersion
            record.inputHash = Int64(bitPattern: cycle.inputHash)
            record.updatedAt = now
            record.payload = try Self.encoder.encode(cycle)
            // 状态机进入“锁定”时记下时刻（PRD §5.13）
            if cycle.recoveryState == .locked, record.lockedAt == nil {
                record.lockedAt = now
            }
            if existing == nil {
                modelContext.insert(record)
            }
            written += 1
        }
        try modelContext.save()
        return written
    }

    /// 读取醒来时间在 [from, to] 内的周期，按时间升序。
    public func cycles(from: Date, to: Date) throws -> [CycleResult] {
        let descriptor = FetchDescriptor<CycleRecord>(
            predicate: #Predicate { $0.wakeTime >= from && $0.wakeTime <= to },
            sortBy: [SortDescriptor(\.wakeTime)]
        )
        return try modelContext.fetch(descriptor).map { record in
            guard let cycle = try? Self.decoder.decode(CycleResult.self, from: record.payload) else {
                throw ScoreRepositoryError.decodingFailed(record.wakeTime)
            }
            return cycle
        }
    }

    public func lockedCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<CycleRecord>(predicate: #Predicate { $0.lockedAt != nil }))
    }

    public func saveJournal(_ entry: JournalEntry) throws {
        let night = entry.night
        let existing = try modelContext.fetch(
            FetchDescriptor<JournalRecord>(predicate: #Predicate { $0.night == night })
        ).first
        let payload = try Self.encoder.encode(entry)
        if let existing {
            existing.energy = entry.energy
            existing.feltUnwell = entry.feltUnwell
            existing.payload = payload
        } else {
            modelContext.insert(JournalRecord(night: night, energy: entry.energy, feltUnwell: entry.feltUnwell, payload: payload))
        }
        try modelContext.save()
    }

    public func journal(from: Date, to: Date) throws -> [JournalEntry] {
        try modelContext.fetch(FetchDescriptor<JournalRecord>(
            predicate: #Predicate { $0.night >= from && $0.night <= to },
            sortBy: [SortDescriptor(\.night)]
        )).compactMap { try? Self.decoder.decode(JournalEntry.self, from: $0.payload) }
    }

    /// 保存一个配置版本，并把它设为当前版本。
    public func saveConfig(_ config: ScoringConfig, now: Date = Date()) throws {
        let version = config.configVersion
        for record in try modelContext.fetch(FetchDescriptor<ConfigRecord>()) {
            record.isCurrent = false
        }
        let existing = try modelContext.fetch(
            FetchDescriptor<ConfigRecord>(predicate: #Predicate { $0.version == version })
        ).first
        let payload = try Self.encoder.encode(config)
        if let existing {
            existing.payload = payload
            existing.isCurrent = true
        } else {
            modelContext.insert(ConfigRecord(version: version, isCurrent: true, payload: payload, createdAt: now))
        }
        try modelContext.save()
    }

    public func currentConfig() throws -> ScoringConfig? {
        let record = try modelContext.fetch(
            FetchDescriptor<ConfigRecord>(predicate: #Predicate { $0.isCurrent })
        ).first
        return try record.flatMap { try Self.decoder.decode(ScoringConfig.self, from: $0.payload) }
    }

    /// 所有保存过的配置版本，按版本号降序（最新的在前）。回滚与对比使用。
    public func configHistory() throws -> [ScoringConfig] {
        let records = try modelContext.fetch(FetchDescriptor<ConfigRecord>(
            sortBy: [SortDescriptor(\.version, order: .reverse)]
        ))
        return try records.map { try Self.decoder.decode(ScoringConfig.self, from: $0.payload) }
    }

    /// 全部手动修正的睡眠时段，键为夜晚（nightKey）。
    public func sleepOverrides() throws -> [DateComponents: SleepOverride] {
        var result: [DateComponents: SleepOverride] = [:]
        for record in try modelContext.fetch(FetchDescriptor<SleepOverrideRecord>()) {
            guard let key = Self.parseDay(record.nightKey),
                  let override = try? Self.decoder.decode(SleepOverride.self, from: record.payload)
            else { continue }
            result[key] = override
        }
        return result
    }

    /// 设置（或清除，传 nil）某个夜晚的睡眠时段修正。
    public func setSleepOverride(nightKey: DateComponents, _ override: SleepOverride?, now: Date = Date()) throws {
        let key = Self.dayString(nightKey)
        let existing = try modelContext.fetch(
            FetchDescriptor<SleepOverrideRecord>(predicate: #Predicate { $0.nightKey == key })
        ).first
        guard let override else {
            if let existing { modelContext.delete(existing) }
            try modelContext.save()
            return
        }
        let payload = try Self.encoder.encode(override)
        if let existing {
            existing.payload = payload
            existing.updatedAt = now
        } else {
            modelContext.insert(SleepOverrideRecord(nightKey: key, payload: payload, updatedAt: now))
        }
        try modelContext.save()
    }

    /// 全部手动排除的醒来日。
    public func manualExclusions() throws -> Set<DateComponents> {
        Set(try modelContext.fetch(FetchDescriptor<ManualExclusionRecord>()).compactMap { Self.parseDay($0.wakeDay) })
    }

    public func setManualExclusion(wakeDay: DateComponents, excluded: Bool, now: Date = Date()) throws {
        let key = Self.dayString(wakeDay)
        let existing = try modelContext.fetch(
            FetchDescriptor<ManualExclusionRecord>(predicate: #Predicate { $0.wakeDay == key })
        ).first
        if excluded, existing == nil {
            modelContext.insert(ManualExclusionRecord(wakeDay: key, createdAt: now))
        } else if !excluded, let existing {
            modelContext.delete(existing)
        }
        try modelContext.save()
    }

    /// 保存骑行汇总（每次刷新后覆盖）。
    public func saveCycling(_ output: CyclingOutput, now: Date = Date()) throws {
        let payload = try Self.encoder.encode(output)
        let existing = try modelContext.fetch(FetchDescriptor<CyclingSummaryRecord>(predicate: #Predicate { $0.key == "current" })).first
        if let existing {
            existing.payload = payload
            existing.updatedAt = now
        } else {
            modelContext.insert(CyclingSummaryRecord(key: "current", updatedAt: now, payload: payload))
        }
        try modelContext.save()
    }

    /// 最近一次保存的骑行汇总；从未保存或解码失败时为 nil。
    public func cyclingOutput() throws -> CyclingOutput? {
        guard let record = try modelContext.fetch(FetchDescriptor<CyclingSummaryRecord>(predicate: #Predicate { $0.key == "current" })).first else {
            return nil
        }
        return try? Self.decoder.decode(CyclingOutput.self, from: record.payload)
    }

    /// 是否已经导入过某个 FIT 文件（去重键）。
    public func hasImportedRide(fileID: String) throws -> Bool {
        var descriptor = FetchDescriptor<ImportedRideRecord>(predicate: #Predicate { $0.fileID == fileID })
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    /// 保存解码后的骑行。已存在时不做任何改动，返回 false。
    @discardableResult
    public func saveImportedRide(_ ride: RideStream, rawFileName: String, now: Date = Date()) throws -> Bool {
        if try hasImportedRide(fileID: ride.fileID) { return false }
        let payload = try Self.encoder.encode(ride)
        modelContext.insert(ImportedRideRecord(
            fileID: ride.fileID,
            start: ride.start,
            importedAt: now,
            rawFileName: rawFileName,
            payload: payload
        ))
        try modelContext.save()
        return true
    }

    /// 全部导入的骑行（按开始时间升序）。读取失败的记录被跳过。
    public func importedRides() throws -> [RideStream] {
        try modelContext.fetch(FetchDescriptor<ImportedRideRecord>(sortBy: [SortDescriptor(\.start)])).compactMap {
            try? Self.decoder.decode(RideStream.self, from: $0.payload)
        }
    }

    /// 导入记录的元数据（用于备份与设置页的列表）。
    public func importedRideRecords() throws -> [(fileID: String, importedAt: Date, rawFileName: String)] {
        try modelContext.fetch(FetchDescriptor<ImportedRideRecord>(sortBy: [SortDescriptor(\.start)])).map {
            ($0.fileID, $0.importedAt, $0.rawFileName)
        }
    }

    /// 删除一次导入（不删除原始文件，由调用方处理）。
    public func deleteImportedRide(fileID: String) throws {
        let found = try modelContext.fetch(FetchDescriptor<ImportedRideRecord>(predicate: #Predicate { $0.fileID == fileID }))
        for record in found { modelContext.delete(record) }
        try modelContext.save()
    }

    /// 把 "yyyy-MM-dd" 解析为日期分量（只含年月日）。格式不对时返回 nil。
    public static func parseDay(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    /// 日期分量的存储格式（yyyy-MM-dd），备份文件中的键也使用它。
    public static func dayString(_ day: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}
