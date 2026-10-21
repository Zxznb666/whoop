import Foundation
import Testing
@testable import VigorScoring

@Suite("Baseline")
struct BaselineTests {
    @Test("冷启动：n = 0 → μ = 先验；n = 7 → μ = (先验 + 个人) / 2")
    func coldStartShrinkage() throws {
        let prior = (mu: Double?.some(50), sigma: 5.0)
        let none = Baseline.statistic(values: [], prior: prior, sigmaFloor: 1.5)
        #expect(none.mu == 50)
        #expect(none.count == 0)
        #expect(none.isCalibrating)

        // 个人 7 晚的中位数为 60
        let seven = Baseline.statistic(values: [58, 59, 60, 61, 62, 60, 60], prior: prior, sigmaFloor: 1.5)
        let mu = try #require(seven.mu)
        #expect(abs(mu - 55) < 1e-9)
        #expect(seven.count == 7)
    }

    @Test("σ 下限：30 晚 ln RMSSD 完全相同 → σ = 0.06")
    func sigmaFloorApplies() {
        let values = [Double](repeating: log(40), count: 30)
        let statistic = Baseline.statistic(
            values: values,
            prior: (mu: log(36), sigma: 0.30),
            sigmaFloor: Baseline.sigmaFloor(for: .lnRMSSDNight)
        )
        #expect(statistic.sigma == 0.06)
        #expect(!statistic.isCalibrating)
    }

    @Test("窗口只取最近 30 个有效夜晚")
    func windowIsLastThirty() {
        let values = (1...40).map(Double.init)
        let statistic = Baseline.statistic(values: values, prior: (mu: nil, sigma: 1), sigmaFloor: 0)
        // 最近 30 个为 11…40，中位数 25.5
        #expect(statistic.mu == 25.5)
        #expect(statistic.count == 30)
    }

    @Test("不用未来数据：改变第 N 晚的值，第 N 晚的基线不变，之后的基线才会变化")
    func noFutureData() throws {
        // 第 n 晚的静息心率为 50 + n；第 20 晚改为 v
        func observations(valueAt index: Int, _ value: Double) -> [BaselineObservation] {
            (0..<40).map { night in
                BaselineObservation(
                    values: [.restingHeartRate: night == index ? value : 50 + Double(night)],
                    isValid: true
                )
            }
        }
        let profile = UserProfile(birthYear: nil, sex: .male)
        let before = BaselineHistory.statistic(
            for: .restingHeartRate, before: 20, in: observations(valueAt: 20, 70),
            profile: profile, year: 2026
        )
        let after = BaselineHistory.statistic(
            for: .restingHeartRate, before: 20, in: observations(valueAt: 20, 0),
            profile: profile, year: 2026
        )
        #expect(before == after)

        // 第 21 晚的基线包含第 20 晚：把它改成很小的值，中位数由 60 变为 59
        let nextBefore = BaselineHistory.statistic(
            for: .restingHeartRate, before: 21, in: observations(valueAt: 20, 70),
            profile: profile, year: 2026
        )
        let nextAfter = BaselineHistory.statistic(
            for: .restingHeartRate, before: 21, in: observations(valueAt: 20, 0),
            profile: profile, year: 2026
        )
        #expect(nextBefore.mu != nextAfter.mu)
    }

    @Test("无效夜晚不进入基线")
    func invalidNightsExcluded() {
        let observations = [
            BaselineObservation(values: [.respiratoryRate: 100], isValid: false),
            BaselineObservation(values: [.respiratoryRate: 14], isValid: true),
        ]
        let values = BaselineHistory.values(for: .respiratoryRate, before: 2, in: observations)
        #expect(values == [14])
    }

    @Test("人群先验：年龄段与性别")
    func priors() {
        #expect(PopulationPriors.ageGroup(birthYear: 2000, year: 2026) == 0)
        #expect(PopulationPriors.ageGroup(birthYear: 1990, year: 2026) == 1)
        #expect(PopulationPriors.ageGroup(birthYear: nil, year: 2026) == 1)
        let female = PopulationPriors.prior(for: .restingHeartRate, profile: UserProfile(birthYear: nil, sex: .female), year: 2026)
        #expect(female.mu == 58)
        let temperature = PopulationPriors.prior(for: .wristTemperature, profile: UserProfile(birthYear: nil, sex: .male), year: 2026)
        #expect(temperature.mu == nil)
    }
}
