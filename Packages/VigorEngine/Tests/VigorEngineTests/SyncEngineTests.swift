import Foundation
import Testing
import VigorHealth
import VigorScoring
import VigorStore
@testable import VigorEngine

/// 记录每次读取范围的回放数据源。
actor RecordingSource: HealthDataSource {
    nonisolated let kind = DataSourceKind.synthetic
    private let replay: ReplayHealthDataSource
    private(set) var requests: [(from: Date, to: Date)] = []

    init(snapshot: HealthSnapshot) {
        replay = ReplayHealthDataSource(snapshot: snapshot, kind: .synthetic)
    }

    func requestAuthorization() async throws {}

    func snapshot(from: Date, to: Date, progress: @Sendable (Double, String) -> Void) async throws -> HealthSnapshot {
        requests.append((from, to))
        return try await replay.snapshot(from: from, to: to, progress: progress)
    }
}

@Suite("SyncEngine")
struct SyncEngineTests {
    let calendar = shanghaiCalendar()
    let end = shanghaiDate(2026, 10, 21, 12)

    func makeEngine(source: RecordingSource, cacheURL: URL?) throws -> SyncEngine {
        let repository = ScoreRepository(modelContainer: try VigorStoreFactory.makeContainer(inMemory: true))
        return SyncEngine(
            source: source,
            repository: repository,
            cache: cacheURL.map(SnapshotCache.init(url:)),
            calendar: calendar,
            historyDays: 40,
            appGroupID: "group.invalid.test"
        )
    }

    func scenario() -> HealthSnapshot {
        SyntheticScenario.make(nights: 30, seed: 7, endingAt: end, calendar: calendar).snapshot
    }

    @Test("首次刷新全量导入；之后只读取最近 3 天，并与缓存合并")
    func incrementalAfterFirstImport() async throws {
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let source = RecordingSource(snapshot: scenario())
        let engine = try makeEngine(source: source, cacheURL: cacheURL)

        try await engine.refresh(mode: .incremental, now: end.addingTimeInterval(-86_400))
        try await engine.refresh(mode: .incremental, now: end)

        let requests = await source.requests
        #expect(requests.count == 2)
        let historyStart = calendar.date(byAdding: .day, value: -40, to: end.addingTimeInterval(-86_400))!
        #expect(requests[0].from == historyStart)
        #expect(requests[1].from == calendar.date(byAdding: .day, value: -3, to: end)!)
        #expect(await engine.cachedSnapshot()?.rangeEnd == end)
    }

    @Test("增量刷新的评分结果与全量刷新一致")
    func incrementalMatchesFull() async throws {
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let snapshot = scenario()

        let incremental = try makeEngine(source: RecordingSource(snapshot: snapshot), cacheURL: cacheURL)
        try await incremental.refresh(mode: .incremental, now: end.addingTimeInterval(-2 * 86_400))
        try await incremental.refresh(mode: .incremental, now: end)
        let merged = try #require(await incremental.cachedSnapshot())

        let fullSource = RecordingSource(snapshot: snapshot)
        let fullRead = try await fullSource.snapshot(
            from: calendar.date(byAdding: .day, value: -40, to: end.addingTimeInterval(-2 * 86_400))!,
            to: end,
            progress: { _, _ in }
        )
        let cyclesMerged = ScoringPipeline.run(PipelineInput(snapshot: merged, now: end, calendar: calendar)).cycles
        let cyclesFull = ScoringPipeline.run(PipelineInput(snapshot: fullRead, now: end, calendar: calendar)).cycles
        #expect(cyclesMerged.count == cyclesFull.count)
        #expect(cyclesMerged.map { $0.recovery?.score } == cyclesFull.map { $0.recovery?.score })
        #expect(cyclesMerged.map(\.load.strain) == cyclesFull.map(\.load.strain))
    }

    @Test("缓存为空（授权前留下的）时改为全量读取")
    func emptyCacheTriggersFullRead() async throws {
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        var empty = scenario()
        empty.sleep = []
        empty.heartRate = []
        try await SnapshotCache(url: cacheURL).save(empty)

        let source = RecordingSource(snapshot: scenario())
        let engine = try makeEngine(source: source, cacheURL: cacheURL)
        try await engine.refresh(mode: .incremental, now: end)

        let requests = await source.requests
        #expect(requests.first?.from == calendar.date(byAdding: .day, value: -40, to: end)!)
    }

    @Test("请求合并取读取范围更大的模式")
    func strongerMode() {
        #expect(RefreshMode.stronger(nil, .incremental) == .window(days: 3))
        #expect(RefreshMode.stronger(.window(days: 3), .window(days: 30)) == .window(days: 30))
        #expect(RefreshMode.stronger(.full, .incremental) == .full)
        #expect(RefreshMode.stronger(.window(days: 30), .full) == .full)
    }
}
