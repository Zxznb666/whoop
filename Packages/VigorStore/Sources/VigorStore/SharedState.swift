import Foundation

/// App Group 的标识：主 App、小组件与手表共用。重签名后可能不可用，读写都必须容忍失败。
public enum VigorConstants {
    public static let appGroupID = "group.com.example.vigor"
}

/// 供小组件与手表读取的共享状态（施工文档 §5 阶段 5 第 1 条）。
public struct SharedState: Codable, Sendable, Hashable {
    public var recovery: Double?
    public var recoveryZone: String?
    public var strain: Double?
    public var strainTargetLower: Double?
    public var strainTargetUpper: Double?
    public var sleepScore: Double?
    public var suggestedBedtime: Date?
    public var stateRaw: String
    public var updatedAt: Date
    /// App Group 是否可用；不可用时状态文件保存在 App 自己的目录中
    public var appGroupAvailable: Bool
    /// 手表训练模式计算实时负荷需要的参数（PRD §6.8）；缺失时手表使用默认值
    public var restingHeartRate: Double?
    public var maxHeartRate: Double?

    public init(
        recovery: Double?,
        recoveryZone: String?,
        strain: Double?,
        strainTargetLower: Double?,
        strainTargetUpper: Double?,
        sleepScore: Double?,
        suggestedBedtime: Date?,
        stateRaw: String,
        updatedAt: Date,
        appGroupAvailable: Bool,
        restingHeartRate: Double? = nil,
        maxHeartRate: Double? = nil
    ) {
        self.recovery = recovery
        self.recoveryZone = recoveryZone
        self.strain = strain
        self.strainTargetLower = strainTargetLower
        self.strainTargetUpper = strainTargetUpper
        self.sleepScore = sleepScore
        self.suggestedBedtime = suggestedBedtime
        self.stateRaw = stateRaw
        self.updatedAt = updatedAt
        self.appGroupAvailable = appGroupAvailable
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
    }
}

public enum SharedStateStore {
    public static let fileName = "shared-state.json"
    /// WatchConnectivity 的 applicationContext 中共享状态的键（手机发送、手表接收）
    public static let watchPayloadKey = "sharedState"

    /// App Group 容器中的文件位置；容器不可用时返回 nil。
    public static func appGroupFileURL(groupID: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    /// App 自己的目录中的备用位置。
    public static func fallbackFileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(fileName)
    }

    /// 写入：优先 App Group；失败或不可用时写入备用位置。返回实际写入的位置与是否使用了 App Group。
    @discardableResult
    public static func write(_ state: SharedState, groupID: String) throws -> (url: URL, appGroupUsed: Bool) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        if let url = appGroupFileURL(groupID: groupID) {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                return (url, true)
            } catch {
                // 容器路径存在但不可写（例如重签名后 App Group 权限不完整），改写备用位置
            }
        }
        let url = try fallbackFileURL()
        try data.write(to: url, options: .atomic)
        return (url, false)
    }

    /// 读取最近一次写入的状态：先找 App Group，再找 App 自己的备用位置。两者都读不到（例如重签名后 App Group 不可用，
    /// 且小组件无法访问 App 的目录）时返回 nil。调用方应显示“打开元气以更新”，而不是崩溃。
    public static func readLatest(groupID: String) -> SharedState? {
        let candidates = [appGroupFileURL(groupID: groupID), try? fallbackFileURL()].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let state = try? read(from: url) {
                return state
            }
        }
        return nil
    }

    /// 编码为 WatchConnectivity 与其他通道使用的 JSON 数据。
    public static func encode(_ state: SharedState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    public static func decode(_ data: Data) throws -> SharedState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(SharedState.self, from: data)
    }

    public static func read(from url: URL) throws -> SharedState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(SharedState.self, from: Data(contentsOf: url))
    }
}
