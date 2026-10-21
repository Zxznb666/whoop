import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("ScoringPipeline on synthetic data")
struct PipelineSyntheticTests {
    private static let endingAt = shanghaiDate(2026, 10, 1, 0)

    private func scenario() -> SyntheticScenario {
        SyntheticScenario.make(nights: 120, seed: 42, endingAt: Self.endingAt, calendar: shanghaiCalendar())
    }

    private func run(_ scenario: SyntheticScenario, now: Date = endingAt.addingTimeInterval(72 * 3600), config: ScoringConfig = .default) -> PipelineOutput {
        ScoringPipeline.run(PipelineInput(
            snapshot: scenario.snapshot,
            journal: scenario.journal,
            config: config,
            now: now,
            calendar: shanghaiCalendar()
        ))
    }

    @Test("生病预警：倒数第 20、19 晚被判为可能不适，并被排除出基线；饮酒夜不会被排除")
    func illnessDetectedAndExcluded() throws {
        let result = scenario()
        let output = run(result)
        let calendar = shanghaiCalendar()

        let sick = output.cycles.filter { cycle in
            result.truth.sickNights.contains { calendar.isDate(cycle.wakeTime, inSameDayAs: $0) }
        }
        #expect(sick.count == 2)
        // 第一晚为“注意”，第二晚连续成立 → “可能不适”，并自动排除（第一晚由它回溯排除）
        #expect(sick.first?.illness == .attention)
        #expect(sick.last?.illness == .possiblyUnwell)
        #expect(sick.first?.exclusion == .illness)
        #expect(sick.last?.exclusion == .illness)

        // 饮酒夜（未同时生病）：不会被判为可能不适，也不会被排除
        let sickDays = result.truth.sickNights
        let alcohol = output.cycles.filter { cycle in
            result.truth.alcoholNights.contains { calendar.isDate(cycle.wakeTime, inSameDayAs: $0) }
                && !sickDays.contains { calendar.isDate(cycle.wakeTime, inSameDayAs: $0) }
        }
        #expect(!alcohol.isEmpty)
        #expect(alcohol.allSatisfy { $0.illness != .possiblyUnwell })
        #expect(alcohol.allSatisfy { $0.exclusion == nil })
    }

    @Test("饮酒混杂：生病信号的夜晚若同时记录饮酒，只做提示：不排除、不推送，但仍判为可能不适")
    func confoundedIllnessIsNotExcluded() throws {
        var result = scenario()
        let calendar = shanghaiCalendar()
        let lastSick = try #require(result.truth.sickNights.sorted().last)
        for index in result.journal.indices where calendar.isDate(result.journal[index].night, inSameDayAs: lastSick) {
            result.journal[index].behaviors["alcohol"] = true
        }
        let output = run(result)
        let sick = output.cycles.filter { calendar.isDate($0.wakeTime, inSameDayAs: lastSick) }
        let cycle = try #require(sick.first)
        #expect(cycle.illnessConfounded)
        #expect(cycle.illness == .possiblyUnwell)
        #expect(cycle.exclusion == nil)
    }

    @Test("分区分布：绿 / 黄 / 红 每一区都在 15%–65% 之间（只防止参数离谱）")
    func zoneDistribution() {
        let output = run(scenario())
        let zones = output.cycles.compactMap { $0.recovery?.zone }
        #expect(zones.count > 100)
        for zone in [RecoveryZone.green, .yellow, .red] {
            let share = Double(zones.filter { $0 == zone }.count) / Double(zones.count)
            #expect(share >= 0.15 && share <= 0.65, "\(zone) 占比 \(share)")
        }
    }

    @Test("流水线性能：120 晚全量计算 < 2 秒")
    func performance() {
        let result = scenario()
        let start = Date()
        _ = run(result)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 2, "耗时 \(elapsed) 秒")
    }

    @Test("不用未来数据：改变第 N 晚的心率，第 N 晚的基线不变，第 N+1 晚的基线随之变化")
    func noFutureDataInPipeline() throws {
        let result = scenario()
        let original = run(result)
        let calendar = shanghaiCalendar()
        let index = 60
        let target = original.cycles[index]

        // 把第 N 晚睡眠期间的心率整体降低 20 bpm，使静息心率（P10）明显下降
        var changed = result
        let nightStart = target.features.session.start
        let nightEnd = target.features.session.end
        for sample in changed.snapshot.heartRate.indices
        where changed.snapshot.heartRate[sample].date >= nightStart && changed.snapshot.heartRate[sample].date <= nightEnd {
            changed.snapshot.heartRate[sample].bpm -= 20
        }
        let rerun = run(changed)

        #expect(rerun.cycles[index].features.restingHeartRate.value != target.features.restingHeartRate.value)
        #expect(rerun.cycles[index].baselines == target.baselines)
        #expect(rerun.cycles[index + 1].baselines[.restingHeartRate] != original.cycles[index + 1].baselines[.restingHeartRate])
    }

    @Test("同样的输入得到同样的输出，输入哈希稳定；改变配置版本哈希变化")
    func determinismAndHash() {
        let result = scenario()
        let first = run(result)
        let second = run(result)
        #expect(first.cycles == second.cycles)

        var config = ScoringConfig.default
        config.configVersion = 2
        let versioned = run(result, config: config)
        #expect(versioned.cycles.last?.inputHash != first.cycles.last?.inputHash)
    }

    @Test("分数状态：等待 → 初步 → 最终 → 锁定（缺少手腕温度，因此不会因数据到齐而提前为最终）")
    func scoreStates() throws {
        var result = scenario()
        result.snapshot.wristTemperature = []
        let lastWake = try #require(run(result).cycles.last?.wakeTime)

        #expect(run(result, now: lastWake.addingTimeInterval(-60)).cycles.last?.recoveryState == .waiting)
        #expect(run(result, now: lastWake.addingTimeInterval(3600)).cycles.last?.recoveryState == .preliminary)
        #expect(run(result, now: lastWake.addingTimeInterval(4 * 3600)).cycles.last?.recoveryState == .final)
        #expect(run(result, now: lastWake.addingTimeInterval(49 * 3600)).cycles.last?.recoveryState == .locked)
    }

    @Test("个性化基础需求：积累 60 晚以后给出建议，并说明是否更新")
    func personalizedNeedAfterSixtyNights() throws {
        let output = run(scenario())
        let personalized = try #require(output.personalizedNeed)
        #expect(personalized.updatedBase >= 6.5 && personalized.updatedBase <= 9.5)
    }
}
