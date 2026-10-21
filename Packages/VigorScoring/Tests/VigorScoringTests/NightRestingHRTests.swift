import Foundation
import Testing
@testable import VigorScoring

@Suite("NightRestingHR")
struct NightRestingHRTests {
    private let session = SleepSession(
        start: shanghaiDate(2026, 10, 21, 23),
        end: shanghaiDate(2026, 10, 22, 7),
        bedtime: nil,
        stages: [],
        asleepDuration: 8 * 3600,
        wakeDay: DateComponents(year: 2026, month: 10, day: 22),
        nightKey: DateComponents(year: 2026, month: 10, day: 21),
        kind: .main,
        timeZoneOffset: 8 * 3600,
        longAwakeGaps: []
    )

    private func points(_ values: [Double]) -> [HeartRateSample] {
        values.enumerated().map { index, bpm in
            HeartRateSample(date: session.start.addingTimeInterval(Double(index) * 300), bpm: bpm)
        }
    }

    @Test("样本 1…20 → 第 10 百分位 = 2.9（线性插值）")
    func p10OfOneToTwenty() throws {
        let result = NightRestingHR.compute(
            heartRate: points((1...20).map(Double.init)),
            session: session,
            seriesMeanHeartRates: [],
            appleRestingHeartRate: 55
        )
        #expect(result.source == .sampledP10)
        let p10 = try #require(result.value)
        #expect(abs(p10 - 2.9) < 1e-9)
        #expect(result.sampleCount == 20)
    }

    @Test("样本不足 10 个时退回 Apple 静息心率")
    func fallbackWhenTooFewSamples() {
        let result = NightRestingHR.compute(
            heartRate: points([50, 51, 52]),
            session: session,
            seriesMeanHeartRates: [],
            appleRestingHeartRate: 55
        )
        #expect(result.source == .appleFallback)
        #expect(result.value == 55)
    }

    @Test("有效序列的平均心率也进入样本池")
    func seriesMeansAddSamples() throws {
        let result = NightRestingHR.compute(
            heartRate: points([60, 61, 62, 63, 64, 65, 66, 67, 68]),
            session: session,
            seriesMeanHeartRates: [40],
            appleRestingHeartRate: nil
        )
        #expect(result.sampleCount == 10)
        #expect(result.source == .sampledP10)
    }

    @Test("最低心率出现时刻：位于夜间后段时位置接近 1")
    func lowestTimeLateInNight() throws {
        var values = [Double](repeating: 70, count: 90)
        for index in 80..<90 { values[index] = 50 }
        let result = NightRestingHR.compute(
            heartRate: points(values),
            session: session,
            seriesMeanHeartRates: [],
            appleRestingHeartRate: nil
        )
        let position = try #require(result.lowestTimePosition)
        #expect(position > 2.0 / 3.0)
    }
}
