import Foundation
import Testing
@testable import VigorScoring

@Suite("Recovery")
struct RecoveryTests {
    private func score(_ zHRV: Double?, _ zRHR: Double? = 0, _ zSleep: Double? = 0, penalties: RecoveryPenalties = RecoveryPenalties()) throws -> RecoveryResult {
        try #require(RecoveryScorer.score(RecoveryInputs(zHRV: zHRV, zRHR: zRHR, zSleep: zSleep, penalties: penalties)))
    }

    @Test("raw = 0 → Recovery = 100 / (1 + e^−0.35) ≈ 58.662")
    func anchorAtZero() throws {
        let result = try score(0)
        #expect(abs(result.uncappedScore - 58.662) < 0.001)
        #expect(abs(RecoveryScorer.baseline - 58.662) < 0.001)
    }

    @Test("只有 z_hrv = 1：Recovery ≈ 75.399，Shapley(HRV) ≈ 16.737，贡献之和 = Recovery − 58.662")
    func singleHRVAnchor() throws {
        let result = try score(1)
        #expect(abs(result.uncappedScore - 75.399) < 0.001)
        let hrv = try #require(result.contributions.first { $0.component == "HRV" })
        #expect(abs(hrv.points - 16.737) < 0.001)
        let total = result.contributions.reduce(0) { $0 + $1.points }
        #expect(abs(total - (result.uncappedScore - RecoveryScorer.baseline)) < 1e-9)
    }

    @Test("z_rhr 缺失：权重变为 0.7333 / 0.2667，z_hrv = 1，z_sleep = 0 → Recovery ≈ 79.85")
    func missingComponentReweights() throws {
        let result = try score(1, nil, 0)
        #expect(abs(try #require(result.weights["HRV"]) - 0.7333) < 0.0001)
        #expect(abs(try #require(result.weights["睡眠"]) - 0.2667) < 0.0001)
        #expect(abs(result.uncappedScore - 79.85) < 0.05)
    }

    @Test("没有 z_hrv 时不出分")
    func noHRVNoScore() {
        #expect(RecoveryScorer.score(RecoveryInputs(zHRV: nil, zRHR: 0, zSleep: 0)) == nil)
    }

    @Test("Shapley 属性测试：100 组随机输入，贡献之和 = Recovery − 58.662（±1e-9）")
    func shapleySumProperty() throws {
        var generator = TestRNG(seed: 7)
        for _ in 0..<100 {
            let penalties = RecoveryPenalties(
                respiratory: generator.uniform(0...0.6),
                temperature: generator.uniform(0...1.2),
                oxygen: generator.uniform(0...0.4),
                breathingDisturbance: generator.chance(0.5) ? 0.2 : 0
            )
            let inputs = RecoveryInputs(
                zHRV: generator.uniform(-3...3),
                zRHR: generator.chance(0.8) ? generator.uniform(-3...3) : nil,
                zSleep: generator.chance(0.8) ? generator.uniform(-3...3) : nil,
                penalties: penalties
            )
            let result = try #require(RecoveryScorer.score(inputs))
            let total = result.contributions.reduce(0) { $0 + $1.points }
            #expect(abs(total - (result.uncappedScore - RecoveryScorer.baseline)) < 1e-9)
        }
    }

    @Test("矛盾信号：z_hrv = 2.5、z_rhr = −1.5 → z_hrv 按 1 计算，并标记")
    func contradiction() throws {
        let result = try score(2.5, -1.5, 0)
        #expect(result.zHRV == 1)
        #expect(result.contradiction)
    }

    @Test("生病封顶：可能不适时 Recovery ≤ 33")
    func illnessCap() throws {
        let result = try #require(RecoveryScorer.score(RecoveryInputs(zHRV: 3, zRHR: 3, zSleep: 3, illnessPossible: true)))
        #expect(result.score <= 33)
        #expect(result.capped)
        #expect(result.uncappedScore > 33)
    }

    @Test("z 截断到 [−3, 3]")
    func zClipping() throws {
        // z_rhr = 0 不触发矛盾信号，因此 z_hrv 只受截断影响
        let result = try score(10, 0, 0)
        #expect(result.zHRV == 3)
        #expect(!result.contradiction)
    }

    @Test("扣分：Δt = 0.8 → 0.8；Δt = 1.5 → 1.2（封顶）")
    func temperaturePenalty() {
        #expect(abs(RecoveryPenalties.make(zResp: nil, temperatureDelta: 0.8, oxygenMedianPercent: nil, breathingElevated: false).temperature - 0.8) < 1e-9)
        #expect(RecoveryPenalties.make(zResp: nil, temperatureDelta: 1.5, oxygenMedianPercent: nil, breathingElevated: false).temperature == 1.2)
    }

    @Test("扣分：血氧中位数 93 → 0.2；90 → 0.4（封顶）")
    func oxygenPenalty() {
        #expect(abs(RecoveryPenalties.make(zResp: nil, temperatureDelta: nil, oxygenMedianPercent: 93, breathingElevated: false).oxygen - 0.2) < 1e-9)
        #expect(RecoveryPenalties.make(zResp: nil, temperatureDelta: nil, oxygenMedianPercent: 90, breathingElevated: false).oxygen == 0.4)
    }

    @Test("分区：绿 ≥ 67，黄 34–66，红 ≤ 33")
    func zones() {
        #expect(RecoveryScorer.zone(for: 67) == .green)
        #expect(RecoveryScorer.zone(for: 66.9) == .yellow)
        #expect(RecoveryScorer.zone(for: 34) == .yellow)
        #expect(RecoveryScorer.zone(for: 33) == .red)
    }
}

/// 测试用的确定性随机数（线性同余），与合成数据的 SplitMix64 无关。
struct TestRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / 9_007_199_254_740_992
    }

    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }
}
