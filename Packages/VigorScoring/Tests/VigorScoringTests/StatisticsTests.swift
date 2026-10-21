import Foundation
import Testing
@testable import VigorScoring

@Suite("Statistics")
struct StatisticsTests {
    @Test("加权中位数：[ln20, ln30, ln40]，权重 [1, 1, 3] → ln40")
    func weightedMedianExample() throws {
        let values = [log(20.0), log(30.0), log(40.0)]
        let result = try #require(Statistics.weightedMedian(values, weights: [1, 1, 3]))
        #expect(result == log(40.0))
    }

    @Test("线性插值分位数：样本 1…20 的第 10 百分位 = 2.9")
    func percentileLinear() throws {
        let result = try #require(Statistics.percentile((1...20).map(Double.init), 0.10))
        #expect(abs(result - 2.9) < 1e-12)
    }

    @Test("MAD 与 σ 换算：{1, 2, 3, 4, 100} 的中位数 3，MAD = 1")
    func madExample() throws {
        let mad = try #require(Statistics.mad([1, 2, 3, 4, 100]))
        #expect(mad == 1)
    }

    @Test("加权四分位距为上下四分位之差")
    func weightedIQR() throws {
        let values = (1...8).map(Double.init)
        let iqr = try #require(Statistics.weightedIQR(values, weights: [Double](repeating: 1, count: 8)))
        #expect(iqr == 4)
    }
}
