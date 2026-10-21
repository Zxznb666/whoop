import Foundation

/// 某个夜晚对应的日志记录（PRD §6.5）。`night` 为醒来日的本地零点，与周期的 `wakeDay` 对齐：
/// 醒来日为 D+1 的记录，回答的是 D 日（“昨天”）的行为与状态。
public struct JournalEntry: Codable, Sendable, Hashable {
    public var night: Date
    /// 是否做过某行为，键为行为标识，例如 "alcohol"、"lateDinner"、"caffeineAfter2pm"
    public var behaviors: [String: Bool]
    /// 数量题的回答，键与 `JournalQuestion.id` 一致
    public var quantities: [String: Double]
    /// 主观精力 1–5
    public var energy: Int?
    /// 是否确认“不适”（§5.12.1）
    public var feltUnwell: Bool

    public init(
        night: Date,
        behaviors: [String: Bool] = [:],
        quantities: [String: Double] = [:],
        energy: Int? = nil,
        feltUnwell: Bool = false
    ) {
        self.night = night
        self.behaviors = behaviors
        self.quantities = quantities
        self.energy = energy
        self.feltUnwell = feltUnwell
    }

    /// 旧版本的记录没有 `quantities` 字段，解码时填空字典。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        night = try container.decode(Date.self, forKey: .night)
        behaviors = try container.decodeIfPresent([String: Bool].self, forKey: .behaviors) ?? [:]
        quantities = try container.decodeIfPresent([String: Double].self, forKey: .quantities) ?? [:]
        energy = try container.decodeIfPresent(Int.self, forKey: .energy)
        feltUnwell = try container.decodeIfPresent(Bool.self, forKey: .feltUnwell) ?? false
    }
}
