import Foundation
import Testing
@testable import VigorScoring

@Suite("NightRestingHR")
struct NightRestingHRTests {
    private let session = SleepSession(
        start: shanghaiDate(2026, 10, 20, 22),
        end: shanghaiDate(2026, 10, 21, 6),
        stages: [],
        asleepDuration: 8 * 3600,
        wakeDay: DateComponents(year: 2026, month: 10, day: 21),
        isMain: true
    )

    @Test("样本少于 10 个时返回 nil")
    func tooFewSamples() {
        let base = shanghaiDate(2026, 10, 21, 1)
        let samples = (0..<9).map { HeartRateSample(date: base.addingTimeInterval(Double($0) * 60), bpm: 50) }
        #expect(NightRestingHR.compute(heartRate: samples, session: session) == nil)
    }

    @Test("5 分钟滑动均值的最低值为 48")
    func lowestFiveMinuteMean() throws {
        // 每分钟一个样本；第 3–8 个为 48，其余为 60。
        // 从第 3 个样本起的 5 分钟窗口恰好包含 6 个 48，均值为 48。
        let base = shanghaiDate(2026, 10, 21, 1)
        let samples = (0..<12).map { index -> HeartRateSample in
            let bpm: Double = (3...8).contains(index) ? 48 : 60
            return HeartRateSample(date: base.addingTimeInterval(Double(index) * 60), bpm: bpm)
        }
        let result = try #require(NightRestingHR.compute(heartRate: samples, session: session))
        #expect(abs(result - 48) < 1e-9)
    }
}
