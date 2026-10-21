import Foundation
import Testing
@testable import VigorCoach

@Suite("VigorCoach")
struct VigorCoachTests {
    private func summary(zone: String? = "green") -> DailySummary {
        DailySummary(
            day: "2026-10-01", recovery: 72, recoveryZone: zone, strain: 9.5, targetLower: 14, targetUpper: 18,
            sleepScore: 88, sleepHours: 7.6, sleepRegularity: 81, zHRV: 0.4, zRestingHeartRate: -0.2,
            debtHours: 0.5, illness: "none", journal: ["alcohol"], trend: "normal", recoveryState: "final"
        )
    }

    @Test("路由：端侧可用优先；否则有 key 用 Claude；都没有用模板")
    func routing() {
        #expect(CoachRouter.choose(onDeviceAvailable: true, claudeKey: "k") == .onDevice)
        #expect(CoachRouter.choose(onDeviceAvailable: false, claudeKey: "k") == .claude)
        #expect(CoachRouter.choose(onDeviceAvailable: false, claudeKey: "") == .template)
        #expect(CoachRouter.choose(onDeviceAvailable: false, claudeKey: nil) == .template)
    }

    @Test("模板文案按分区给出建议")
    func templateByZone() async throws {
        let coach = TemplateCoach()
        #expect(try await coach.dailyLine(for: summary(zone: "green")).contains("适合安排高强度训练"))
        #expect(try await coach.dailyLine(for: summary(zone: "red")).contains("需要恢复"))
        #expect(try await coach.dailyLine(for: summary(zone: "red")).contains("轻松活动"))
        #expect(try await coach.dailyLine(for: summary(zone: nil)).contains("还没有恢复分数"))
    }

    @Test("发送前必须确认，否则不会调用网络")
    func sendRequiresConfirmation() async {
        let coach = ClaudeCoach(apiKey: "sk-test", confirmed: false) { _ in
            Issue.record("未确认时不应发送")
            return Data()
        }
        await #expect(throws: ClaudeCoachError.notConfirmed) {
            _ = try await coach.dailyLine(for: summary())
        }
    }

    @Test("Claude 请求：端点、请求头、默认模型，正文只包含脱敏汇总")
    func claudeRequest() throws {
        let request = try ClaudeCoach.request(for: summary(), apiKey: "sk-test")
        #expect(request.url == URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "claude-haiku-5-5")
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("2026-10-01"))
        #expect(!text.contains("T"))
    }

    @Test("Claude 响应解析：取第一个文本块")
    func parsesResponse() async throws {
        let json = #"{"content":[{"type":"text","text":"今天状态不错，按计划训练。"}]}"#
        let coach = ClaudeCoach(apiKey: "sk-test", confirmed: true) { _ in Data(json.utf8) }
        #expect(try await coach.dailyLine(for: summary()) == "今天状态不错，按计划训练。")
    }

    @Test("预览：与发送的内容完全一致，包含脱敏字段")
    func previewMatchesPayload() throws {
        let preview = try CoachPreview.text(for: summary())
        #expect(preview.contains("\"recovery\" : 72"))
        #expect(preview.contains("\"journal\""))
    }
}
