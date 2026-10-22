import Testing
@testable import VigorScoring

@Suite("骑行双轴曲线的刻度换算（M6 补完 C2）")
struct RideChartScaleTests {
    @Test("心率 140 在 100…180、功率上限 400 的刻度上位于 200，并能换算回来")
    func mappingRoundTrip() {
        let y = RideChartScale.mappedHeartRate(140, low: 100, high: 180, top: 400)
        #expect(y == 200)
        #expect(RideChartScale.heartRate(mapped: y, low: 100, high: 180, top: 400) == 140)
    }

    @Test("功率上限：max(最大功率 × 1.1, FTP × 1.5) 向上取整到 50 W")
    func powerTop() {
        #expect(RideChartScale.powerTop(maxPower: 300, ftp: 250) == 400) // 375 → 400
        #expect(RideChartScale.powerTop(maxPower: 600, ftp: 200) == 700) // 660 → 700
        #expect(RideChartScale.powerTop(maxPower: 0, ftp: nil) == 50)
    }

    @Test("右轴刻度只保留落在心率范围内的值")
    func heartRateTicks() {
        #expect(RideChartScale.heartRateTicks(low: 100, high: 180) == [100, 120, 140, 160, 180])
        #expect(RideChartScale.heartRateTicks(low: 130, high: 170) == [140, 160])
    }
}
