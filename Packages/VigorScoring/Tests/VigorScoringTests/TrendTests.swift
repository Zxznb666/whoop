import Foundation
import Testing
@testable import VigorScoring

@Suite("TrendAnalysis")
struct TrendTests {
    @Test("7 天均值高于 60 天正常范围上沿：适应良好")
    func adaptedWell() throws {
        var values = [Double](repeating: log(40), count: 53)
        values += [Double](repeating: log(80), count: 7)
        let summary = try #require(TrendAnalysis.summarize(lnRMSSD: values))
        #expect(summary.state == .adaptedWell)
    }

    @Test("7 天均值低于正常范围下沿：疲劳累积")
    func fatigue() throws {
        var values = [Double](repeating: log(40), count: 53)
        values += [Double](repeating: log(15), count: 7)
        let summary = try #require(TrendAnalysis.summarize(lnRMSSD: values))
        #expect(summary.state == .fatigueAccumulating)
    }

    @Test("数据不足 7 晚时没有趋势")
    func tooFew() {
        #expect(TrendAnalysis.summarize(lnRMSSD: [1, 2, 3]) == nil)
    }
}
