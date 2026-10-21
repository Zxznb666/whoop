import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// 端侧 Foundation Models 适配（PRD §6.10）：先检查 `SystemLanguageModel.default.isAvailable`。
@available(iOS 26.0, watchOS 26.0, macOS 26.0, *)
public struct OnDeviceCoach: CoachProvider {
    public let name = "端侧模型"

    public init() {}

    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public func dailyLine(for summary: DailySummary) async throws -> String {
        let session = LanguageModelSession(instructions: "你是一位简洁的身体状态教练，只用中文、一句话、不超过 60 字。")
        let prompt = try CoachPreview.text(for: summary)
        let response = try await session.respond(to: prompt)
        return response.content
    }

    /// 报告总结：指令与内容都由调用方给出，本地生成，不发出设备。
    public func complete(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif
