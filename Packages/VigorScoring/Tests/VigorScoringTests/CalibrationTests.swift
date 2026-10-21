import Foundation
import Testing
@testable import VigorScoring

@Suite("Calibration")
struct CalibrationTests {
    @Test("岭回归：λ 很小时恢复真实系数；λ 很大时收缩到先验")
    func ridgeShrinkage() throws {
        let x: [[Double]] = (0..<50).map { [Double($0 % 7), Double($0 % 5)] }
        let y = x.map { 2 * $0[0] - 1 * $0[1] }
        let nearOLS = try #require(RidgeRegression.fit(features: x, targets: y, lambda: 1e-9, priorWeights: [0, 0]))
        #expect(abs(nearOLS[0] - 2) < 1e-6)
        #expect(abs(nearOLS[1] + 1) < 1e-6)

        let shrunk = try #require(RidgeRegression.fit(features: x, targets: y, lambda: 1e9, priorWeights: [0.5, 0.5]))
        #expect(abs(shrunk[0] - 0.5) < 1e-3)
        #expect(abs(shrunk[1] - 0.5) < 1e-3)
    }

    @Test("Cholesky 求解：已知解的 2×2 系统")
    func choleskyKnownSolution() throws {
        let solution = try #require(RidgeRegression.choleskySolve([[4, 2], [2, 3]], [8, 7]))
        #expect(abs(solution[0] - 1.25) < 1e-12)
        #expect(abs(solution[1] - 1.5) < 1e-12)
    }

    @Test("校准：样本不足 45 天时不评估")
    func needsFortyFiveDays() {
        let samples = (0..<30).map { (features: [Double($0 % 3)], energy: Double($0 % 5 + 1)) }
        #expect(Calibration.evaluate(samples: samples, defaultWeights: [1], lambda: 1) == nil)
    }

    @Test("校准：按 70/30 切分；提升不足 0.05 时不建议采用")
    func splitAndGate() throws {
        let samples = (0..<60).map { day -> (features: [Double], energy: Double) in
            let z = Double(day % 9) - 4
            return (features: [z], energy: 3 + 0.5 * z + Double(day % 2) * 0.01)
        }
        let report = try #require(Calibration.evaluate(samples: samples, defaultWeights: [0.5], lambda: 0.1))
        #expect(report.trainCount == 42)
        #expect(report.validationCount == 18)
        #expect(report.weights.count == 1)
        #expect(report.recommended == ((report.improvement ?? 0) >= 0.05))
    }
}
