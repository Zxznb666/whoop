import Foundation
import Testing
@testable import VigorScoring

@Suite("骑行专项指标")
struct CyclingMathTests {
    @Test("NP：恒定 200 W 持续 1 小时 → 200")
    func constantPowerNormalizedPower() throws {
        let power = [Double](repeating: 200, count: 3600)
        let np = try #require(CyclingMath.normalizedPower(power))
        #expect(abs(np - 200) < 1e-9)
    }

    @Test("NP：300 W 30 分钟后接 100 W 30 分钟 → 约 253.0（±2）")
    func variablePowerNormalizedPower() throws {
        let power = [Double](repeating: 300, count: 1800) + [Double](repeating: 100, count: 1800)
        let np = try #require(CyclingMath.normalizedPower(power))
        #expect(abs(np - 253.0) <= 2)
    }

    @Test("IF 与 TSS：NP 200、FTP 250、1 小时 → IF 0.8，TSS 64.0")
    func intensityAndTSS() {
        let intensity = CyclingMath.intensityFactor(normalizedPower: 200, ftp: 250)
        let tss = CyclingMath.tss(durationSeconds: 3600, normalizedPower: 200, ftp: 250)
        #expect(abs(intensity - 0.8) < 1e-9)
        #expect(abs(tss - 64.0) < 1e-9)
    }

    @Test("FTP 估算：最佳 20 分钟功率 280 → 266")
    func estimatedFTP() {
        #expect(abs(CyclingMath.estimatedFTP(bestTwentyMinutePower: 280) - 266) < 1e-9)
    }

    @Test("有氧解耦：前半段 NP 200 / 心率 140，后半段 NP 200 / 心率 147 → 4.76%（±0.01）")
    func aerobicDecouplingExample() {
        let first = CyclingMath.efficiencyFactor(normalizedPower: 200, averageHeartRate: 140)
        let second = CyclingMath.efficiencyFactor(normalizedPower: 200, averageHeartRate: 147)
        let decoupling = CyclingMath.aerobicDecoupling(firstHalfEF: first, secondHalfEF: second)
        #expect(abs(decoupling - 4.76) <= 0.01)
    }

    @Test("机械功：200 W 持续 1 小时 → 720 kJ")
    func mechanicalWork() {
        let work = CyclingMath.mechanicalWorkKJ([Double](repeating: 200, count: 3600))
        #expect(abs(work - 720) < 1e-9)
    }

    @Test("暂停按 0 填充，缺失值也按 0 计")
    func paddingUsesZeros() {
        let padded = CyclingMath.padded([100, nil, 300, 300], pauses: [2..<3], duration: 5)
        #expect(padded == [100, 0, 0, 300, 0])
    }

    @Test("功率区间：按相对 FTP 的百分比划分到 Z1…Z7")
    func zones() {
        // FTP 200：5% (Z1)，55% (Z2)，75% (Z2)，80% (Z3)，125% (Z6)，160% (Z7)
        let zones = CyclingMath.zoneSeconds([110, 150, 160, 250, 320, 10], ftp: 200)
        #expect(zones == [1, 2, 1, 0, 0, 1, 1])
    }

    @Test("功率曲线：最佳 5 秒与 60 秒")
    func powerCurve() {
        var power = [Double](repeating: 100, count: 120)
        power[10..<15] = [300, 300, 300, 300, 300]
        let curve = CyclingMath.powerCurve(power, durations: [5, 60, 300])
        #expect(curve[5] == 300)
        // 60 秒窗口必然包含 5 秒的 300 W：55 × 100 + 5 × 300 = 7000，除以 60
        #expect(abs((curve[60] ?? 0) - 7000.0 / 60) < 1e-9)
        #expect(curve[300] == nil)
    }

    @Test("PMC：从 0 开始，连续 42 天 TSS 恒为 100 → CTL ≈ 63.65（±0.02）")
    func pmcConvergesToExpectedValue() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(byAdding: .day, value: 41, to: start)!
        var tss: [Date: Double] = [:]
        for offset in 0..<42 {
            tss[calendar.date(byAdding: .day, value: offset, to: start)!] = 100
        }
        let series = PerformanceManagement.series(tssByDay: tss, from: start, through: end, calendar: calendar)
        let last = try #require(series.last)
        #expect(abs(last.ctl - 63.65) <= 0.02)
        #expect(series.first?.tsb == 0)
    }

    @Test("TSB 文案：−20 以下疲劳累积，−10 至 +5 训练适宜，+15 以上状态新鲜")
    func tsbStatusText() {
        #expect(PerformanceManagement.statusText(tsb: -25) == "疲劳累积")
        #expect(PerformanceManagement.statusText(tsb: 0) == "训练适宜")
        #expect(PerformanceManagement.statusText(tsb: 18) == "状态新鲜")
    }
}
