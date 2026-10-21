import Foundation
import Testing
@testable import VigorScoring

@Suite("NightHRVAggregator")
struct NightHRVAggregatorTests {
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

    /// 中点落在夜间、可直接采用的段。
    private func window(
        rmssd: Double,
        position: Double = 0.5,
        stage: SleepStage = .core,
        accepted: Int = 60,
        rejectRate: Double = 0,
        isValid: Bool = true
    ) -> HRVWindow {
        let middle = session.start.addingTimeInterval(position * 8 * 3600)
        return HRVWindow(
            seriesID: UUID(),
            start: middle.addingTimeInterval(-30),
            end: middle.addingTimeInterval(30),
            stage: stage,
            position: position,
            candidateCount: accepted,
            acceptedCount: accepted,
            rejectedCount: 0,
            rejectRate: rejectRate,
            rmssd: rmssd,
            meanHeartRate: 60,
            sdnn: nil,
            durationSeconds: 60,
            acceptedRR: [],
            acceptedBeatTimes: [],
            rejectedBeatTimes: [],
            invalidReason: isValid ? nil : "测试无效段"
        )
    }

    @Test("两段：权重相同，RMSSD 为 20 和 40 → exp(mean(ln)) = √800 ≈ 28.2843")
    func twoSegments() throws {
        var overnight = [window(rmssd: 20), window(rmssd: 40)]
        var morning: [HRVWindow] = []
        let hrv = NightHRVAggregator.aggregate(session: session, overnight: &overnight, morning: &morning, sdnn: [])
        #expect(hrv.nightValidCount == 2)
        let rmssd = try #require(hrv.nightRMSSD)
        #expect(abs(rmssd - 800.0.squareRoot()) < 1e-9)
        let adopted = overnight.map(\.adopted)
        #expect(adopted == [true, true])
    }

    @Test("三段及以上：取加权中位数（RMSSD 20、30、40 权重相同 → 30）")
    func threeSegmentsWeightedMedian() throws {
        var overnight = [window(rmssd: 20), window(rmssd: 30), window(rmssd: 40)]
        var morning: [HRVWindow] = []
        let hrv = NightHRVAggregator.aggregate(session: session, overnight: &overnight, morning: &morning, sdnn: [])
        let rmssd = try #require(hrv.nightRMSSD)
        #expect(abs(rmssd - 30) < 1e-9)
        #expect(hrv.dispersion != nil)
    }

    @Test("一段：直接采用，不做合成")
    func singleSegment() {
        var overnight = [window(rmssd: 33)]
        var morning: [HRVWindow] = []
        let hrv = NightHRVAggregator.aggregate(session: session, overnight: &overnight, morning: &morning, sdnn: [])
        #expect(hrv.nightRMSSD == 33)
        #expect(hrv.dispersion == nil)
    }

    @Test("权重 w = q × p × s：深睡 × 后 1/3 夜 = 1.3 × 1.5；质量 q = 30/60 × 1 = 0.5 → w = 0.5 × 1.5 × 1.3")
    func weightComposition() {
        var overnight = [
            window(rmssd: 30, position: 0.9, stage: .deep),
            window(rmssd: 30, position: 0.5, stage: .core, accepted: 30),
        ]
        var morning: [HRVWindow] = []
        _ = NightHRVAggregator.aggregate(session: session, overnight: &overnight, morning: &morning, sdnn: [])
        #expect(abs(overnight[0].weight - 1.95) < 1e-9)
        #expect(abs(overnight[1].weight - 0.5) < 1e-9)
    }

    @Test("清醒中的段直接丢弃（权重为 0，不计入有效段）")
    func awakeSegmentDropped() {
        var overnight = [window(rmssd: 20, stage: .awake), window(rmssd: 40)]
        var morning: [HRVWindow] = []
        let hrv = NightHRVAggregator.aggregate(session: session, overnight: &overnight, morning: &morning, sdnn: [])
        #expect(hrv.nightValidCount == 1)
        #expect(hrv.nightRMSSD == 40)
    }

    @Test("无效段不参与合成；没有任何 HRV 时退回 SDNN 兜底")
    func fallbackToSDNN() {
        var overnight = [window(rmssd: 20, isValid: false)]
        var morning: [HRVWindow] = []
        let sdnn = [ValueSample(start: session.start.addingTimeInterval(600), end: session.start.addingTimeInterval(660), value: 42)]
        let hrv = NightHRVAggregator.aggregate(session: session, overnight: &overnight, morning: &morning, sdnn: sdnn)
        #expect(hrv.nightRMSSD == nil)
        #expect(hrv.method == .sdnnFallback)
        #expect(hrv.sdnnMean == 42)
    }

    @Test("晨测：醒后 20 分钟开始、与正念记录重叠 → 归入晨测；不重叠 → 忽略")
    func morningIdentification() {
        let wake = session.end
        let morningSeries = HRVWindow(
            seriesID: UUID(), start: wake.addingTimeInterval(1200), end: wake.addingTimeInterval(1260),
            candidateCount: 60, acceptedCount: 60, rejectedCount: 0, rejectRate: 0, rmssd: 25, meanHeartRate: 60,
            sdnn: nil, durationSeconds: 60, acceptedRR: [], acceptedBeatTimes: [], rejectedBeatTimes: [], invalidReason: nil
        )
        let mindful = [ValueSample(start: wake.addingTimeInterval(1210), end: wake.addingTimeInterval(1330), value: 1)]

        let matched = NightHRVAggregator.classify(session: session, analyzed: [morningSeries], mindfulSessions: mindful)
        #expect(matched.morning.count == 1)
        #expect(matched.morning[0].isMorning)
        #expect(matched.overnight.isEmpty)

        let unmatched = NightHRVAggregator.classify(session: session, analyzed: [morningSeries], mindfulSessions: [])
        #expect(unmatched.morning.isEmpty)
        #expect(unmatched.overnight.isEmpty)
    }

    @Test("晨测与夜间分别输出；展示值优先取夜间")
    func modesAreSeparate() {
        var overnight = [window(rmssd: 30)]
        var morning = [
            HRVWindow(
                seriesID: UUID(), start: session.end, end: session.end.addingTimeInterval(60),
                isMorning: true, candidateCount: 60, acceptedCount: 60, rejectedCount: 0, rejectRate: 0,
                rmssd: 50, meanHeartRate: 60, sdnn: nil, durationSeconds: 60, acceptedRR: [],
                acceptedBeatTimes: [], rejectedBeatTimes: [], invalidReason: nil
            ),
        ]
        let hrv = NightHRVAggregator.aggregate(session: session, overnight: &overnight, morning: &morning, sdnn: [])
        #expect(hrv.nightRMSSD == 30)
        #expect(hrv.morningRMSSD == 50)
        #expect(hrv.displayRMSSD == 30)
        #expect(hrv.method == .overnight)
    }
}
