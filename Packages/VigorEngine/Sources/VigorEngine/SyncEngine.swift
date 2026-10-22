import Foundation
import VigorFIT
import VigorHealth
import VigorScoring
import VigorStore

/// 同步的状态，供诊断页读取（施工文档 §5 阶段 5 第 2 条）。
public struct SyncStatus: Sendable, Hashable {
    public var lastSuccessAt: Date?
    public var lastError: String?
    public var lastCycleCount: Int
    public var progress: Double
    public var progressText: String
    /// 最近一次评分所用数据的条数（诊断用）
    public var inventory: SnapshotInventory?

    public init(
        lastSuccessAt: Date? = nil,
        lastError: String? = nil,
        lastCycleCount: Int = 0,
        progress: Double = 0,
        progressText: String = "",
        inventory: SnapshotInventory? = nil
    ) {
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.lastCycleCount = lastCycleCount
        self.progress = progress
        self.progressText = progressText
        self.inventory = inventory
    }
}

/// 一次刷新从 HealthKit 读取多少数据。
public enum RefreshMode: Sendable, Hashable {
    /// 只读取最近 `days` 天，与本地快照缓存合并；没有缓存时自动改为全量读取
    case window(days: Int)
    /// 读取全部历史窗口并重建缓存（首次导入、手动重新导入）
    case full

    /// 日常增量刷新：最近 3 天，足以覆盖晚到的温度、呼吸率和跨夜睡眠
    public static let incremental = RefreshMode.window(days: 3)

    /// 两个请求合并时取读取范围更大的那个。
    public static func stronger(_ lhs: RefreshMode?, _ rhs: RefreshMode) -> RefreshMode {
        switch (lhs, rhs) {
        case (nil, _): rhs
        case (.full?, _), (_, .full): .full
        case let (.window(a)?, .window(b)): .window(days: max(a, b))
        }
    }
}

/// 评分用到的用户设置（PRD §6.12）。
public struct ScoringSettings: Sendable, Hashable {
    public var baseSleepNeedHours: Double
    public var maxHeartRate: Double?
    public var targetWakeMinutes: Int?
    /// 手动修正的睡眠时段（键为夜晚）；只改视图，不改 HealthKit 原始数据（PRD §5.2 第 8 条）
    public var sleepOverrides: [DateComponents: SleepOverride]
    /// 手动排除的醒来日（设置中的“排除指定夜晚”）
    public var manualExcludedNights: Set<DateComponents>
    /// 导入的 FIT 骑行（M6）。不来自 HealthKit，每次刷新时由调用方提供，不进入快照缓存。
    public var importedRides: [RideStream]
    /// 手动设置的 FTP（瓦）；为 nil 时使用 HealthKit 或自动估算
    public var manualFTP: Double?
    /// 心率来源的手动指定（M6 补完 C5，键为 Bundle ID）；每次刷新时由调用方提供
    public var heartRateSourcePreferences: [String: SourcePreference]

    public init(
        baseSleepNeedHours: Double = 7.5,
        maxHeartRate: Double? = nil,
        targetWakeMinutes: Int? = nil,
        sleepOverrides: [DateComponents: SleepOverride] = [:],
        manualExcludedNights: Set<DateComponents> = [],
        importedRides: [RideStream] = [],
        manualFTP: Double? = nil,
        heartRateSourcePreferences: [String: SourcePreference] = [:]
    ) {
        self.baseSleepNeedHours = baseSleepNeedHours
        self.maxHeartRate = maxHeartRate
        self.targetWakeMinutes = targetWakeMinutes
        self.sleepOverrides = sleepOverrides
        self.manualExcludedNights = manualExcludedNights
        self.importedRides = importedRides
        self.manualFTP = manualFTP
        self.heartRateSourcePreferences = heartRateSourcePreferences
    }
}

/// 编排：读取健康数据 → 合并本地快照缓存 → 评分流水线 → 持久化 → 共享状态 → 通知计划。
/// 数据源是 `HealthDataSource` 协议，实时、合成与导入快照走同一条路径（施工文档 §5 阶段 5 第 2 条）。
public actor SyncEngine {
    private let source: any HealthDataSource
    private let repository: ScoreRepository
    private let cache: SnapshotCache?
    private let calendar: Calendar
    private let appGroupID: String
    /// 评分与缓存保留的历史天数
    private let historyDays: Int
    public private(set) var status = SyncStatus()
    /// 本次刷新中不致命的问题（缓存写入失败等），刷新结束时写入 `status.lastError`
    private var warnings: [String] = []

    public init(
        source: any HealthDataSource,
        repository: ScoreRepository,
        cache: SnapshotCache? = nil,
        calendar: Calendar,
        historyDays: Int = 180,
        appGroupID: String = "group.com.example.vigor"
    ) {
        self.source = source
        self.repository = repository
        self.cache = cache
        self.calendar = calendar
        self.historyDays = historyDays
        self.appGroupID = appGroupID
    }

    /// 本地缓存中的快照（界面用来计算身体年龄等需要原始数据的指标）。
    public func cachedSnapshot() async -> HealthSnapshot? {
        await cache?.load()
    }

    /// 一次刷新。失败时记录错误并抛出，不会崩溃（施工文档 §5 阶段 5 第 2 条）。
    @discardableResult
    public func refresh(
        mode: RefreshMode = .incremental,
        settings: ScoringSettings = ScoringSettings(),
        now: Date = Date(),
        announcedRecovery: [Date: Double] = [:],
        sent: Set<String> = []
    ) async throws -> [PlannedNotification] {
        warnings = []
        do {
            var snapshot = try await readSnapshot(mode: mode, now: now)
            let inventory = SnapshotInventory(snapshot)
            // 导入的骑行在评分前填入（不经过快照缓存，见 ScoringSettings.importedRides）
            snapshot.importedRides = settings.importedRides
            let journal = try await repository.journal(from: snapshot.rangeStart, to: now)
            let config = try await repository.currentConfig() ?? .default
            status.progressText = "计算分数"
            let output = ScoringPipeline.run(PipelineInput(
                snapshot: snapshot,
                journal: journal,
                sleepOverrides: settings.sleepOverrides,
                manualExcludedNights: settings.manualExcludedNights,
                baseSleepNeedHours: settings.baseSleepNeedHours,
                maxHeartRate: settings.maxHeartRate,
                targetWakeMinutes: settings.targetWakeMinutes,
                manualFTP: settings.manualFTP,
                heartRateSourcePreferences: settings.heartRateSourcePreferences,
                config: config,
                now: now,
                calendar: calendar
            ))
            try await repository.upsert(output.cycles, now: now)
            try await repository.saveCycling(output.cycling, now: now)
            let notifications = NotificationPlanner.plan(
                cycles: output.cycles,
                announcedRecovery: announcedRecovery,
                sent: sent,
                calendar: calendar
            )
            // 共享状态只服务小组件和手表，写失败不应让整次刷新失败
            if let last = output.cycles.last {
                do {
                    try writeSharedState(from: last, now: now)
                } catch {
                    warnings.append("共享状态写入失败：\(error)")
                }
            }
            status = SyncStatus(
                lastSuccessAt: now,
                lastError: warnings.isEmpty ? nil : warnings.joined(separator: "\n"),
                lastCycleCount: output.cycles.count,
                progress: 1,
                progressText: "完成",
                inventory: inventory
            )
            return notifications
        } catch {
            status.lastError = String(describing: error)
            status.progressText = "失败"
            throw error
        }
    }

    /// 按模式读取 HealthKit，并与缓存合并后写回。没有缓存时一律全量读取。
    private func readSnapshot(mode: RefreshMode, now: Date) async throws -> HealthSnapshot {
        let historyStart = calendar.date(byAdding: .day, value: -historyDays, to: now) ?? now
        // 空缓存（例如授权之前那次刷新留下的）视同没有缓存，避免历史数据永远导入不进来
        let cached: HealthSnapshot? = mode == .full ? nil : await cache?.load().flatMap {
            $0.sleep.isEmpty && $0.heartRate.isEmpty ? nil : $0
        }
        var readStart = historyStart
        if let cached, case let .window(days) = mode {
            let windowStart = calendar.date(byAdding: .day, value: -days, to: now) ?? now
            // 缓存过旧（覆盖不到窗口起点）时，从缓存末尾开始补读
            readStart = max(historyStart, min(windowStart, cached.rangeEnd))
        }
        status.progressText = cached == nil ? "导入历史数据" : "读取最近数据"
        let fresh = try await source.snapshot(from: readStart, to: now) { [weak self] fraction, text in
            Task { await self?.report(progress: fraction, text: text) }
        }
        let snapshot = cached?.merging(fresh, cut: readStart, keepFrom: historyStart) ?? fresh
        do {
            try await cache?.save(snapshot)
        } catch {
            // 缓存写失败不影响本次评分，下次刷新会退回全量读取
            warnings.append("快照缓存写入失败：\(error)")
        }
        return snapshot
    }

    func report(progress: Double, text: String) {
        status.progress = progress
        status.progressText = text
    }

    private func writeSharedState(from cycle: CycleResult, now: Date) throws {
        let state = SharedState(
            recovery: cycle.recovery?.score,
            recoveryZone: cycle.recovery?.zone.rawValue,
            strain: cycle.load.strain,
            strainTargetLower: cycle.loadTarget?.lower,
            strainTargetUpper: cycle.loadTarget?.upper,
            sleepScore: cycle.sleepScore.score,
            suggestedBedtime: cycle.bedtimeAdvice?.bedtimeAt100,
            stateRaw: cycle.recoveryState.rawValue,
            updatedAt: now,
            appGroupAvailable: SharedStateStore.appGroupFileURL(groupID: appGroupID) != nil
        )
        try SharedStateStore.write(state, groupID: appGroupID)
    }
}
