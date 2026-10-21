import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("亮点规则（合成数据）")
struct HighlightsSyntheticTests {
    private static let endingAt = shanghaiDate(2026, 10, 1, 0)

    private func cycles(nights: Int = 120) -> [CycleResult] {
        let scenario = SyntheticScenario.make(nights: nights, seed: 42, endingAt: Self.endingAt, calendar: shanghaiCalendar())
        return ScoringPipeline.run(PipelineInput(
            snapshot: scenario.snapshot,
            journal: scenario.journal,
            now: Self.endingAt.addingTimeInterval(72 * 3600),
            calendar: shanghaiCalendar()
        )).cycles
    }

    @Test("规则至少 8 条，标识唯一，覆盖需要的类别")
    func ruleCatalog() {
        #expect(Highlights.ruleIDs.count >= 8)
        #expect(Set(Highlights.ruleIDs).count == Highlights.ruleIDs.count)
        for required in ["hrvTrend", "sleepDebt", "loadBalance", "regularity", "illness", "calibration", "dataQuality", "wear"] {
            #expect(Highlights.ruleIDs.contains(required))
        }
    }

    @Test("合成场景中触发的所有规则都在目录内；覆盖 5 个类别（数据质量与佩戴不完整在合成数据中不出现，见下面的单独测试）")
    func producedRulesAreCatalogued() {
        let all = cycles()
        var seen: Set<String> = []
        for end in 14...all.count {
            for highlight in Highlights.make(cycles: Array(all.prefix(end))) {
                #expect(Highlights.ruleIDs.contains(highlight.id))
                seen.insert(highlight.id)
            }
        }
        #expect(seen == ["hrvTrend", "illness", "loadBalance", "regularity", "sleepDebt"])
    }

    @Test("生病预警的那一晚：出现“身体信号需要留意”的提醒")
    func illnessHighlight() throws {
        let all = cycles()
        let sick = try #require(all.firstIndex { $0.illness == .possiblyUnwell && !$0.illnessConfounded })
        let highlights = Highlights.make(cycles: Array(all.prefix(sick + 1)))
        #expect(highlights.contains { $0.id == "illness" && $0.tone == .caution })
    }

    @Test("基线未满 14 晚时提示校准期；满 14 晚后不再提示")
    func calibrationHighlight() {
        let all = cycles()
        #expect(Highlights.make(cycles: Array(all.prefix(10))).contains { $0.id == "calibration" })
        #expect(!Highlights.make(cycles: Array(all.prefix(20))).contains { $0.id == "calibration" })
    }

    @Test("数据质量低：规则触发（用合成周期的副本验证，合成数据本身不会出现）")
    func dataQualityHighlight() throws {
        var today = try #require(cycles().last)
        today.quality = QualityReport(total: 0.2, level: .low, components: today.quality.components, reasons: [])
        #expect(Highlights.make(cycles: [today]).contains { $0.id == "dataQuality" && $0.tone == .caution })
    }

    @Test("佩戴不完整：规则触发（用合成周期的副本验证）")
    func wearHighlight() throws {
        var today = try #require(cycles().last)
        today.features.partialWear = true
        #expect(Highlights.make(cycles: [today]).contains { $0.id == "wear" && $0.tone == .caution })
    }
}
