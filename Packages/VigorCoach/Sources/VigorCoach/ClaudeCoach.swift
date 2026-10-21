import Foundation

/// 发送前的预览与确认（PRD §9.3）：用户必须先看到将要发送的确切内容。
public enum CoachPreview {
    public static func text(for summary: DailySummary) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return String(decoding: try encoder.encode(summary), as: UTF8.self)
    }
}

public enum ClaudeCoachError: LocalizedError, Equatable {
    case notConfirmed
    case badResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .notConfirmed: "发送前需要先确认预览的内容。"
        case .badResponse: "教练返回的内容无法解析。"
        case .http(let status): "教练服务返回 HTTP \(status)。"
        }
    }
}

/// Claude API 适配（施工文档 §5 阶段 9）。请求头为 `x-api-key` 与 `anthropic-version: 2023-06-01`，默认模型 `claude-haiku-5-5`。
public struct ClaudeCoach: CoachProvider {
    public typealias Transport = @Sendable (URLRequest) async throws -> Data

    public let name = "Claude"
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let defaultModel = "claude-haiku-5-5"

    private let apiKey: String
    private let model: String
    private let transport: Transport
    private let confirmed: Bool

    public init(apiKey: String, model: String = ClaudeCoach.defaultModel, confirmed: Bool, transport: @escaping Transport) {
        self.apiKey = apiKey
        self.model = model
        self.confirmed = confirmed
        self.transport = transport
    }

    public func dailyLine(for summary: DailySummary) async throws -> String {
        guard confirmed else { throw ClaudeCoachError.notConfirmed }
        let request = try Self.request(for: summary, apiKey: apiKey, model: model)
        let data = try await transport(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else { throw ClaudeCoachError.badResponse }
        return text
    }

    /// 构造请求。只包含脱敏汇总的 JSON，不包含原始数据。
    public static func request(for summary: DailySummary, apiKey: String, model: String = ClaudeCoach.defaultModel) throws -> URLRequest {
        let prompt = "你是一位简洁的身体状态教练。根据下面的每日汇总，用一句中文给出今天的建议，不超过 60 字。\n"
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "messages": [
                ["role": "user", "content": prompt + (try CoachPreview.text(for: summary))],
            ],
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
