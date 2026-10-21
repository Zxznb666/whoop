import Foundation
import Testing
import VigorHealth
import VigorScoring
import VigorStore
@testable import VigorEngine

@Suite("手动修正与排除经同步链路传入流水线（F7）")
struct CorrectionsSyncTests {
    let calendar = shanghaiCalendar()
    let end = shanghaiDate(2026, 10, 21, 12)

    @Test("排除的醒来日标记为手动排除；修正的睡眠起点被评分使用")
    func settingsReachPipeline() async throws {
        let snapshot = SyntheticScenario.make(nights: 30, seed: 7, endingAt: end, calendar: calendar).snapshot
        let repository = ScoreRepository(modelContainer: try VigorStoreFactory.makeContainer(inMemory: true))
        let engine = SyncEngine(
            source: ReplayHealthDataSource(snapshot: snapshot, kind: .synthetic),
            repository: repository,
            cache: nil,
            calendar: calendar,
            historyDays: 40,
            appGroupID: "group.invalid.test"
        )
        // 只修改最近一晚：它还没有锁定，因此会被新的结果覆盖
        try await engine.refresh(mode: .full, now: end)
        let latest = try #require(try await repository.cycles(from: .distantPast, to: end).last)
        let newStart = latest.features.session.start.addingTimeInterval(30 * 60)

        try await engine.refresh(
            mode: .full,
            settings: ScoringSettings(
                sleepOverrides: [latest.features.session.nightKey: SleepOverride(start: newStart)],
                manualExcludedNights: [latest.wakeDay]
            ),
            now: end
        )

        let updated = try #require(try await repository.cycles(from: .distantPast, to: end).last)
        #expect(updated.wakeDay == latest.wakeDay)
        #expect(updated.exclusion == .manual)
        #expect(updated.features.session.start == newStart)
    }

    @Test("没有设置时，最近一晚不被标记为手动排除")
    func defaultSettingsChangeNothing() async throws {
        let snapshot = SyntheticScenario.make(nights: 30, seed: 7, endingAt: end, calendar: calendar).snapshot
        let repository = ScoreRepository(modelContainer: try VigorStoreFactory.makeContainer(inMemory: true))
        let engine = SyncEngine(
            source: ReplayHealthDataSource(snapshot: snapshot, kind: .synthetic),
            repository: repository,
            cache: nil,
            calendar: calendar,
            historyDays: 40,
            appGroupID: "group.invalid.test"
        )
        try await engine.refresh(mode: .full, now: end)
        let latest = try #require(try await repository.cycles(from: .distantPast, to: end).last)
        #expect(latest.exclusion != .manual)
    }
}
