import Foundation
import Testing
@testable import VigorScoring

@Suite("NightAnalyzer")
struct NightAnalyzerTests {
    private let calendar = shanghaiCalendar()

    private func sample(_ start: Date, _ end: Date) -> SleepStageSample {
        SleepStageSample(start: start, end: end, stage: .core, sourceIsWatch: true)
    }

    private func snapshot(sleep: [SleepStageSample]) -> HealthSnapshot {
        HealthSnapshot(
            schemaVersion: 1,
            exportedAt: shanghaiDate(2026, 10, 22, 8),
            rangeStart: shanghaiDate(2026, 10, 20, 0),
            rangeEnd: shanghaiDate(2026, 10, 22, 8),
            profile: UserProfile(birthYear: nil, sex: .unknown),
            sleep: sleep,
            heartRate: [],
            hrvSDNN: [],
            restingHeartRate: [],
            respiratoryRate: [],
            wristTemperature: [],
            oxygenSaturation: [],
            heartbeatSeries: []
        )
    }

    @Test("只为主睡眠生成报告，且按时间倒序返回")
    func onlyMainSessionsAreReported() throws {
        let night1 = sample(shanghaiDate(2026, 10, 20, 23), shanghaiDate(2026, 10, 21, 7))
        let nap = sample(shanghaiDate(2026, 10, 21, 14), shanghaiDate(2026, 10, 21, 14, 30))
        let night2 = sample(shanghaiDate(2026, 10, 21, 23), shanghaiDate(2026, 10, 22, 6))
        let reports = NightAnalyzer.analyze(snapshot(sleep: [night1, nap, night2]), calendar: calendar)
        #expect(reports.count == 2)
        let newest = try #require(reports.first)
        let oldest = try #require(reports.last)
        #expect(newest.session.end == shanghaiDate(2026, 10, 22, 6))
        #expect(oldest.session.end == shanghaiDate(2026, 10, 21, 7))
    }

    @Test("汇总：夜数、有 RMSSD 的夜数、平均有效片段数、中位数与质量分布")
    func summary() {
        func report(rmssd: Double?, quality: DataQuality, valid: Int) -> NightReport {
            let session = SleepSession(
                start: shanghaiDate(2026, 10, 20, 23),
                end: shanghaiDate(2026, 10, 21, 7),
                stages: [],
                asleepDuration: 8 * 3600,
                wakeDay: DateComponents(year: 2026, month: 10, day: 21),
                isMain: true
            )
            let hrv = NightHRV(
                rmssd: rmssd,
                method: rmssd == nil ? .none : .overnight,
                overnightSegments: [],
                morningSegments: [],
                validOvernightCount: valid,
                sdnnMean: nil,
                quality: quality
            )
            return NightReport(
                session: session,
                hrv: hrv,
                nightRHR: nil,
                appleRHR: nil,
                respiratoryRate: nil,
                wristTemperature: nil,
                spo2Mean: nil,
                heartRateCount: 0
            )
        }
        let summary = AvailabilitySummary.make([
            report(rmssd: 20, quality: .high, valid: 4),
            report(rmssd: 40, quality: .medium, valid: 2),
            report(rmssd: nil, quality: .none, valid: 0),
        ])
        #expect(summary.nights == 3)
        #expect(summary.nightsWithRMSSD == 2)
        #expect(summary.meanValidSegmentsPerNight == 2)
        #expect(summary.medianRMSSD == 30)
        #expect(summary.qualityCounts == [.high: 1, .medium: 1, .low: 0, .none: 1])
    }
}
