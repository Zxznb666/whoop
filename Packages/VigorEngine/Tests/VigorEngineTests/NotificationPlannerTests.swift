import Foundation
import Testing
@testable import VigorEngine
import VigorScoring
import VigorHealth

@Suite("NotificationPlanner")
struct NotificationPlannerTests {
    private func cycle(
        wake: Date,
        state: ScoreState,
        quality: DataQuality = .high,
        recovery: Double = 70,
        illness: IllnessLevel = .none,
        confounded: Bool = false
    ) -> CycleResult {
        let base = defaultSyntheticCycle()
        var result = base
        result.wakeTime = wake
        result.recoveryState = state
        result.quality = QualityReport(total: 0.9, level: quality, components: base.quality.components, reasons: [])
        result.recovery = RecoveryScorer.score(RecoveryInputs(zHRV: (recovery - RecoveryScorer.baseline) / 20, zRHR: 0, zSleep: 0))
        result.illness = illness
        result.illnessConfounded = confounded
        return result
    }

    /// 通过流水线生成一个真实的周期，再改写需要的字段。
    private func defaultSyntheticCycle() -> CycleResult {
        let endingAt = shanghaiDate(2026, 10, 1, 0)
        let scenario = SyntheticScenario.make(nights: 30, seed: 42, endingAt: endingAt, calendar: shanghaiCalendar())
        return ScoringPipeline.run(PipelineInput(
            snapshot: scenario.snapshot,
            journal: scenario.journal,
            now: endingAt,
            calendar: shanghaiCalendar()
        )).cycles.last!
    }

    @Test("恢复分数已生成：只发一次")
    func recoveryReadyOncePerCycle() {
        let wake = shanghaiDate(2026, 9, 30, 7)
        let cycles = [cycle(wake: wake, state: .final)]
        let first = NotificationPlanner.plan(cycles: cycles, announcedRecovery: [:], sent: [], calendar: shanghaiCalendar())
        let ready = first.filter { $0.kind == .recoveryReady }
        #expect(ready.count == 1)

        let second = NotificationPlanner.plan(cycles: cycles, announcedRecovery: [:], sent: Set(ready.map(\.identifier)), calendar: shanghaiCalendar())
        #expect(second.filter { $0.kind == .recoveryReady }.isEmpty)
    }

    @Test("初步且质量低：不推送，等到最终；质量中及以上的初步状态推送")
    func lowQualityWaitsForFinal() {
        let wake = shanghaiDate(2026, 9, 30, 7)
        let low = NotificationPlanner.plan(
            cycles: [cycle(wake: wake, state: .preliminary, quality: .low)],
            announcedRecovery: [:], sent: [], calendar: shanghaiCalendar()
        )
        #expect(low.filter { $0.kind == .recoveryReady }.isEmpty)

        let medium = NotificationPlanner.plan(
            cycles: [cycle(wake: wake, state: .preliminary, quality: .medium)],
            announcedRecovery: [:], sent: [], calendar: shanghaiCalendar()
        )
        #expect(medium.filter { $0.kind == .recoveryReady }.count == 1)
    }

    @Test("分数变化 ≥ 5 时发送“已更新”，小于 5 不发送")
    func scoreUpdateThreshold() {
        let wake = shanghaiDate(2026, 9, 30, 7)
        let current = cycle(wake: wake, state: .final, recovery: 70)
        let announced = [wake: 60.0]
        let big = NotificationPlanner.plan(cycles: [current], announcedRecovery: announced, sent: [], calendar: shanghaiCalendar())
        #expect(big.contains { $0.kind == .scoreUpdated })

        let small = NotificationPlanner.plan(cycles: [current], announcedRecovery: [wake: 67], sent: [], calendar: shanghaiCalendar())
        #expect(!small.contains { $0.kind == .scoreUpdated })
    }

    @Test("生病预警：可能不适且未混杂饮酒时推送；混杂时不推送")
    func illnessNotification() {
        let wake = shanghaiDate(2026, 9, 30, 7)
        let sent = NotificationPlanner.plan(
            cycles: [cycle(wake: wake, state: .final, illness: .possiblyUnwell)],
            announcedRecovery: [:], sent: [], calendar: shanghaiCalendar()
        )
        #expect(sent.contains { $0.kind == .illness })

        let confounded = NotificationPlanner.plan(
            cycles: [cycle(wake: wake, state: .final, illness: .possiblyUnwell, confounded: true)],
            announcedRecovery: [:], sent: [], calendar: shanghaiCalendar()
        )
        #expect(!confounded.contains { $0.kind == .illness })
    }
}
