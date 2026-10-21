import Testing
@testable import VigorScoring

@Suite("压力（日间安静心率基线）")
struct StressTests {
    @Test("窗口平均心率等于日间基线 → 0；高出 10% → 1；高出 35% → 封顶为 3")
    func windowAnchors() {
        let baseline = 80.0
        #expect(Stress.windowStress(meanHeartRate: baseline, daytimeBaseline: baseline) == 0)
        #expect(abs(Stress.windowStress(meanHeartRate: baseline * 1.10, daytimeBaseline: baseline) - 1) < 1e-9)
        #expect(Stress.windowStress(meanHeartRate: baseline * 1.35, daytimeBaseline: baseline) == 3)
    }

    @Test("日间安静心率取 P20（线性插值）")
    func daytimeQuietHeartRateIsP20() {
        #expect(Stress.daytimeQuietHeartRate(windowMeans: [60, 70, 80, 90, 100]) == 68)
        #expect(Stress.daytimeQuietHeartRate(windowMeans: []) == nil)
    }

    @Test("有效天数不足 3 天：退回夜间静息心率 × 1.15")
    func fallbackWhenFewDays() {
        #expect(Stress.daytimeBaseline(priorDaytime: [], restingHeartRate: 50) == 50 * 1.15)
        #expect(Stress.daytimeBaseline(priorDaytime: [70, 75], restingHeartRate: 50) == 50 * 1.15)
    }

    @Test("有效天数达到 3 天：取中位数")
    func medianWhenEnoughDays() {
        #expect(Stress.daytimeBaseline(priorDaytime: [70, 90, 80], restingHeartRate: 50) == 80)
    }

    @Test("只取最近 14 个周期的日间安静心率")
    func onlyRecentCycles() {
        // 前 6 个很高，只有最近 14 个（全部是 70）参与中位数
        let history = Array(repeating: 120.0, count: 6) + Array(repeating: 70.0, count: 14)
        #expect(Stress.daytimeBaseline(priorDaytime: history, restingHeartRate: 50) == 70)
    }

    @Test("日间基线远高于夜间静息心率时，同样的心率不会被判为满格压力（D-047 的原因）")
    func dayBaselineAvoidsSaturation() {
        // 夜间静息 52，白天安静 78：窗口平均 80 的压力应接近 0，而不是 3
        let baseline = Stress.daytimeBaseline(priorDaytime: Array(repeating: 78.0, count: 5), restingHeartRate: 52)
        #expect(Stress.windowStress(meanHeartRate: 80, daytimeBaseline: baseline) < 0.5)
    }

    @Test("z_hrv < −1 时加 0.5，上限仍为 3")
    func hrvAdjustment() {
        #expect(Stress.daily(windowStresses: [2.8], zHRV: -1.2) == 3)
        #expect(Stress.daily(windowStresses: [1], zHRV: -1.2) == 1.5)
        #expect(Stress.daily(windowStresses: [1], zHRV: -0.5) == 1)
    }
}
