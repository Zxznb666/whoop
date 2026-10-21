import Foundation

/// 某个夜晚对应的日志记录（PRD §6.5）。`night` 为醒来日的本地零点，与 §4.4 的 nightKey 一致。
public struct JournalEntry: Codable, Sendable, Hashable {
    public var night: Date
    /// 是否做过某行为，键为行为标识，例如 "alcohol"、"lateDinner"、"caffeineAfter2pm"
    public var behaviors: [String: Bool]
    /// 主观精力 1–5
    public var energy: Int?
    /// 是否确认“不适”（§5.12.1）
    public var feltUnwell: Bool

    public init(night: Date, behaviors: [String: Bool] = [:], energy: Int? = nil, feltUnwell: Bool = false) {
        self.night = night
        self.behaviors = behaviors
        self.energy = energy
        self.feltUnwell = feltUnwell
    }
}
