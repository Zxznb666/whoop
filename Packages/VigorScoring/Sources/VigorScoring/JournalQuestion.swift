import Foundation

/// 日志问卷的一道题（PRD §6.5）。题目可以增删、排序，配置保存在 App 的 UserDefaults 中。
public struct JournalQuestion: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: Codable, Sendable, Hashable {
        /// 是 / 否，回答写入 `JournalEntry.behaviors`
        case yesNo
        /// 数量，回答写入 `JournalEntry.quantities`；`unit` 只用于显示
        case quantity(unit: String)
    }

    /// 稳定标识：算法按它识别行为（例如 "alcohol"），修改标题不改变标识。
    public var id: String
    public var title: String
    public var kind: Kind

    public init(id: String, title: String, kind: Kind = .yesNo) {
        self.id = id
        self.title = title
        self.kind = kind
    }

    /// PRD §6.5 的默认题目。“不适”由单独的开关确认（§5.12.1），不在这里重复。
    public static let defaults: [JournalQuestion] = [
        JournalQuestion(id: "alcohol", title: "饮酒"),
        JournalQuestion(id: "lateDinner", title: "睡前 3 小时内进食"),
        JournalQuestion(id: "caffeineAfter2pm", title: "14 点后摄入咖啡因"),
        JournalQuestion(id: "screenBeforeBed", title: "睡前看屏幕"),
        JournalQuestion(id: "lateTraining", title: "晚间训练"),
        JournalQuestion(id: "stress", title: "压力大"),
        JournalQuestion(id: "travel", title: "旅行"),
        JournalQuestion(id: "sauna", title: "桑拿"),
        JournalQuestion(id: "supplements", title: "补剂"),
    ]

    /// 配置的编解码：题目列表以 JSON 保存，解码失败时由调用方回退到 `defaults`。
    public static func encode(_ questions: [JournalQuestion]) throws -> Data {
        try JSONEncoder().encode(questions)
    }

    public static func decode(_ data: Data) throws -> [JournalQuestion] {
        try JSONDecoder().decode([JournalQuestion].self, from: data)
    }
}
