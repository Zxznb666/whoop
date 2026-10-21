import Testing
@testable import VigorDesign
import VigorScoring

@Suite("VigorDesign")
struct VigorDesignTests {
    @Test("分区颜色与文字一一对应（色弱友好）")
    func zoneLabels() {
        #expect(VigorTokens.label(for: .green) == "绿")
        #expect(VigorTokens.label(for: .yellow) == "黄")
        #expect(VigorTokens.label(for: .red) == "红")
    }

    @Test("睡眠分期都有名称")
    func stageLabels() {
        let stages: [SleepStage] = [.awake, .inBed, .core, .deep, .rem, .asleepUnspecified]
        #expect(stages.allSatisfy { !VigorTokens.label(for: $0).isEmpty })
    }
}
