import Foundation
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

    public init(
        lastSuccessAt: Date? = nil,
        lastError: String? = nil,
        lastCycleCount: Int = 0,
        progress: Double = 0,
        progressText: String = ""
    ) {
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.lastCycleCount = lastCycleCount
        self.progress = progress
        self.progressText = progressText
    }
}

/// 编排：读取健康数据 → 评分流水线 → 持久化 → 共享状态 → 通知计划。
/// 数据源是 `HealthDataSource` 协议，实时、合成与导入快照走同一条路径（施工文档 §5 阶段 5 第 2 条）。
public actor SyncEngine {
    private let source: any HealthDataSource
    private let repository: ScoreRepository
    private let calendar: Calendar
    private let appGroupID: String
    public private(set) var status = SyncStatus()

    public init(
        source: any HealthDataSource,
        repository: ScoreRepository,
        calendar: Calendar,
        appGroupID: String = "group.com.example.vigor"
    ) {
        self.source = source
        self.repository = repository
        self.calendar = calendar
        self.appGroupID = appGroupID
    }

    /// 一次完整的刷新。失败时记录错误并抛出，不会崩溃（施工文档 §5 阶段 5 第 2 条）。
    @discardableResult
    public func refresh(
        from start: Date,
        to end: Date,
        now: Date = Date(),
        announcedRecovery: [Date: Double] = [:],
        sent: Set<String> = []
    ) async throws -> [PlannedNotification] {
        do {
            status.progressText = "读取健康数据"
            let snapshot = try await source.snapshot(from: start, to: end) { [weak self] fraction, text in
                Task { await self?.report(progress: fraction, text: text) }
            }
            let journal = try await repository.journal(from: start, to: end)
            let config = try await repository.currentConfig() ?? .default
            let output = ScoringPipeline.run(PipelineInput(
                snapshot: snapshot,
                journal: journal,
                config: config,
                now: now,
                calendar: calendar
            ))
            try await repository.upsert(output.cycles, now: now)
            let notifications = NotificationPlanner.plan(
                cycles: output.cycles,
                announcedRecovery: announcedRecovery,
                sent: sent,
                calendar: calendar
            )
            if let last = output.cycles.last {
                try writeSharedState(from: last, now: now)
            }
            status = SyncStatus(lastSuccessAt: now, lastError: nil, lastCycleCount: output.cycles.count, progress: 1, progressText: "完成")
            return notifications
        } catch {
            status.lastError = String(describing: error)
            status.progressText = "失败"
            throw error
        }
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
