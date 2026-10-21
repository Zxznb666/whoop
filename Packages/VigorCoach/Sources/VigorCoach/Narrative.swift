import Foundation
import VigorScoring

/// 周报与月报的文字来源（PRD §6.7、§9.3）。顺序固定：端侧 → Claude → 模板。
public enum NarrativeSource: String, Sendable, Hashable {
    case onDevice
    case claude
    case template

    public var label: String {
        switch self {
        case .onDevice: "端侧模型"
        case .claude: "Claude"
        case .template: "模板"
        }
    }
}

public enum NarrativeRouter {
    /// 端侧可用时优先使用，不发出设备；否则只有用户填了 key 并且已在预览中确认，才使用 Claude；都不满足时用模板。
    public static func choose(onDeviceAvailable: Bool, claudeKey: String?, confirmed: Bool) -> NarrativeSource {
        if onDeviceAvailable { return .onDevice }
        if let key = claudeKey, !key.isEmpty, confirmed { return .claude }
        return .template
    }
}

/// 模板版周报 / 月报文字：只用报告中的数字，不做推断，任何设备都能生成。
public enum PeriodNarrator {
    public static func template(for report: PeriodReport) -> String {
        let period = report.kind == .week ? "本周" : "本月"
        var parts = ["\(period) \(report.cycleCount) 个周期"]
        if let recovery = report.meanRecovery {
            parts.append("平均恢复 \(Int(recovery.rounded()))%")
        }
        if let strain = report.meanStrain {
            parts.append("平均负荷 \(String(format: "%.1f", strain))")
        }
        if let sleep = report.meanSleepScore {
            parts.append("平均睡眠分 \(Int(sleep.rounded()))")
        }
        if report.workoutCount > 0 {
            parts.append("训练 \(report.workoutCount) 次")
        }
        var text = parts.joined(separator: "，") + "。"
        if let debt = report.debtChangeHours {
            let direction = debt > 0.05 ? "增加" : (debt < -0.05 ? "减少" : "基本持平")
            text += String(format: "睡眠负债%@ %.1f 小时。", direction, abs(debt))
        }
        return text
    }
}

public extension CoachPreview {
    /// 周报 / 月报发送前的预览：将要发送的确切 JSON。
    static func reportText(for report: PeriodReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }
}

/// 不带周期汇总的纯文本请求（周报总结与连接测试使用）。仍然只在用户确认后由调用方发送。
public enum ClaudeText {
    public static func request(system: String, user: String, apiKey: String, model: String = ClaudeCoach.defaultModel) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 300,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        var request = URLRequest(url: ClaudeCoach.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func parse(_ data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else { throw ClaudeCoachError.badResponse }
        return text
    }
}
