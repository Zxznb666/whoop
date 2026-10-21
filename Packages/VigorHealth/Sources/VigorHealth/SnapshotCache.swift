import Foundation
import VigorFIT
import VigorScoring

/// 本地快照缓存：保存最近一次合并后的健康数据，使每次刷新只需从 HealthKit 读取最近几天（见 DECISIONS D-068）。
public actor SnapshotCache {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// 默认位置：`Application Support/snapshot-cache.json`。
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("snapshot-cache.json")
    }

    /// 文件不存在或无法解码时返回 nil（调用方应改为全量读取）。
    public func load() -> HealthSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? SnapshotCoding.decode(data)
    }

    public func save(_ snapshot: HealthSnapshot) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try SnapshotCoding.encode(snapshot).write(to: url, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

extension HealthSnapshot {
    /// 用 `fresh` 替换结束时间晚于 `cut` 的样本，并丢弃结束时间早于 `keepFrom` 的样本。
    ///
    /// HealthKit 的时间谓词返回与窗口重叠的样本，即结束时间晚于窗口起点的样本。
    /// 所以旧数据保留“结束时间 ≤ cut”的部分，新数据保留“结束时间 > cut”的部分，两者不重不漏。
    /// `cut` 之前被删除的样本不会被发现，需要定期用更大的窗口或全量读取来纠正。
    public func merging(_ fresh: HealthSnapshot, cut: Date, keepFrom: Date) -> HealthSnapshot {
        func splice<T>(_ old: [T], _ new: [T], end: (T) -> Date, start: (T) -> Date) -> [T] {
            let kept = old.filter { end($0) <= cut && end($0) >= keepFrom }
            let added = new.filter { end($0) > cut }
            return (kept + added).sorted { start($0) < start($1) }
        }
        func values(_ old: [ValueSample], _ new: [ValueSample]) -> [ValueSample] {
            splice(old, new, end: \.end, start: \.start)
        }

        var merged = fresh
        merged.rangeStart = max(min(rangeStart, fresh.rangeStart), keepFrom)
        merged.sleep = splice(sleep, fresh.sleep, end: \.end, start: \.start)
        merged.inBed = splice(inBed, fresh.inBed, end: \.end, start: \.start)
        merged.heartRate = splice(heartRate, fresh.heartRate, end: \.date, start: \.date)
        merged.hrvSDNN = values(hrvSDNN, fresh.hrvSDNN)
        merged.restingHeartRate = values(restingHeartRate, fresh.restingHeartRate)
        merged.respiratoryRate = values(respiratoryRate, fresh.respiratoryRate)
        merged.wristTemperature = values(wristTemperature, fresh.wristTemperature)
        merged.oxygenSaturation = values(oxygenSaturation, fresh.oxygenSaturation)
        merged.heartbeatSeries = splice(heartbeatSeries, fresh.heartbeatSeries, end: \.end, start: \.start)
        merged.mindfulSessions = values(mindfulSessions, fresh.mindfulSessions)
        merged.workouts = splice(workouts, fresh.workouts, end: \.end, start: \.start)
        merged.activeEnergy = values(activeEnergy, fresh.activeEnergy)
        merged.steps = values(steps, fresh.steps)
        merged.vo2Max = values(vo2Max, fresh.vo2Max)
        merged.heartRateRecovery = values(heartRateRecovery, fresh.heartRateRecovery)
        merged.breathingDisturbances = splice(breathingDisturbances, fresh.breathingDisturbances, end: \.end, start: \.start)
        merged.timeInDaylight = values(timeInDaylight, fresh.timeInDaylight)
        merged.dietaryCaffeine = values(dietaryCaffeine, fresh.dietaryCaffeine)
        merged.alcoholicBeverages = values(alcoholicBeverages, fresh.alcoholicBeverages)
        merged.stateOfMind = splice(stateOfMind, fresh.stateOfMind, end: \.date, start: \.date)
        merged.cyclingPower = values(cyclingPower, fresh.cyclingPower)
        merged.cyclingCadence = values(cyclingCadence, fresh.cyclingCadence)
        merged.cyclingSpeed = values(cyclingSpeed, fresh.cyclingSpeed)
        merged.ftp = values(ftp, fresh.ftp)
        // 导入的骑行不来自 HealthKit：由调用方每次完整提供，这里沿用 `fresh` 的列表，不做窗口拼接。
        merged.importedRides = fresh.importedRides
        return merged
    }
}
