import Foundation
import Testing
@testable import VigorScoring

@Suite("IllnessWarning")
struct IllnessTests {
    @Test("注意条件：T 成立且 R、H、C 至少一个成立")
    func temperatureWithOneMore() {
        let signals = IllnessSignals(temperature: true, respiratory: false, hrv: false, restingHeartRate: true)
        #expect(IllnessWarning.meetsAttentionCondition(signals))
        let temperatureOnly = IllnessSignals(temperature: true, respiratory: false, hrv: false, restingHeartRate: false)
        #expect(!IllnessWarning.meetsAttentionCondition(temperatureOnly))
    }

    @Test("注意条件：T 不成立时，R、H、C 必须同时成立")
    func threeWithoutTemperature() {
        #expect(IllnessWarning.meetsAttentionCondition(IllnessSignals(temperature: false, respiratory: true, hrv: true, restingHeartRate: true)))
        #expect(!IllnessWarning.meetsAttentionCondition(IllnessSignals(temperature: false, respiratory: true, hrv: true, restingHeartRate: false)))
    }

    @Test("四个信号的阈值：Δt ≥ 0.5、z_resp ≥ 1.5、z_hrv ≤ −1.5、静息心率 ≥ μ + 2σ")
    func thresholds() {
        let baseline = BaselineStatistic(mu: 55, sigma: 2, count: 30)
        let on = IllnessWarning.signals(temperatureDelta: 0.5, zResp: 1.5, zHRV: -1.5, restingHeartRate: 59, restingBaseline: baseline)
        #expect(on == IllnessSignals(temperature: true, respiratory: true, hrv: true, restingHeartRate: true))
        let off = IllnessWarning.signals(temperatureDelta: 0.49, zResp: 1.49, zHRV: -1.49, restingHeartRate: 58.9, restingBaseline: baseline)
        #expect(off == IllnessSignals(temperature: false, respiratory: false, hrv: false, restingHeartRate: false))
    }
}
