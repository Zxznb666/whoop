import Foundation
import VigorScoring

/// 心跳序列的二进制编解码（施工文档 §4.3）：
/// 头部为 start、end（Float64，距 1970 的秒数）与拍数（UInt32）；
/// 每拍为 t（Float64，距序列开始的秒数）加一个 UInt8 间隙标记。
public enum HeartbeatCodec {
    public enum DecodingError: Error, Equatable {
        case truncated
    }

    public static func encode(_ series: HeartbeatSeries) -> Data {
        var data = Data()
        data.appendUUID(series.id)
        data.appendDouble(series.start.timeIntervalSince1970)
        data.appendDouble(series.end.timeIntervalSince1970)
        data.appendUInt32(UInt32(series.beats.count))
        for beat in series.beats {
            data.appendDouble(beat.t)
            data.append(beat.precededByGap ? 1 : 0)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> HeartbeatSeries {
        var reader = ByteReader(data: data)
        let id = try reader.readUUID()
        let start = try reader.readDouble()
        let end = try reader.readDouble()
        let count = try reader.readUInt32()
        var beats: [Beat] = []
        beats.reserveCapacity(Int(count))
        for _ in 0..<count {
            let t = try reader.readDouble()
            let gap = try reader.readUInt8()
            beats.append(Beat(t: t, precededByGap: gap != 0))
        }
        return HeartbeatSeries(
            id: id,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            beats: beats
        )
    }
}

/// 以 HK UUID 为键的心跳序列文件缓存。删除事件到来时调用 `remove`。
public actor HeartbeatCache {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 默认位置：`Application Support/HeartbeatCache/`。
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("HeartbeatCache", isDirectory: true)
    }

    public func contains(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    public func load(_ id: UUID) throws -> HeartbeatSeries? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try HeartbeatCodec.decode(Data(contentsOf: url))
    }

    public func store(_ series: HeartbeatSeries) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try HeartbeatCodec.encode(series).write(to: fileURL(for: series.id), options: .atomic)
    }

    public func remove(_ id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("hbc")
    }
}

private struct ByteReader {
    let data: Data
    var offset = 0

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else { throw HeartbeatCodec.DecodingError.truncated }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func readDouble() throws -> Double {
        let bits = try readBytes(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Double(bitPattern: bits)
    }

    mutating func readUUID() throws -> UUID {
        let b = try readBytes(16)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    private mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else { throw HeartbeatCodec.DecodingError.truncated }
        let start = data.startIndex + offset
        offset += count
        return Array(data[start..<(start + count)])
    }
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func appendDouble(_ value: Double) {
        let bits = value.bitPattern
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
        }
    }

    mutating func appendUUID(_ id: UUID) {
        Swift.withUnsafeBytes(of: id.uuid) { append(contentsOf: $0) }
    }
}
