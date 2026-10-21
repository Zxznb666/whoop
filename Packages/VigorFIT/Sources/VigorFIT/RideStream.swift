import Foundation

/// 1 Hz 对齐的骑行数据（施工文档 §4.1）。数组下标 = 距开始的秒数，缺失为 nil。
/// 暂停区间内没有采样点，数组同样为 nil；是否按 0 填充由评分层决定。
public struct RideStream: Sendable, Codable, Equatable, Hashable {
    public var fileID: String
    public var device: FITFileID
    public var sport: Int?
    public var start: Date
    public var heartRate: [Int?]
    public var power: [Int?]
    public var cadence: [Int?]
    public var speed: [Double?]
    public var distance: [Double?]
    public var altitude: [Double?]
    public var latitude: [Double?]
    public var longitude: [Double?]
    /// 计时器暂停的秒数区间（与 `heartRate` 的下标一致，左闭右开）。
    public var pauses: [Range<Int>]
    public var laps: [FITLap]

    public init(
        fileID: String,
        device: FITFileID,
        sport: Int?,
        start: Date,
        heartRate: [Int?],
        power: [Int?],
        cadence: [Int?],
        speed: [Double?],
        distance: [Double?],
        altitude: [Double?],
        latitude: [Double?],
        longitude: [Double?],
        pauses: [Range<Int>],
        laps: [FITLap]
    ) {
        self.fileID = fileID
        self.device = device
        self.sport = sport
        self.start = start
        self.heartRate = heartRate
        self.power = power
        self.cadence = cadence
        self.speed = speed
        self.distance = distance
        self.altitude = altitude
        self.latitude = latitude
        self.longitude = longitude
        self.pauses = pauses
        self.laps = laps
    }

    /// 只有功率与心率的骑行（测试与合成数据用）。
    public static func simple(fileID: String, start: Date, heartRate: [Int?], power: [Int?], pauses: [Range<Int>] = []) -> RideStream {
        let count = max(heartRate.count, power.count)
        let blank = [Double?](repeating: nil, count: count)
        return RideStream(
            fileID: fileID, device: FITFileID(), sport: 2, start: start,
            heartRate: heartRate + [Int?](repeating: nil, count: count - heartRate.count),
            power: power + [Int?](repeating: nil, count: count - power.count),
            cadence: [Int?](repeating: nil, count: count), speed: blank, distance: blank,
            altitude: blank, latitude: blank, longitude: blank, pauses: pauses, laps: []
        )
    }

    /// 时长（秒）= 最后一条记录的秒数 + 1。
    public var durationSeconds: Int { heartRate.count }

    /// 从解码结果生成逐秒数组。没有任何采样点时返回 nil。
    public static func make(from activity: FITActivity) -> RideStream? {
        guard let start = activity.sessions.first?.startTime ?? activity.records.map(\.timestamp).min() else {
            return nil
        }
        let indexed: [(index: Int, record: FITRecord)] = activity.records.compactMap { record in
            let index = Int(record.timestamp.timeIntervalSince(start).rounded())
            return index >= 0 ? (index, record) : nil
        }
        guard let last = indexed.map(\.index).max() else { return nil }
        let count = last + 1

        var stream = RideStream(
            fileID: activity.fileID.identity,
            device: activity.fileID,
            sport: activity.sessions.first?.sport,
            start: start,
            heartRate: Array(repeating: nil, count: count),
            power: Array(repeating: nil, count: count),
            cadence: Array(repeating: nil, count: count),
            speed: Array(repeating: nil, count: count),
            distance: Array(repeating: nil, count: count),
            altitude: Array(repeating: nil, count: count),
            latitude: Array(repeating: nil, count: count),
            longitude: Array(repeating: nil, count: count),
            pauses: [],
            laps: activity.laps
        )
        // 同一秒多条记录时，后出现的覆盖先出现的。
        for (index, record) in indexed {
            stream.heartRate[index] = record.heartRate
            stream.power[index] = record.power
            stream.cadence[index] = record.cadence
            stream.speed[index] = record.speed
            stream.distance[index] = record.distance
            stream.altitude[index] = record.altitude
            stream.latitude[index] = record.latitude
            stream.longitude[index] = record.longitude
        }

        // 暂停：停止事件到下一个开始事件之间。结束时仍未恢复的暂停延伸到末尾。
        var pauseStart: Int?
        for event in activity.timerEvents.sorted(by: { $0.time < $1.time }) {
            let index = Int(event.time.timeIntervalSince(start).rounded())
            if event.isStart {
                if let from = pauseStart { stream.appendPause(from, to: index, count: count) }
                pauseStart = nil
            } else if pauseStart == nil {
                pauseStart = index
            }
        }
        if let from = pauseStart { stream.appendPause(from, to: count, count: count) }
        return stream
    }

    private mutating func appendPause(_ from: Int, to: Int, count: Int) {
        let lower = max(0, from)
        let upper = min(count, to)
        if lower < upper { pauses.append(lower..<upper) }
    }
}
