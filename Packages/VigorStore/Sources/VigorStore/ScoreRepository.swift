import Foundation
import SwiftData
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

    static func dayString(_ day: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}
