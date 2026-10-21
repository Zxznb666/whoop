import Foundation
import Testing
@testable import VigorScoring

@Suite("Insights, reports, body age and fitness")
struct InsightsAndReportTests {
    /// 只填写报告与洞察需要的字段；其余字段取中性值。
    private func cycle(wake: Date, recovery: Double, debt: Double = 0, strain: Double = 10, hrv: Double = 40) -> CycleResult {
        let session = SleepSession(
            start: wake.addingTimeInterval(-8 * 3600),
            end: wake,
            bedtime: nil,
            stages: [],
            asleepDuration: 8 * 3600,
            wakeDay: DateComponents(year: 2026, month: 10, day: 1),
            nightKey: DateComponents(year: 2026, month: 9, day: 30),
            kind: .main,
            timeZoneOffset: 28800,
            longAwakeGaps: []
        )
        let features = NightFeatures(
            session: session,
            hrv: NightHRV(nightRMSSD: hrv, nightValidCount: 3, nightTotalCount: 3, morningRMSSD: nil, morningValidCount: 0, sdnnMean: nil, dispersion: nil, method: .overnight),
            windows: [],
            restingHeartRate: RestingHeartRate(value: 52, source: .sampledP10, sampleCount: 40, meanHeartRate: 58, lowestTimePosition: 0.5),
            meanHeartRate: 58,
            heartRateCount: 100,
            partialWear: false,
            longestHeartRateGapMinutes: 10,
            heartRateCoverage: 1,
            awakenings: 1,
            respiratoryRate: 14,
            wristTemperature: 36.4,
            spo2MedianPercent: 97,
            spo2BelowFraction: 0,
            breathingDisturbance: nil,
            breathingDisturbanceUnit: nil,
            appleRestingHeartRate: 53
        )
        return CycleResult(
            wakeDay: DateComponents(year: 2026, month: 10, day: 1),
            wakeTime: wake,
            features: features,
            quality: QualityReport(total: 0.9, level: .high, components: QualityComponents(hrv: 1, heartRate: 1, sleep: 1, vitals: 1), reasons: []),
            baselines: [:],
            zHRV: 0,
            zRHR: 0,
            zResp: 0,
            temperatureDelta: 0,
            sleepMetrics: SleepMetrics(totalSleepHours: 7.5, efficiency: 0.92, efficiencyIsSleepPeriod: false, sleepLatencyMinutes: 12, wasoMinutes: 20, awakenings: 1, remLatencyMinutes: 60, restorativeHours: 3, restorativeFraction: 0.4),
            sri: 80,
            need: SleepNeedComponents(base: 7.5, loadAddition: 0, napCredit: 0, debtRepayment: 0, baseNeed: 7.5),
            sleepScore: SleepScore(score: 80, performance: 90, durationAchieved: 0.9, efficiencyComponent: 0.8, consistencyComponent: 0.8, restorativeComponent: 0.5, zSleep: 0),
            debtAfterNight: debt,
            illnessSignals: IllnessSignals(temperature: false, respiratory: false, hrv: false, restingHeartRate: false),
            illness: .none,
            illnessConfounded: false,
            exclusion: nil,
            recovery: RecoveryScorer.score(RecoveryInputs(zHRV: 0, zRHR: 0, zSleep: 0)).map { result in
                var copy = result
                copy.score = recovery
                return copy
            },
            recoveryState: .final,
            load: CycleLoad(trimp: 50, strain: strain, countedMinutes: 900, unwornMinutes: 0, zoneMinutes: [0, 0, 0, 0, 0], maxHeartRate: 185, restingHeartRate: 52, activityModelEnabled: false, workouts: [], stress: nil),
            acwr: nil,
            loadTarget: nil,
            trend: nil,
            bedtimeAdvice: nil,
            algorithmVersion: 1,
            configVersion: 1,
            inputHash: 0
        )
    }

    @Test("饮酒洞察：做了与没做各 6 个样本，次日恢复平均低 14 分 → 文案与排序")
    func alcoholInsightSentence() throws {
        let calendar = shanghaiCalendar()
        var cycles: [CycleResult] = []
        var journal: [JournalEntry] = []
        for day in 0..<12 {
            let wake = shanghaiDate(2026, 9, 1 + day, 7)
            let drank = day % 2 == 0
            cycles.append(cycle(wake: wake, recovery: drank ? 50 + Double(day % 3) * 0.5 : 64 + Double(day % 3) * 0.5))
            journal.append(JournalEntry(night: calendar.startOfDay(for: wake), behaviors: ["alcohol": drank]))
        }
        let insights = JournalInsights.compute(cycles: cycles, journal: journal, calendar: calendar)
        let top = try #require(insights.first { $0.outcome == .recovery })
        #expect(top.behavior == "alcohol")
        #expect(top.difference < 0)
        #expect(abs(top.difference + 14) < 1)
        #expect(top.sentence.contains("饮酒后次日恢复平均低"))
        #expect(top.sentence.contains("差异明显"))
    }

    @Test("洞察：每组至少 5 个样本，否则不显示")
    func insightNeedsFivePerGroup() {
        let calendar = shanghaiCalendar()
        let cycles = (0..<8).map { cycle(wake: shanghaiDate(2026, 9, 1 + $0, 7), recovery: 60) }
        let journal = (0..<8).map { JournalEntry(night: calendar.startOfDay(for: shanghaiDate(2026, 9, 1 + $0, 7)), behaviors: ["alcohol": $0 < 2]) }
        #expect(JournalInsights.compute(cycles: cycles, journal: journal, calendar: calendar).allSatisfy { $0.behavior != "alcohol" })
    }

    @Test("周报边界：周日 23:59 属于本周，下周一 00:00 属于下一周")
    func weekBoundary() throws {
        let calendar = shanghaiCalendar()
        // 2026-09-27 是周日，2026-09-28 是周一
        let sundayLate = shanghaiDate(2026, 9, 27, 23, 59)
        let mondayStart = shanghaiDate(2026, 9, 28, 0, 0)
        let week = try #require(ReportBuilder.week(containing: sundayLate, cycles: [], journal: [], calendar: calendar))
        #expect(week.end == mondayStart)
        let next = try #require(ReportBuilder.week(containing: mondayStart, cycles: [], journal: [], calendar: calendar))
        #expect(next.start == mondayStart)
    }

    @Test("周报汇总：平均恢复、最好与最差的一天、训练次数与睡眠负债变化")
    func weeklySummary() throws {
        let calendar = shanghaiCalendar()
        let cycles = [
            cycle(wake: shanghaiDate(2026, 9, 28, 7), recovery: 40, debt: 1.0),
            cycle(wake: shanghaiDate(2026, 9, 29, 7), recovery: 80, debt: 0.5),
            cycle(wake: shanghaiDate(2026, 9, 30, 7), recovery: 60, debt: 2.0),
        ]
        let report = try #require(ReportBuilder.week(containing: shanghaiDate(2026, 9, 30, 12), cycles: cycles, journal: [], calendar: calendar))
        #expect(report.cycleCount == 3)
        #expect(abs((report.meanRecovery ?? 0) - 60) < 1e-9)
        #expect(report.bestRecoveryDay == shanghaiDate(2026, 9, 29, 7))
        #expect(report.worstRecoveryDay == shanghaiDate(2026, 9, 28, 7))
        #expect(abs((report.debtChangeHours ?? 0) - 1.0) < 1e-9)
    }

    @Test("身体年龄：各项都处于参考值时偏移为 0；VO2max 高 5 时偏移为 −3 年；缺项列出")
    func bodyAgeAnchors() {
        let reference = BodyAge.vo2Reference(age: 35, sex: .male)
        #expect(reference == 43)
        let neutral = BodyAgeInputs(vo2Max: reference, restingHeartRateBaseline: 60, lnRMSSDBaseline: 3.5, lnRMSSDPrior: 3.5, sri: 75, dailySteps: 8000, weeklyZone2PlusMinutes: 150)
        let zero = BodyAge.compute(chronologicalAge: 35, sex: .male, inputs: neutral)
        #expect(abs(zero.offsetYears) < 1e-9)
        #expect(zero.missing.isEmpty)

        var fitter = neutral
        fitter.vo2Max = reference + 5
        let better = BodyAge.compute(chronologicalAge: 35, sex: .male, inputs: fitter)
        #expect(abs(better.offsetYears + 3) < 1e-9)

        let partial = BodyAge.compute(chronologicalAge: 35, sex: .male, inputs: BodyAgeInputs(vo2Max: reference))
        #expect(partial.missing.contains("静息心率"))
        #expect(partial.missing.contains("日均步数"))
    }

    @Test("身体年龄偏移截断在 ±15 年")
    func bodyAgeClamped() {
        let extreme = BodyAgeInputs(vo2Max: 200, restingHeartRateBaseline: 60, lnRMSSDBaseline: 3.5, lnRMSSDPrior: 3.5, sri: 75, dailySteps: 8000, weeklyZone2PlusMinutes: 150)
        #expect(BodyAge.compute(chronologicalAge: 35, sex: .male, inputs: extreme).offsetYears == -15)
    }

    @Test("心肺适能：线性斜率与心率恢复的前后半段中位数变化")
    func fitnessTrend() throws {
        let start = shanghaiDate(2026, 7, 1, 0)
        let points = (0..<90).map { (start.addingTimeInterval(Double($0) * 86_400), 40 + 0.1 * Double($0)) }
        #expect(abs(try #require(CardioFitness.slopePerDay(points)) - 0.1) < 1e-9)
        let values = [20.0, 21, 22, 23, 30, 31, 32, 33]
        #expect(CardioFitness.recoveryChange(values) == 10)
    }
}
