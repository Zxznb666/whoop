import Foundation
import Testing
@testable import VigorScoring

@Suite("RRProcessor")
struct RRProcessorTests {
    /// rr[i] 为第 i 与第 i+1 拍之间的毫秒数；gapBeats 为带有 precededByGap 的拍序号（从 1 开始）。
    private func makeSeries(rr: [Double], gapBeats: Set<Int> = []) -> HeartbeatSeries {
        var beats = [Beat(t: 0, precededByGap: false)]
        var time: TimeInterval = 0
        for (offset, interval) in rr.enumerated() {
            time += interval / 1000
            beats.append(Beat(t: time, precededByGap: gapBeats.contains(offset + 1)))
        }
        return HeartbeatSeries(
            id: UUID(),
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: time),
            beats: beats
        )
    }

    /// RR 在 1000 与 1020 ms 之间交替；count 为 RR 个数。
    private func alternatingSeries(count: Int) -> HeartbeatSeries {
        makeSeries(rr: (0..<count).map { $0 % 2 == 0 ? 1000 : 1020 })
    }

    /// 所有 RR 都是 1000 ms，平均心率恰为 60 bpm，RMSSD 为 0。
    private func constantSeries(count: Int) -> HeartbeatSeries {
        makeSeries(rr: [Double](repeating: 1000, count: count))
    }

    @Test("RMSSD 基础计算")
    func basicRMSSD() throws {
        let result = RRProcessor.analyze(makeSeries(rr: [1000, 1010, 990, 1000]))
        #expect(result.acceptedRR.count == 4)
        for (actual, expected) in zip(result.acceptedRR, [1000.0, 1010, 990, 1000]) {
            #expect(abs(actual - expected) < 1e-6)
        }
        #expect(result.candidateCount == 4)
        #expect(result.acceptedCount == 4)
        #expect(result.rejectedCount == 0)
        // 差值 10、-20、10，平方均值 = 200
        let rmssd = try #require(result.rmssd)
        #expect(abs(rmssd - 200.0.squareRoot()) < 1e-9)
    }

    @Test("生理范围：RR 超出 [300, 2000] ms 被剔除，跨过它的差值不计算")
    func physiologicalRange() throws {
        let result = RRProcessor.analyze(makeSeries(rr: [1000, 1010, 2500, 990, 1000]))
        #expect(result.rejectedCount == 1)
        // 1010 与 990 不相邻（中间的 2500 已删除），不计算差值；只剩 1000→1010（+10）与 990→1000（+10）
        let rmssd = try #require(result.rmssd)
        #expect(abs(rmssd - 10) < 1e-9)
    }

    @Test("局部中位数：一串 1000 ms 中间夹一个 1300 → 1300 被剔除，且不产生跨越它的 Δ")
    func localMedianRejectsSpike() throws {
        var rr = [Double](repeating: 1000, count: 10)
        rr.append(1300)
        rr += [Double](repeating: 1000, count: 10)
        let result = RRProcessor.analyze(makeSeries(rr: rr))
        #expect(result.rejectedCount == 1)
        #expect(result.rejectedBeatTimes.count == 1)
        // 所有被接受的相邻 RR 都是 1000，因此 RMSSD 必须恰好为 0
        let rmssd = try #require(result.rmssd)
        #expect(rmssd == 0)
    }

    @Test("早搏：一串 1000 ms 中出现 750 紧跟 1250 → 两拍都被剔除")
    func ectopicPairRemoved() {
        var rr = [Double](repeating: 1000, count: 8)
        rr += [750, 1250]
        rr += [Double](repeating: 1000, count: 8)
        let result = RRProcessor.analyze(makeSeries(rr: rr))
        #expect(result.rejectedCount == 2)
    }

    @Test("间隙：precededByGap 处断开，不跨间隙计算差值")
    func gapBreaksDifference() throws {
        // 第 3 个 RR（1000）紧跟在间隙之后的拍上，不属于候选
        let result = RRProcessor.analyze(makeSeries(rr: [1000, 1020, 1000, 1040, 1000], gapBeats: [3]))
        #expect(result.candidateCount == 4)
        // 差值只来自 1000→1020（+20）与 1040→1000（-40）：(400 + 1600) / 2 = 1000
        let rmssd = try #require(result.rmssd)
        #expect(abs(rmssd - 1000.0.squareRoot()) < 1e-9)
    }

    @Test("整段验收：39 个有效 RR → 无效；46 个有效 RR 且时长足够 → 有效")
    func thirtyNineRRInvalid() {
        let short = RRProcessor.analyze(alternatingSeries(count: 39))
        #expect(short.acceptedCount == 39)
        #expect(!short.isValid)
        #expect(short.invalidReason == RRProcessor.reasonInsufficientRR)

        let enough = RRProcessor.analyze(alternatingSeries(count: 46))
        #expect(enough.acceptedCount == 46)
        #expect(enough.isValid)
    }

    @Test("整段验收：时长 44 秒 → 无效；46 秒 → 有效")
    func durationGate() {
        // 44 个 RR、每个 1000 ms：时长 44 秒，RR 数量已足够
        let short = RRProcessor.analyze(constantSeries(count: 44))
        #expect(short.durationSeconds == 44)
        #expect(short.acceptedCount == 44)
        #expect(short.invalidReason == RRProcessor.reasonTooShort)

        let long = RRProcessor.analyze(constantSeries(count: 46))
        #expect(long.durationSeconds == 46)
        #expect(long.isValid)
    }

    @Test("扰动：段内平均心率 = 静息心率 × 1.2 → 丢弃；× 1.09 → 保留")
    func disturbanceDiscard() {
        // RR 恒为 1000 ms → 平均心率 60 bpm
        var discarded = RRProcessor.analyze(constantSeries(count: 61))
        #expect(discarded.isValid)
        RRProcessor.applyDisturbance(&discarded, restingHeartRate: 50, config: .default)
        #expect(discarded.invalidReason == RRProcessor.reasonDisturbed)

        var kept = RRProcessor.analyze(constantSeries(count: 61))
        RRProcessor.applyDisturbance(&kept, restingHeartRate: 55, config: .default)
        #expect(kept.isValid)
    }
}
