import Foundation
@testable import VigorFIT

/// 测试用 FIT 编码器：用于往返测试与生成端到端的骑行样例。
/// 可选：压缩时间戳头、开发者字段、大端定义、14 字节头（含头 CRC）。
struct FITEncoderOptions {
    var compressedTimestamps = false
    var bigEndian = false
    var developerFields = false
    var headerCRC = false
}

enum FITTestEncoder {
    static func encode(_ activity: FITActivity, _ options: FITEncoderOptions = FITEncoderOptions()) -> Data {
        var writer = Writer(bigEndian: options.bigEndian)

        writer.emit(header: 0, local: 0, global: 0, developerFields: false, fields: [
            F(1, 2, 4, activity.fileID.manufacturer.map(UInt64.init)),
            F(2, 2, 4, activity.fileID.product.map(UInt64.init)),
            F(3, 4, 12, activity.fileID.serialNumber.map(UInt64.init)),
            F(4, 4, 6, activity.fileID.timeCreated.map { UInt64(fitTime($0)) }),
        ])

        for event in activity.timerEvents {
            let time = fitTime(event.time)
            writer.emit(header: 1, local: 1, global: 21, developerFields: false, fields: [
                F(253, 4, 6, UInt64(time)),
                F(0, 1, 0, 0),
                F(1, 1, 0, event.isStart ? 0 : 4),
            ])
            writer.last = time
        }

        for session in activity.sessions {
            writer.emit(header: 4, local: 4, global: 18, developerFields: false, fields: [
                F(2, 4, 6, session.startTime.map { UInt64(fitTime($0)) }),
                F(5, 1, 0, session.sport.map(UInt64.init)),
                F(7, 4, 6, session.totalElapsedSeconds.map { UInt64(($0 * 1000).rounded()) }),
                F(9, 4, 6, session.totalDistance.map { UInt64(($0 * 100).rounded()) }),
            ])
        }

        for lap in activity.laps {
            let end = lap.endTime.map(fitTime)
            writer.emit(header: 5, local: 5, global: 19, developerFields: false, fields: [
                F(2, 4, 6, lap.startTime.map { UInt64(fitTime($0)) }),
                F(253, 4, 6, end.map(UInt64.init)),
            ])
            if let end { writer.last = end }
        }

        for record in activity.records {
            let time = fitTime(record.timestamp)
            let fields = recordFields(record)
            if options.compressedTimestamps, let last = writer.last, time >= last, time - last < 32 {
                writer.emit(header: 0x80 | (3 << 5) | UInt8(time & 0x1F), local: 3, global: 20,
                            developerFields: options.developerFields, fields: fields)
            } else {
                writer.emit(header: 2, local: 2, global: 20, developerFields: options.developerFields,
                            fields: [F(253, 4, 6, UInt64(time))] + fields)
            }
            writer.last = time
        }

        let headerSize: UInt8 = options.headerCRC ? 14 : 12
        var header: [UInt8] = [headerSize, 0x20, 0x54, 0x08]
        header += littleEndian32(UInt32(writer.body.count))
        header += Array(".FIT".utf8)
        if options.headerCRC {
            header += littleEndian16(FITCRCForTests.compute(header))
        }
        var file = header + writer.body
        file += littleEndian16(FITCRCForTests.compute(file))
        return Data(file)
    }

    /// 合成样例：包含压缩时间戳会用到的 1 秒连续采样、一次 40 秒的间隔、若干无效值和一次暂停。
    static func sampleActivity() -> FITActivity {
        let start = Date(timeIntervalSince1970: 1_767_000_000)
        var records: [FITRecord] = []
        for i in 0..<90 {
            let second = i >= 60 ? i + 40 : i
            records.append(FITRecord(
                timestamp: start.addingTimeInterval(Double(second)),
                latitude: Double(470_000_000 + i * 1000) * 180 / 2_147_483_648,
                longitude: Double(-1_220_000_000 - i * 500) * 180 / 2_147_483_648,
                altitude: 100 + Double(i) * 0.2,
                heartRate: i == 10 ? nil : 100 + i % 50,
                cadence: 80 + i % 7,
                distance: Double(i) * 8.5,
                speed: 8.5 + Double(i) * 0.01,
                power: i % 3 == 0 ? nil : 200 + i
            ))
        }
        return FITActivity(
            fileID: FITFileID(manufacturer: 1, product: 2901, serialNumber: 3_456_789, timeCreated: start),
            sessions: [FITSession(startTime: start, sport: 2, totalElapsedSeconds: 1234.567, totalDistance: 765.0)],
            laps: [FITLap(startTime: start, endTime: start.addingTimeInterval(89))],
            records: records,
            timerEvents: [
                FITTimerEvent(time: start, isStart: true),
                FITTimerEvent(time: start.addingTimeInterval(50), isStart: false),
                FITTimerEvent(time: start.addingTimeInterval(60), isStart: true),
            ]
        )
    }

    private static func recordFields(_ record: FITRecord) -> [F] {
        [
            F(0, 4, 5, record.latitude.map { UInt64(UInt32(bitPattern: Int32((($0 * 2_147_483_648) / 180).rounded()))) }),
            F(1, 4, 5, record.longitude.map { UInt64(UInt32(bitPattern: Int32((($0 * 2_147_483_648) / 180).rounded()))) }),
            F(2, 2, 4, record.altitude.map { UInt64(((($0 + 500) * 5).rounded())) }),
            F(78, 4, 6, record.altitude.map { UInt64((($0 + 500) * 5).rounded()) }),
            F(3, 1, 2, record.heartRate.map(UInt64.init)),
            F(4, 1, 2, record.cadence.map(UInt64.init)),
            F(5, 4, 6, record.distance.map { UInt64(($0 * 100).rounded()) }),
            F(6, 2, 4, record.speed.map { UInt64(($0 * 1000).rounded()) }),
            F(73, 4, 6, record.speed.map { UInt64(($0 * 1000).rounded()) }),
            F(7, 2, 4, record.power.map(UInt64.init)),
        ]
    }

    static func fitTime(_ date: Date) -> UInt32 {
        UInt32(date.timeIntervalSince1970 - FITDecoder.epochOffset)
    }

    private static func littleEndian16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    private static func littleEndian32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }
}

/// 字段规格：编号、字节数、基本类型，以及取值（nil 写入无效值）。
struct F {
    var number: UInt8
    var size: Int
    var baseType: UInt8
    var value: UInt64?

    init(_ number: UInt8, _ size: Int, _ baseType: UInt8, _ value: UInt64?) {
        self.number = number
        self.size = size
        self.baseType = baseType
        self.value = value
    }
}

private struct Writer {
    var body: [UInt8] = []
    var bigEndian: Bool
    var last: UInt32?
    var defined: Set<UInt8> = []

    init(bigEndian: Bool) {
        self.bigEndian = bigEndian
    }

    /// 首次使用某个本地类型时先写定义消息；之后同一本地类型的数据消息沿用该定义。
    mutating func emit(header: UInt8, local: UInt8, global: UInt16, developerFields: Bool, fields: [F]) {
        if !defined.contains(local) {
            defined.insert(local)
            body.append(0x40 | (developerFields ? 0x20 : 0) | local)
            body.append(0)
            body.append(bigEndian ? 1 : 0)
            appendUInt16(global)
            body.append(UInt8(fields.count))
            for field in fields {
                body += [field.number, UInt8(field.size), field.baseType]
            }
            if developerFields {
                body += [1, 0, 2, 0] // 1 个开发者字段：编号 0、2 字节、索引 0
            }
        }
        body.append(header)
        for field in fields {
            appendValue(field)
        }
        if developerFields {
            body += [0xAB, 0xCD] // 与定义一致的开发者数据，解码时必须跳过
        }
    }

    private mutating func appendUInt16(_ value: UInt16) {
        let high = UInt8(value >> 8), low = UInt8(value & 0xFF)
        body += bigEndian ? [high, low] : [low, high]
    }

    private mutating func appendValue(_ field: F) {
        var raw: UInt64
        if let value = field.value {
            raw = value
        } else if field.baseType == 5 {
            raw = 0x7FFF_FFFF // sint32 的无效值
        } else {
            raw = (UInt64(1) << UInt64(field.size * 8)) - 1 // 无符号类型的无效值（全 1）
        }
        var bytes: [UInt8] = []
        for _ in 0..<field.size {
            bytes.append(UInt8(raw & 0xFF))
            raw >>= 8
        }
        body += bigEndian ? bytes.reversed() : bytes
    }
}

/// 与解码器相同的 CRC-16 实现，只用于构造测试文件。
enum FITCRCForTests {
    private static let table: [UInt16] = [
        0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
        0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
    ]

    static func compute(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte & 0xF)]
            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int((byte >> 4) & 0xF)]
        }
        return crc
    }
}
