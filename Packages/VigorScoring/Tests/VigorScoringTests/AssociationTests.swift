import Foundation
import Testing
@testable import VigorScoring

@Suite("Association")
struct AssociationTests {
    @Test("Student t 分布：t = 2.0、df = 10 时双侧 p ≈ 0.07339（±0.0005）")
    func studentPValue() {
        let p = Distributions.twoSidedPValue(t: 2.0, df: 10)
        #expect(abs(p - 0.07339) < 0.0005)
    }

    @Test("t 分布的 CDF 关于 0 对称，且 CDF(0) = 0.5")
    func studentCDFSymmetry() {
        #expect(abs(Distributions.studentTCDF(0, df: 5) - 0.5) < 1e-9)
        let upper = Distributions.studentTCDF(1.3, df: 7)
        let lower = Distributions.studentTCDF(-1.3, df: 7)
        #expect(abs(upper + lower - 1) < 1e-9)
    }

    @Test("Welch：自由度公式与 t 统计量")
    func welchFormula() throws {
        let a = [10.0, 12, 11, 13, 9]
        let b = [7.0, 8, 6, 9, 7, 8]
        let result = try #require(Association.welch(a, b))
        let meanA = a.reduce(0, +) / Double(a.count)
        let meanB = b.reduce(0, +) / Double(b.count)
        #expect(abs(result.difference - (meanA - meanB)) < 1e-12)
        let varA = a.reduce(0) { $0 + ($1 - meanA) * ($1 - meanA) } / 4
        let varB = b.reduce(0) { $0 + ($1 - meanB) * ($1 - meanB) } / 5
        let seA = varA / 5
        let seB = varB / 6
        let expectedDF = (seA + seB) * (seA + seB) / (seA * seA / 4 + seB * seB / 5)
        #expect(abs(result.degreesOfFreedom - expectedDF) < 1e-9)
        #expect(abs(result.t - (meanA - meanB) / (seA + seB).squareRoot()) < 1e-12)
        #expect(result.confidenceLow < result.difference && result.difference < result.confidenceHigh)
    }

    @Test("Welch：每组至少需要 2 个样本")
    func welchNeedsSamples() {
        #expect(Association.welch([1], [2, 3, 4]) == nil)
    }

    @Test("Spearman：严格单调关系 → 1")
    func spearmanMonotonic() throws {
        let x = [1.0, 2, 3, 4, 5, 6]
        let y = x.map { pow($0, 3) }
        #expect(abs(try #require(Association.spearman(x, y)) - 1) < 1e-12)
        #expect(abs(try #require(Association.spearman(x, y.reversed())) + 1) < 1e-12)
    }

    @Test("Spearman：并列取平均秩")
    func tiedRanks() {
        #expect(Association.ranks([10, 20, 20, 30]) == [1, 2.5, 2.5, 4])
    }
}
