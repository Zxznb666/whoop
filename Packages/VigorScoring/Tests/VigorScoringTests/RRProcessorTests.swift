import Foundation
import Testing
@testable import VigorScoring

@Suite("RRProcessor")
struct RRProcessorTests {
    /// rr 为相邻两拍之间的毫秒数；gapBeats 为带有 precededByGap 的拍序号（从 1 开始）。
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

    @Test("RMSSD 基础计算")
    func basicRMSSD() throws {
        let result = RRProcessor.analyze(makeSeries(rr: [1000, 1010, 990, 1000]), config: .default)
        let expected = [1000.0, 1010, 990, 1000]
        #expect(result.acceptedRRms.count == expected.count)
        for (actual, value) in zip(result.acceptedRRms, expected) {
            #expect(abs(actual - value) < 1e-6)
        }
        #expect(result.candidateRR == 4)
        #expect(result.acceptedRR == 4)
        #expect(result.rejectedRR == 0)
        let rmssd = try #require(result.rmssd)
        #expect(abs(rmssd - 200.0.squareRoot()) < 1e-6)
    }

    @Test("越界 RR 被拒绝，跨过它的差值不计算")
    func rejectsOutOfRange() throws {
        // 第 3 个 RR 为 2500 ms，被拒绝；其前后相邻的 1010 与 990 之间不计算 Δ。
        let result = RRProcessor.analyze(makeSeries(rr: [1000, 1010, 2500, 1010, 990]), config: .default)
        #expect(result.candidateRR == 5)
        #expect(result.rejectedRR == 1)
        #expect(result.acceptedRR == 4)
        // Δ 只有 1010→1000 的 +10 和 990→1010 的 −20，RMSSD = √((100 + 400) / 2) = √250
        let rmssd = try #require(result.rmssd)
        #expect(abs(rmssd - 250.0.squareRoot()) < 1e-6)
    }

    @Test("突变 30% 的 RR 被拒绝，之后的 RR 不与之前的计算 Δ")
    func rejectsSuccessiveChange() {
        let result = RRProcessor.analyze(makeSeries(rr: [1000, 1000, 1300, 1000]), config: .default)
        #expect(result.rejectedRR == 1)
        #expect(result.acceptedRR == 3)
        #expect(result.acceptedRRms.allSatisfy { abs($0 - 1000) < 1e-6 })
        // 只有前两个 1000 之间有 Δ = 0，RMSSD 为 0
        #expect(result.rmssd == 0)
    }

    @Test("突变拒绝后的 Δ 只在连续的被接受 RR 之间计算")
    func successiveChangeDoesNotBridge() throws {
        // 1300 被拒绝；随后的 1000 与 1020 之间已被打断，不计算 Δ。
        // 只有 1000→1020 的 +20 和 1000→1030 的 +30 参与计算：√((400 + 900) / 2) = √650
        let result = RRProcessor.analyze(makeSeries(rr: [1000, 1020, 1300, 1000, 1030]), config: .default)
        #expect(result.rejectedRR == 1)
        #expect(result.acceptedRR == 4)
        let rmssd = try #require(result.rmssd)
        #expect(abs(rmssd - 650.0.squareRoot()) < 1e-6)
    }

    @Test("precededByGap 的拍不产生 RR，也不跨它计算 Δ")
    func gapBreaksContinuity() throws {
        // 第 3 拍的 precededByGap 为 true：RR 序列为 1000、1010、(无)、1030、1020。
        // 1010→1030 之间被打断不计算 Δ；只有 1030→1020 的 −10 参与计算。
        let result = RRProcessor.analyze(makeSeries(rr: [1000, 1010, 1000, 1030, 1020], gapBeats: [3]), config: .default)
        #expect(result.candidateRR == 4)
        #expect(result.acceptedRR == 4)
        #expect(result.rejectedRR == 0)
        #expect(result.acceptedRRms.count == 4)
        let expected = [1000.0, 1010, 1030, 1020]
        for (actual, value) in zip(result.acceptedRRms, expected) {
            #expect(abs(actual - value) < 1e-6)
        }
        // Δ = [10, −10]，RMSSD = √((100 + 100) / 2) = 10
        let rmssd = try #require(result.rmssd)
        #expect(abs(rmssd - 10) < 1e-6)
    }

    @Test("只有 20 个有效 RR 时无效，原因为有效 RR 不足")
    func tooFewValidRR() {
        let result = RRProcessor.analyze(makeSeries(rr: Array(repeating: 1000, count: 20)), config: .default)
        #expect(result.acceptedRR == 20)
        #expect(result.isValid == false)
        #expect(result.invalidReason == "有效 RR 不足")
    }

    @Test("40 个有效 RR 时有效")
    func enoughValidRR() throws {
        let rr = (0..<40).map { $0.isMultiple(of: 2) ? 1000.0 : 1010.0 }
        let result = RRProcessor.analyze(makeSeries(rr: rr), config: .default)
        #expect(result.isValid == true)
        #expect(result.invalidReason == nil)
        let rmssd = try #require(result.rmssd)
        #expect(abs(rmssd - 10) < 1e-6)
    }

    @Test("剔除率超过 20% 时无效，原因为伪迹比例过高")
    func tooManyArtifacts() {
        // 40 个 RR 中每 4 个的第 4 个为 2500 ms：共 10 个被拒绝（25%），30 个被接受。
        let rr = (0..<40).map { index -> Double in
            if index % 4 == 3 { return 2500 }
            return index.isMultiple(of: 2) ? 1000 : 1010
        }
        let result = RRProcessor.analyze(makeSeries(rr: rr), config: .default)
        #expect(result.candidateRR == 40)
        #expect(result.rejectedRR == 10)
        #expect(result.acceptedRR == 30)
        #expect(result.isValid == false)
        #expect(result.invalidReason == "伪迹比例过高")
    }
}
