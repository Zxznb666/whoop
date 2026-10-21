import Foundation
import Testing
@testable import VigorScoring

@Suite("Sleep")
struct SleepTests {
    @Test("环形均值：23:50 与 00:10 → 00:00；完全相同的时刻 → 环形标准差 = 0")
    func circularWrapsMidnight() throws {
        let summary = try #require(CircularStatistics.summarize(minutesOfDay: [1430, 10]))
        let wrapped = min(summary.meanMinuteOfDay, 1440 - summary.meanMinuteOfDay)
        #expect(wrapped < 0.5)

        let identical = try #require(CircularStatistics.summarize(minutesOfDay: [600, 600, 600]))
        #expect(identical.standardDeviationMinutes < 1e-6)
    }

    @Test("SRI：7 天作息完全相同 → 100")
    func sriIdenticalDays() throws {
        let calendar = shanghaiCalendar()
        let endingAt = shanghaiDate(2026, 10, 21, 8)
        var stages: [SleepStageSample] = []
        for day in 0..<7 {
            let base = calendar.date(byAdding: .day, value: -day - 1, to: endingAt)!
            let bed = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: base)!
            let wake = bed.addingTimeInterval(8 * 3600)
            stages.append(SleepStageSample(start: bed, end: wake, stage: .core, sourceIsWatch: true))
        }
        // 白天醒着：覆盖每个完整的日子，使每一分钟都是已知状态
        let awakeStart = calendar.date(byAdding: .day, value: -7, to: endingAt)!
        stages.append(SleepStageSample(start: awakeStart, end: endingAt, stage: .awake, sourceIsWatch: true))
        let sri = try #require(SleepRegularity.sri(stages: stages, endingAt: endingAt, calendar: calendar))
        #expect(abs(sri - 100) < 1e-9)
    }

    @Test("SRI：少于 5 天的有效数据 → nil")
    func sriNeedsFiveDays() {
        let calendar = shanghaiCalendar()
        let endingAt = shanghaiDate(2026, 10, 21, 8)
        let stages = (1...4).map { day -> SleepStageSample in
            let base = calendar.date(byAdding: .day, value: -day, to: endingAt)!
            let bed = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: base)!
            return SleepStageSample(start: bed, end: bed.addingTimeInterval(8 * 3600), stage: .core, sourceIsWatch: true)
        }
        #expect(SleepRegularity.sri(stages: stages, endingAt: endingAt, calendar: calendar) == nil)
    }

    @Test("睡眠负债：基础 7.5 h，负荷 0，无小睡，D_prev = 0，TST = 6.5 h → D = 1.0 h；次晚需求 = 7.8 h")
    func debtRecurrence() {
        let components = SleepNeed.components(base: 7.5, loadAddition: 0, napCredit: 0, previousDebt: 0)
        let debt = SleepNeed.nextDebt(previousDebt: 0, baseNeed: components.baseNeed, totalSleep: 6.5)
        #expect(abs(debt - 1.0) < 1e-9)

        let next = SleepNeed.components(base: 7.5, loadAddition: 0, napCredit: 0, previousDebt: debt)
        #expect(abs(next.total - 7.8) < 1e-9)
    }

    @Test("睡眠负债被限制在 [0, 10] 小时")
    func debtClamped() {
        #expect(SleepNeed.nextDebt(previousDebt: 0, baseNeed: 7.5, totalSleep: 12) == 0)
        #expect(SleepNeed.nextDebt(previousDebt: 10, baseNeed: 7.5, totalSleep: 1) == 10)
    }

    @Test("需求构成：负荷追加最多 52 分钟；小睡抵扣为睡着时长的 0.8 倍")
    func needComponents() {
        // 昨日负荷 20 → 4 × (20 − 8) = 48 分钟
        #expect(abs(SleepNeed.loadAdditionHours(previousStrain: 20) - 48.0 / 60) < 1e-9)
        // 负荷 40 → 4 × 32 = 128 分钟，封顶 52 分钟
        #expect(abs(SleepNeed.loadAdditionHours(previousStrain: 40) - 52.0 / 60) < 1e-9)
        #expect(abs(SleepNeed.napCreditHours(napAsleepHours: 0.5) - 0.4) < 1e-9)
    }

    @Test("折线拐点：两段斜率不同的数据，拐点落在真实位置附近")
    func piecewiseKnee() throws {
        let x = (0..<60).map { 5 + Double($0) * 0.1 }
        let y = x.map { value -> Double in
            value < 7.5 ? 0.6 * (value - 7.5) : 0.1 * (value - 7.5)
        }
        let knee = try #require(PiecewiseLinear.knee(x: x, y: y, grid: 5...10, step: 0.1))
        #expect(abs(knee - 7.5) < 0.11)
    }

    @Test("个性化：A、B 相差超过 1 小时时不更新")
    func personalizationGuard() {
        let hours = [Double](repeating: 7, count: 70)
        let result = PersonalizedNeed.make(
            currentBase: 7.5,
            totalSleepHours: hours,
            previousDebts: [(Double, Double)](repeating: (0, 0), count: 70),
            isFreeDay: [Bool](repeating: true, count: 70),
            nextZHRV: [Double?](repeating: 0, count: 70)
        )
        #expect(result.updatedBase == 7.5)
        #expect(result.hint != nil)
    }

    @Test("睡眠分：各项都理想 → 接近 100")
    func idealSleepScore() {
        let score = SleepScoring.score(
            totalSleepHours: 8,
            napCreditHours: 0,
            needHours: 8,
            efficiency: 0.99,
            sri: 100,
            zRestorative: 2
        )
        #expect(abs(score.score - 100) < 1e-9)
        #expect(score.performance == 100)
        #expect(abs(score.zSleep - (100 - 80) / 12) < 1e-9)
    }

    @Test("睡眠分：一致性缺失时权重按比例分配给其余分量")
    func missingConsistencyReweights() {
        let score = SleepScoring.score(
            totalSleepHours: 8,
            napCreditHours: 0,
            needHours: 8,
            efficiency: 0.99,
            sri: nil,
            zRestorative: 0
        )
        // 时长 1、效率 1、修复 0.5：加权 (0.55 + 0.15 + 0.15 × 0.5) / 0.85
        let expected = 100 * (0.55 + 0.15 + 0.15 * 0.5) / 0.85
        #expect(abs(score.score - expected) < 1e-9)
        #expect(score.consistencyComponent == nil)
    }

    @Test("作息建议：要睡够 100% 的需求，入睡时刻 = 起床 − 需求 − 入睡耗时")
    func bedtimeAdviceBasic() {
        let wake = shanghaiDate(2026, 10, 22, 7)
        let advice = BedtimeAdvisor.advise(
            wakeTime: wake,
            needHours: 8,
            latencyMinutes: 15,
            averageBedtime: nil,
            previousBedtime: nil
        )
        #expect(advice.bedtimeAt100 == wake.addingTimeInterval(-(8 * 3600 + 15 * 60)))
        #expect(advice.bedtimeAt85 > advice.bedtimeAt100)
        #expect(!advice.progressivelyAdjusted)
    }

    @Test("作息建议：比 7 天平均早 60 分钟以上时，每晚最多提前 30 分钟")
    func bedtimeAdviceProgressive() {
        let wake = shanghaiDate(2026, 10, 22, 7)
        let previous = shanghaiDate(2026, 10, 21, 23)
        let advice = BedtimeAdvisor.advise(
            wakeTime: wake,
            needHours: 9,
            latencyMinutes: 15,
            averageBedtime: shanghaiDate(2026, 10, 21, 23, 30),
            previousBedtime: previous
        )
        #expect(advice.progressivelyAdjusted)
        #expect(advice.bedtimeAt100 == previous.addingTimeInterval(-30 * 60))
    }

    @Test("睡眠指标：WASO、觉醒次数与修复性睡眠比例")
    func metricsFromSession() throws {
        let bed = shanghaiDate(2026, 10, 21, 23)
        let wake = shanghaiDate(2026, 10, 22, 7)
        let stages = [
            SleepStageSample(start: bed, end: bed.addingTimeInterval(3600), stage: .deep, sourceIsWatch: true),
            SleepStageSample(start: bed.addingTimeInterval(3600), end: bed.addingTimeInterval(3600 + 600), stage: .awake, sourceIsWatch: true),
            SleepStageSample(start: bed.addingTimeInterval(4200), end: wake, stage: .rem, sourceIsWatch: true),
        ]
        let session = try #require(SleepSessionBuilder.sessions(
            stages: stages,
            inBed: [SleepStageSample(start: bed.addingTimeInterval(-600), end: wake, stage: .inBed, sourceIsWatch: false)],
            calendar: shanghaiCalendar()
        ).first)
        let metrics = SleepMetricsCalculator.make(session: session, bedtime: session.bedtime)
        // 醒着 10 分钟，持续 ≥ 2 分钟，计为 1 次觉醒
        #expect(metrics.awakenings == 1)
        #expect(abs(metrics.wasoMinutes - 10) < 1e-9)
        #expect(metrics.sleepLatencyMinutes == 10)
        // 深睡 1 小时 + REM（从 4200 秒到醒来，共 24600 秒）
        #expect(abs(metrics.restorativeHours - 28200.0 / 3600) < 1e-9)
        #expect(abs(metrics.restorativeFraction - 28200.0 / 28200.0) < 1e-9)
    }
}
