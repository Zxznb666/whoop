import Foundation

/// 教练的统一接口（PRD §6.10）。
public protocol CoachProvider: Sendable {
    var name: String { get }
    func dailyLine(for summary: DailySummary) async throws -> String
}

/// 模板文案：不依赖任何模型，任何设备都可用（PRD §11 的兜底）。
public struct TemplateCoach: CoachProvider {
    public let name = "模板"

    public init() {}

    public func dailyLine(for summary: DailySummary) async throws -> String {
        guard let zone = summary.recoveryZone else {
            return "今天还没有恢复分数，先完成昨晚的数据同步。"
        }
        let target = {
            guard let lower = summary.targetLower, let upper = summary.targetUpper else { return "按感觉安排训练" }
            return "目标负荷 \(lower)–\(upper)"
        }()
        switch zone {
        case "green": return "状态良好，适合安排高强度训练，\(target)。"
        case "yellow": return "状态一般，中等强度为宜，\(target)。"
        default: return "身体需要恢复，今天以轻松活动为主，\(target)。"
        }
    }
}

public enum CoachKind: String, Sendable, Hashable {
    case onDevice
    case claude
    case template
}

public enum CoachRouter {
    /// 端侧可用就用端侧；否则用户填了 key 时用 Claude；都没有时用模板（施工文档 §5 阶段 9）。
    public static func choose(onDeviceAvailable: Bool, claudeKey: String?) -> CoachKind {
        if onDeviceAvailable { return .onDevice }
        if let key = claudeKey, !key.isEmpty { return .claude }
        return .template
    }
}
