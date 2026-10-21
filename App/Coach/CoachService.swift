import Foundation
import VigorCoach
import VigorScoring

/// 教练的设置（PRD §6.10、§9.3）：key 存钥匙串，模型名存 UserDefaults。
enum CoachSettings {
    static let apiKeyAccount = "claude-api-key"
    private static let modelKey = "vigor.coach.model"

    /// 可选的 Claude 模型（与 `VigorCoach` 的默认值一致）
    static let models = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]

    static var apiKey: String? {
        KeychainStore.read(account: apiKeyAccount)
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? ClaudeCoach.defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
            return OnDeviceCoach.isAvailable
        }
        #endif
        return false
    }
}

/// 真正发出网络请求的传输层。只在用户确认预览之后由调用方使用。
enum ClaudeTransport {
    static let send: ClaudeCoach.Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeCoachError.http(http.statusCode)
        }
        return data
    }
}

enum CoachText {
    static let reportInstructions = "你是一位简洁的身体状态教练。根据下面的周报或月报数据，用中文写两到三句总结，不超过 120 字，不做医疗判断。"

    /// 周报 / 月报的文字：端侧 → Claude（已确认）→ 模板，依次降级。任何一步失败都进入下一步，不会让界面空白。
    static func report(_ report: PeriodReport, claudeAllowed: Bool) async -> (text: String, source: NarrativeSource) {
        let prompt = (try? CoachPreview.reportText(for: report)) ?? ""
        if NarrativeRouter.choose(onDeviceAvailable: CoachSettings.onDeviceAvailable, claudeKey: nil, confirmed: false) == .onDevice,
           let text = await onDeviceText(prompt) {
            return (text, .onDevice)
        }
        if NarrativeRouter.choose(onDeviceAvailable: false, claudeKey: CoachSettings.apiKey, confirmed: claudeAllowed) == .claude,
           let key = CoachSettings.apiKey,
           let text = await claudeText(prompt, key: key) {
            return (text, .claude)
        }
        return (PeriodNarrator.template(for: report), .template)
    }

    private static func onDeviceText(_ prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
            return try? await OnDeviceCoach().complete(instructions: reportInstructions, prompt: prompt)
        }
        #endif
        return nil
    }

    private static func claudeText(_ prompt: String, key: String) async -> String? {
        do {
            let request = try ClaudeText.request(system: reportInstructions, user: prompt, apiKey: key, model: CoachSettings.model)
            return try ClaudeText.parse(try await ClaudeTransport.send(request))
        } catch {
            return nil
        }
    }
}
