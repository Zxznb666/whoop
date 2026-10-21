import Foundation

/// 数据质量等级（PRD §5.7）。质量分的计算放在阶段 3。
public enum DataQuality: String, Codable, Sendable, Hashable {
    case high
    case medium
    case low
    case none
}
