import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("SyntheticSnapshot")
struct SyntheticSnapshotTests {
    @Test("相同种子生成的快照完全相等")
    func sameSeedIsReproducible() {
        #expect(defaultSyntheticSnapshot(seed: 42) == defaultSyntheticSnapshot(seed: 42))
    }

    @Test("不同种子生成的快照不相等")
    func differentSeedDiffers() {
        #expect(defaultSyntheticSnapshot(seed: 42) != defaultSyntheticSnapshot(seed: 7))
    }

    @Test("夜晚结构：30 晚各一段主睡眠，无心跳序列的夜晚为 3 晚")
    func nightStructure() {
        let snapshot = defaultSyntheticSnapshot()
        let reports = NightAnalyzer.analyze(snapshot, calendar: shanghaiCalendar())
        #expect(reports.count == 30)

        let withoutSeries = reports.filter { $0.hrv.overnightSegments.isEmpty && $0.hrv.morningSegments.isEmpty }
        #expect(withoutSeries.count == 3)
        #expect(snapshot.sleep.filter { $0.sourceIsWatch }.count > 0)
    }

    @Test("用合成快照跑 NightAnalyzer：27 晚有 RMSSD、3 晚走 SDNN 兜底，RMSSD 落在 15–120 ms")
    func analysisOnSyntheticData() {
        let reports = NightAnalyzer.analyze(defaultSyntheticSnapshot(), calendar: shanghaiCalendar())
        let summary = AvailabilitySummary.make(reports)

        #expect(summary.nights == 30)
        #expect(summary.nightsWithRMSSD == 27)
        #expect(reports.filter { $0.hrv.method == .sdnnFallback }.count == 3)

        for report in reports {
            if let rmssd = report.hrv.rmssd {
                #expect(rmssd >= 15 && rmssd <= 120)
            }
        }
    }
}
