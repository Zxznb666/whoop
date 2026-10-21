import Foundation

public struct HRVConfig: Sendable, Hashable, Codable {
    public var minRRms = 300.0
    public var maxRRms = 2000.0
    /// 相对上一个“被接受”的 RR
    public var maxSuccessiveChange = 0.20
    public var minValidRR = 30
    public var maxRejectRate = 0.20
    /// 片段中点落在睡眠后 1/3
    public var lateSleepWeight = 1.5
    /// 片段中点落在深睡分期内
    public var deepSleepWeight = 1.3
    public var morningWindow: TimeInterval = 3600
    public var sessionMergeGap: TimeInterval = 3600
    public var napMaxDuration: TimeInterval = 3 * 3600

    public static let `default` = HRVConfig()

    public init() {}
}
