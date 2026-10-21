import Foundation
import Testing
import VigorScoring
@testable import VigorCoach

@Suite("周报文字与来源顺序")
struct NarrativeTests {
    private func report(kind: PeriodReport.Kind = .week, debt: Double? = -0.5, workouts: Int = 2) -> PeriodReport {
        PeriodReport(
            kind: kind,
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_600_000),
            cycleCount: 3,
            meanRecovery: 62.4,
            meanStrain: 11.25,
            meanSleepScore: 80.6,
            bestRecoveryDay: nil,
            worstRecoveryDay: nil,
            workoutCount: workouts,
            totalStrain: 33.75,
            debtChangeHours: debt,
            topInsights: []
        )
    }

    @Test("来源顺序：端侧可用时优先；否则必须同时有 key 与确认才用 Claude；其余用模板")
    func routerOrder() {
        #expect(NarrativeRouter.choose(onDeviceAvailable: true, claudeKey: "k", confirmed: true) == .onDevice)
        #expect(NarrativeRouter.choose(onDeviceAvailable: false, claudeKey: "k", confirmed: true) == .claude)
        #expect(NarrativeRouter.choose(onDeviceAvailable: false, claudeKey: "k", confirmed: false) == .template)
        #expect(NarrativeRouter.choose(onDeviceAvailable: false, claudeKey: "", confirmed: true) == .template)
        #expect(NarrativeRouter.choose(onDeviceAvailable: false, claudeKey: nil, confirmed: true) == .template)
    }

    @Test("模板周报：只使用报告中的数字，四舍五入规则固定")
    func templateWeek() {
        let text = PeriodNarrator.template(for: report())
        #expect(text == "本周 3 个周期，平均恢复 62%，平均负荷 11.2，平均睡眠分 81，训练 2 次。睡眠负债减少 0.5 小时。")
    }

    @Test("模板月报：用“本月”，没有训练时不提训练，负债基本持平")
    func templateMonth() {
        let text = PeriodNarrator.template(for: report(kind: .month, debt: 0.01, workouts: 0))
        #expect(text.hasPrefix("本月 3 个周期"))
        #expect(!text.contains("训练"))
        #expect(text.contains("睡眠负债基本持平 0.0 小时。"))
    }

    @Test("Claude 文本请求：端点、请求头、模型与用户内容都正确；解析返回的第一段文字")
    func claudeTextRequest() throws {
        let request = try ClaudeText.request(system: "系统", user: "用户内容", apiKey: "test-key", model: "claude-haiku-5-5")
        #expect(request.url == ClaudeCoach.endpoint)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["model"] as? String == "claude-haiku-5-5")
        #expect(body?["system"] as? String == "系统")

        let response = Data(#"{"content":[{"type":"text","text":"很好"}]}"#.utf8)
        #expect(try ClaudeText.parse(response) == "很好")
        #expect(throws: ClaudeCoachError.badResponse) {
            try ClaudeText.parse(Data("{}".utf8))
        }
    }

    @Test("周报预览：发送前看到的 JSON 包含报告的全部数字")
    func previewContainsNumbers() throws {
        let text = try CoachPreview.reportText(for: report())
        #expect(text.contains("\"cycleCount\" : 3"))
        #expect(text.contains("\"meanRecovery\" : 62.4"))
    }
}
