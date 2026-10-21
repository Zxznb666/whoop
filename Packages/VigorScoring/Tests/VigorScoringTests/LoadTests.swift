import Foundation
import Testing
@testable import VigorScoring

@Suite("Load")
struct LoadTests {
    @Test("负荷映射：TRIMP 20 → 5.823；87 → 12.042；300 → 18.200；600 → 21（封顶）")
    func strainAnchors() {
        #expect(abs(Strain.strain(fromTRIMP: 20) - 5.823) < 0.001)
        #expect(abs(Strain.strain(fromTRIMP: 87) - 12.042) < 0.001)
        #expect(abs(Strain.strain(fromTRIMP: 300) - 18.200) < 0.001)
        #expect(Strain.strain(fromTRIMP: 600) == 21)
    }

    @Test("每分钟 TRIMP：男，x = 0.5 → 0.83574；女，x = 0.5 → 0.99109；x = 0.2 → 0")
    func trimpPerMinute() {
        #expect(abs(Strain.trimpPerMinute(hrr: 0.5, sex: .male) - 0.83574) < 1e-4)
        #expect(abs(Strain.trimpPerMinute(hrr: 0.5, sex: .female) - 0.99109) < 1e-4)
        #expect(Strain.trimpPerMinute(hrr: 0.2, sex: .male) == 0)
    }

    @Test("目标区间：绿 → 14–18；ACWR = 1.4 时 → 12–16；黄 10–14；红 0–10")
    func targets() {
        #expect(LoadTargets.target(zone: .green, acwr: nil) == LoadTarget(lower: 14, upper: 18))
        #expect(LoadTargets.target(zone: .green, acwr: 1.4) == LoadTarget(lower: 12, upper: 16))
        #expect(LoadTargets.target(zone: .yellow, acwr: nil) == LoadTarget(lower: 10, upper: 14))
        #expect(LoadTargets.target(zone: .red, acwr: nil) == LoadTarget(lower: 0, upper: 10))
        #expect(LoadTargets.target(zone: .red, acwr: 1.3) == LoadTarget(lower: 0, upper: 10))
    }

    @Test("ACWR：最近 7 天平均 ÷ 最近 28 天平均；历史不足 7 天时为 nil")
    func acwr() throws {
        #expect(LoadTargets.acwr(recentTRIMP: [10, 10, 10]) == nil)
        let flat = [Double](repeating: 10, count: 28)
        #expect(abs(try #require(LoadTargets.acwr(recentTRIMP: flat)) - 1) < 1e-9)
        // 前 21 天 10，最近 7 天 20：(20) / ((21·10 + 7·20) / 28) = 20 / 12.5 = 1.6
        let spike = [Double](repeating: 10, count: 21) + [Double](repeating: 20, count: 7)
        #expect(abs(try #require(LoadTargets.acwr(recentTRIMP: spike)) - 1.6) < 1e-9)
    }

    @Test("插值：相隔 10 分钟的两个心率点 → 中间线性插值；相隔 20 分钟 → 中间不插值（空窗规则）")
    func interpolationRules() throws {
        let origin = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            HeartRateSample(date: origin, bpm: 60),
            HeartRateSample(date: origin.addingTimeInterval(10 * 60), bpm: 80),
            HeartRateSample(date: origin.addingTimeInterval(30 * 60), bpm: 90),
        ]
        // 网格需要包含第 30 分钟的测量点，否则它会被忽略
        let grid = MinuteGrid.build(
            origin: origin,
            end: origin.addingTimeInterval(31 * 60),
            heartRate: samples,
            activeEnergy: [],
            steps: []
        )
        let line = LoadCalculator.timeline(grid: grid, from: 0, to: 30, restingHeartRate: 55, maxHeartRate: 190, model: nil)

        let middle = line[5]
        #expect(middle.source == .interpolated)
        #expect(abs(try #require(middle.bpm) - 70) < 1e-9)

        // 第 15 分钟位于 10 分钟与 30 分钟两个点之间（间隔 20 分钟），不插值，按静息处理
        let gap = line[15]
        #expect(gap.source == .resting)
        #expect(gap.bpm == 55)
    }

    @Test("未佩戴：超过 60 分钟没有心率的空窗不计入负荷")
    func unwornGap() {
        let origin = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            HeartRateSample(date: origin, bpm: 70),
            HeartRateSample(date: origin.addingTimeInterval(120 * 60), bpm: 70),
        ]
        let grid = MinuteGrid.build(origin: origin, end: origin.addingTimeInterval(120 * 60), heartRate: samples, activeEnergy: [], steps: [])
        let line = LoadCalculator.timeline(grid: grid, from: 0, to: 120, restingHeartRate: 55, maxHeartRate: 190, model: nil)
        #expect(line[60].source == .unworn)
    }

    @Test("空窗回归：样本不足 500 个时不启用")
    func regressionNeedsSamples() {
        // 完美的线性数据：y = 60 + 10x，x 取 0…1
        let x = (0..<499).map { Double($0) / 498 }
        let y = x.map { 60 + 10 * $0 }
        let model = ActivityModel.fit(
            count: Double(x.count),
            sumX: x.reduce(0, +),
            sumY: y.reduce(0, +),
            sumXY: zip(x, y).reduce(0) { $0 + $1.0 * $1.1 },
            sumXX: x.reduce(0) { $0 + $1 * $1 },
            sumYY: y.reduce(0) { $0 + $1 * $1 }
        )
        #expect(model == nil)
    }

    @Test("空窗回归：样本 ≥ 500 且 R² ≥ 0.3 时启用，并恢复斜率")
    func regressionEnabled() throws {
        let x = (0..<600).map { Double($0 % 50) / 50 }
        let y = x.map { 60 + 10 * $0 }
        let model = try #require(ActivityModel.fit(
            count: Double(x.count),
            sumX: x.reduce(0, +),
            sumY: y.reduce(0, +),
            sumXY: zip(x, y).reduce(0) { $0 + $1.0 * $1.1 },
            sumXX: x.reduce(0) { $0 + $1 * $1 },
            sumYY: y.reduce(0) { $0 + $1 * $1 }
        ))
        #expect(abs(model.slope - 10) < 1e-6)
        #expect(abs(model.rSquared - 1) < 1e-9)
    }

    @Test("最大心率：运动中 30 秒均值达到 195，而公式值为 185 → HRmax 更新为 195")
    func maxHeartRateUpdates() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let effort = (0..<30).map { HeartRateSample(date: start.addingTimeInterval(Double($0)), bpm: 195) }
        let peak = try #require(MaxHeartRate.observedPeak(workoutHeartRate: effort))
        #expect(peak == 195)
        #expect(MaxHeartRate.effective(initial: 185, observedPeak: peak) == 195)
        #expect(MaxHeartRate.effective(initial: 185, observedPeak: 180) == 185)
    }

    @Test("压力：elev = 0.10 → 1；elev ≥ 0.30 封顶为 3；z_hrv < −1 时加 0.5")
    func stressRules() {
        #expect(abs(Stress.windowStress(meanHeartRate: 66, daytimeBaseline: 60) - 1) < 1e-9)
        #expect(Stress.windowStress(meanHeartRate: 90, daytimeBaseline: 60) == 3)
        #expect(Stress.daily(windowStresses: [1, 1], zHRV: -1.5) == 1.5)
        #expect(Stress.daily(windowStresses: [], zHRV: 0) == nil)
    }
}
