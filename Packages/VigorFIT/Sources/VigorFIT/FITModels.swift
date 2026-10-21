import Foundation

/// 解码后的一次 FIT 活动文件。只保留施工文档 §4.1 要求的消息与字段，单位已换算为 SI 单位。
public struct FITActivity: Sendable, Codable, Equatable {
    public var fileID: FITFileID
    public var sessions: [FITSession]
    public var laps: [FITLap]
    public var records: [FITRecord]
    public var timerEvents: [FITTimerEvent]
}

/// `file_id` 消息。`identity` 用于去重（施工文档 §4.1：序列号 + 创建时间）。
public struct FITFileID: Sendable, Codable, Equatable, Hashable {
    public var manufacturer: Int?
    public var product: Int?
    public var serialNumber: UInt32?
    public var timeCreated: Date?

    public init(manufacturer: Int? = nil, product: Int? = nil, serialNumber: UInt32? = nil, timeCreated: Date? = nil) {
        self.manufacturer = manufacturer
        self.product = product
        self.serialNumber = serialNumber
        self.timeCreated = timeCreated
    }

    public var identity: String {
        let serial = serialNumber.map(String.init) ?? "0"
        let created = timeCreated.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        return "\(serial)-\(created)"
    }
}

public struct FITSession: Sendable, Codable, Equatable {
    public var startTime: Date?
    public var sport: Int?
    public var totalElapsedSeconds: Double?
    public var totalDistance: Double?
}

public struct FITLap: Sendable, Codable, Equatable {
    public var startTime: Date?
    public var endTime: Date?
}

/// `record` 消息（逐秒采样点）。缺失或无效的字段为 nil。
public struct FITRecord: Sendable, Codable, Equatable {
    public var timestamp: Date
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var heartRate: Int?
    public var cadence: Int?
    public var distance: Double?
    public var speed: Double?
    public var power: Int?
}

/// `event` 消息中的计时器事件：开始或停止（暂停识别用）。
public struct FITTimerEvent: Sendable, Codable, Equatable {
    public var time: Date
    public var isStart: Bool
}

public enum FITError: Error, Equatable, Sendable {
    case truncated
    case invalidHeader
    case headerCRCMismatch
    case crcMismatch
    case corrupt(String)
}
