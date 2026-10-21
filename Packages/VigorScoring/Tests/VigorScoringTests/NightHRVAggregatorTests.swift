import Foundation
import Testing
@testable import VigorScoring

@Suite("NightHRVAggregator")
struct NightHRVAggregatorTests {
    /// 睡眠 22:00–次日 06:00，共 8 小时；2/3 点为 03:20。
    private let session = SleepSession(
        start: shanghaiDate(2026, 10, 20, 22),
        end: shanghaiDate(2026, 10, 21, 6),
        stages: [],
        asleepDuration: 8 * 3600,
        wakeDay: DateComponents(year: 2026, month: 10, day: 21),
        isMain: true
    )

    private func segment(start: Date, minutes: Double = 5, rmssd: Double?, isValid: Bool = true) -> SegmentResult {
        SegmentResult(
            seriesID: UUID(),
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            candidateRR: 60,
            acceptedRR: 60,
            rejectedRR: 0,
            rmssd: rmssd,
            isValid: isValid,
            invalidReason: isValid ? nil : "有效 RR 不足",
            acceptedRRms: [],
            acceptedRRTimes: []
        )
    }

    @Test("两个有效夜间片段 RMSSD 为 20 和 40 时，几何加权均值为 √800")
    func overnightGeometricMean() throws {
        let segments = [
            segment(start: shanghaiDate(2026, 10, 21, 1), rmssd: 20),
            segment(start: shanghaiDate(2026, 10, 21, 2), rmssd: 40),
        ]
        let hrv = NightHRVAggregator.aggregate(session: session, segments: segments, sdnn: [], config: .default)
        #expect(hrv.method == .overnight)
        #expect(hrv.validOvernightCount == 2)
        #expect(hrv.quality == .medium)
        let rmssd = try #require(hrv.rmssd)
        #expect(abs(rmssd - 800.0.squareRoot()) < 1e-6)
    }

    @Test("有效夜间片段不少于 4 个时质量为高")
    func fourOvernightSegmentsAreHighQuality() {
        let segments = (1...4).map { hour in
            segment(start: shanghaiDate(2026, 10, 21, hour), rmssd: 30)
        }
        let hrv = NightHRVAggregator.aggregate(session: session, segments: segments, sdnn: [], config: .default)
        #expect(hrv.quality == .high)
    }

    @Test("同时有夜间片段和有效晨测片段时，优先使用晨测")
    func morningTakesPriority() throws {
        let segments = [
            segment(start: shanghaiDate(2026, 10, 21, 1), rmssd: 30),
            segment(start: shanghaiDate(2026, 10, 21, 6, 20), rmssd: 50),
        ]
        let hrv = NightHRVAggregator.aggregate(session: session, segments: segments, sdnn: [], config: .default)
        #expect(hrv.method == .morning)
        #expect(hrv.quality == .high)
        #expect(hrv.morningSegments.count == 1)
        let rmssd = try #require(hrv.rmssd)
        #expect(abs(rmssd - 50) < 1e-6)
    }

    @Test("没有片段只有 SDNN 时使用 SDNN 兜底，RMSSD 为 nil")
    func sdnnFallback() throws {
        let sdnn = [
            ValueSample(start: shanghaiDate(2026, 10, 21, 2), end: shanghaiDate(2026, 10, 21, 2, 1), value: 45),
            ValueSample(start: shanghaiDate(2026, 10, 21, 4), end: shanghaiDate(2026, 10, 21, 4, 1), value: 55),
        ]
        let hrv = NightHRVAggregator.aggregate(session: session, segments: [], sdnn: sdnn, config: .default)
        #expect(hrv.method == .sdnnFallback)
        #expect(hrv.rmssd == nil)
        #expect(hrv.quality == .low)
        let sdnnMean = try #require(hrv.sdnnMean)
        #expect(abs(sdnnMean - 50) < 1e-6)
    }

    @Test("没有任何数据时方法为 none，质量为 none")
    func noData() {
        let hrv = NightHRVAggregator.aggregate(session: session, segments: [], sdnn: [], config: .default)
        #expect(hrv.method == .none)
        #expect(hrv.quality == .none)
        #expect(hrv.rmssd == nil)
    }
}
