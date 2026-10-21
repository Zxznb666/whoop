import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("实验室：版本对比、消融、校准样本与导出（合成数据）")
struct LabAnalysisSyntheticTests {
    private static let endingAt = shanghaiDate(2026, 10, 1, 0)

    private func output(_ config: ScoringConfig = .default) -> PipelineOutput {
        let scenario = SyntheticScenario.make(nights: 60, seed: 42, endingAt: Self.endingAt, calendar: shanghaiCalendar())
        return ScoringPipeline.run(PipelineInput(
            snapshot: scenario.snapshot,
            journal: scenario.journal,
            config: config,
            now: Self.endingAt.addingTimeInterval(72 * 3600),
            calendar: shanghaiCalendar()
        ))
    }

    @Test("同一配置重算：逐日变化全部为 0，没有明显变化")
    func identicalRunHasNoChange() {
        let cycles = output().cycles
        let comparison = LabAnalysis.compare(before: cycles, after: cycles)
        #expect(comparison.changes.count == cycles.count)
        #expect(comparison.meanAbsoluteChange == 0)
        #expect(comparison.notableCount == 0)
    }

    @Test("改变晚段权重后：有周期的恢复分数发生变化，对比结果可读")
    func changedConfigMovesScores() throws {
        var changed = ScoringConfig.default
        changed.configVersion = 2
        changed.lateNightWeight = 0.5
        let comparison = LabAnalysis.compare(before: output().cycles, after: output(changed).cycles)
        #expect(!comparison.changes.isEmpty)
        #expect((comparison.meanAbsoluteChange ?? 0) > 0)
        let maximum = try #require(comparison.maximumAbsoluteChange)
        let mean = try #require(comparison.meanAbsoluteChange)
        #expect(maximum >= mean)
    }

    @Test("消融：去掉静息心率或睡眠都能得到分布；与原分数的差值有方向")
    func ablationProducesDistributions() {
        let cycles = output().cycles
        for component in LabAnalysis.Component.allCases {
            let ablation = LabAnalysis.ablation(cycles: cycles, removing: component)
            #expect(ablation.count > 0)
            #expect(ablation.meanShift != nil)
            if let ablatedMean = ablation.ablatedMean, let actualMean = ablation.actualMean, let shift = ablation.meanShift {
                #expect(abs(shift - (ablatedMean - actualMean)) < 1e-9)
            }
        }
    }

    @Test("消融的基准：不去掉任何分量时，直接调用评分器得到的分数与周期记录一致")
    func ablationBaselineMatchesScorer() throws {
        let cycle = try #require(output().cycles.last)
        let recovery = try #require(cycle.recovery)
        let inputs = RecoveryInputs(
            zHRV: recovery.zHRV,
            zRHR: recovery.zRHR,
            zSleep: recovery.zSleep,
            penalties: recovery.penalties,
            illnessPossible: cycle.illness == .possiblyUnwell
        )
        #expect(RecoveryScorer.score(inputs)?.score == recovery.score)
    }

    @Test("校准样本：每个有精力记录的醒来日一条，特征为三个 z-score，精力在 1–5 之间")
    func calibrationSamples() {
        let scenario = SyntheticScenario.make(nights: 60, seed: 42, endingAt: Self.endingAt, calendar: shanghaiCalendar())
        let cycles = output().cycles
        let samples = LabAnalysis.calibrationSamples(cycles: cycles, journal: scenario.journal, calendar: shanghaiCalendar())
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.features.count == LabAnalysis.calibrationWeights.count })
        #expect(samples.allSatisfy { (1...5).contains($0.energy) })
        #expect(samples.count <= cycles.count)
    }

    @Test("CSV：表头列数与每一行一致，行数 = 周期数 + 1；JSON 可以解回周期数")
    func csvAndJSONExport() throws {
        let cycles = output().cycles
        let csv = DailyExport.csv(cycles: cycles, calendar: shanghaiCalendar())
        let lines = csv.split(separator: "\n")
        let columns = DailyExport.csvHeader.split(separator: ",").count
        #expect(lines.count == cycles.count + 1)
        #expect(lines.allSatisfy { $0.split(separator: ",", omittingEmptySubsequences: false).count == columns })

        let json = try DailyExport.featuresJSON(cycles: cycles)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([NightFeatures].self, from: json)
        #expect(decoded.count == cycles.count)
    }
}
