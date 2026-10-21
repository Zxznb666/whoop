import Foundation

/// FIT 协议解码器（自己实现，不引入第三方库；施工文档 §4.1）。
public enum FITDecoder {
    /// 解码整个文件。文件头、整体 CRC 任一校验失败都会抛出 `FITError`。
    public static func decode(_ data: Data) throws -> FITActivity {
        let bytes = [UInt8](data)
        guard bytes.count >= 14 else { throw FITError.truncated }
        let headerSize = Int(bytes[0])
        guard headerSize == 12 || headerSize == 14 else { throw FITError.invalidHeader }
        guard bytes[8..<12].elementsEqual(Array(".FIT".utf8)) else { throw FITError.invalidHeader }
        let dataSize = Int(readUInt32LE(bytes, 4))
        if headerSize == 14 {
            let stored = readUInt16LE(bytes, 12)
            if stored != 0, FITCRC.compute(bytes[0..<12]) != stored {
                throw FITError.headerCRCMismatch
            }
        }
        let dataEnd = headerSize + dataSize
        guard dataEnd + 2 <= bytes.count else { throw FITError.truncated }
        guard FITCRC.compute(bytes[0..<dataEnd]) == readUInt16LE(bytes, dataEnd) else {
            throw FITError.crcMismatch
        }
        var reader = FITReader(bytes: bytes, pos: headerSize, end: dataEnd)
        return try reader.readAll()
    }

    /// FIT 纪元（1989-12-31 00:00:00 UTC）与 Unix 纪元之间相差的秒数。
    static let epochOffset: Double = 631_065_600

    static func date(fromFIT seconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(seconds) + epochOffset)
    }
}

private struct FieldDefinition {
    var number: UInt8
    var size: Int
    var baseType: UInt8
}

private struct MessageDefinition {
    var bigEndian: Bool
    var globalNumber: UInt16
    var fields: [FieldDefinition]
    var developerSize: Int
}

/// 逐条读取记录；压缩时间戳头需要记住上一个完整时间戳。
private struct FITReader {
    let bytes: [UInt8]
    var pos: Int
    let end: Int
    var definitions: [UInt8: MessageDefinition] = [:]
    var lastTimestamp: UInt32?
    var activity = FITActivity(fileID: FITFileID(), sessions: [], laps: [], records: [], timerEvents: [])

    init(bytes: [UInt8], pos: Int, end: Int) {
        self.bytes = bytes
        self.pos = pos
        self.end = end
    }

    mutating func readAll() throws -> FITActivity {
        while pos < end {
            let header = try readByte()
            if header & 0x80 != 0 {
                // 压缩时间戳头：bit5–6 为本地类型，bit0–4 为时间偏移。
                let local = (header >> 5) & 0x03
                let offset = UInt32(header & 0x1F)
                guard let last = lastTimestamp else {
                    throw FITError.corrupt("压缩时间戳出现在第一个时间戳之前")
                }
                var timestamp = (last & ~0x1F) + offset
                if offset < (last & 0x1F) { timestamp += 0x20 }
                lastTimestamp = timestamp
                try readData(local: local, compressedTimestamp: timestamp)
            } else if header & 0x40 != 0 {
                try readDefinition(local: header & 0x0F, hasDeveloperFields: header & 0x20 != 0)
            } else {
                try readData(local: header & 0x0F, compressedTimestamp: nil)
            }
        }
        return activity
    }

    private mutating func readByte() throws -> UInt8 {
        guard pos < end else { throw FITError.truncated }
        defer { pos += 1 }
        return bytes[pos]
    }

    private mutating func readDefinition(local: UInt8, hasDeveloperFields: Bool) throws {
        _ = try readByte() // 保留字节
        let bigEndian = try readByte() == 1
        let g0 = try readByte(), g1 = try readByte()
        let global = bigEndian ? (UInt16(g0) << 8 | UInt16(g1)) : (UInt16(g1) << 8 | UInt16(g0))
        let count = Int(try readByte())
        var fields: [FieldDefinition] = []
        for _ in 0..<count {
            fields.append(FieldDefinition(number: try readByte(), size: Int(try readByte()), baseType: try readByte()))
        }
        var developerSize = 0
        if hasDeveloperFields {
            // 开发者字段只跳过：每个定义 3 字节（字段号、大小、索引）。
            let devCount = Int(try readByte())
            for _ in 0..<devCount {
                _ = try readByte()
                developerSize += Int(try readByte())
                _ = try readByte()
            }
        }
        definitions[local] = MessageDefinition(
            bigEndian: bigEndian, globalNumber: global, fields: fields, developerSize: developerSize
        )
    }

    private mutating func readData(local: UInt8, compressedTimestamp: UInt32?) throws {
        guard let definition = definitions[local] else {
            throw FITError.corrupt("本地类型 \(local) 没有定义")
        }
        var values: [UInt8: Int64] = [:]
        for field in definition.fields {
            guard pos + field.size <= end else { throw FITError.truncated }
            if let value = scalar(at: pos, size: field.size, baseType: field.baseType, bigEndian: definition.bigEndian) {
                values[field.number] = value
            }
            pos += field.size
        }
        guard pos + definition.developerSize <= end else { throw FITError.truncated }
        pos += definition.developerSize

        var timestamp = compressedTimestamp
        if compressedTimestamp == nil, let explicit = values[253] {
            timestamp = UInt32(truncatingIfNeeded: explicit)
            lastTimestamp = timestamp
        }
        apply(globalNumber: definition.globalNumber, values: values, timestamp: timestamp)
    }

    private mutating func apply(globalNumber: UInt16, values: [UInt8: Int64], timestamp: UInt32?) {
        switch globalNumber {
        case 0: // file_id
            activity.fileID = FITFileID(
                manufacturer: values[1].map(Int.init),
                product: values[2].map(Int.init),
                serialNumber: values[3].map { UInt32(truncatingIfNeeded: $0) },
                timeCreated: values[4].map { FITDecoder.date(fromFIT: $0) }
            )
        case 18: // session
            activity.sessions.append(FITSession(
                startTime: values[2].map { FITDecoder.date(fromFIT: $0) },
                sport: values[5].map(Int.init),
                totalElapsedSeconds: values[7].map { Double($0) / 1000 },
                totalDistance: values[9].map { Double($0) / 100 }
            ))
        case 19: // lap
            activity.laps.append(FITLap(
                startTime: values[2].map { FITDecoder.date(fromFIT: $0) },
                endTime: timestamp.map { FITDecoder.date(fromFIT: Int64($0)) }
            ))
        case 20: // record
            guard let timestamp else { return }
            activity.records.append(record(values: values, timestamp: timestamp))
        case 21: // event：计时器的开始 / 停止（事件 0 为计时器；类型 0 开始，1 或 4 停止）
            guard let timestamp, values[0] == 0 else { return }
            if values[1] == 0 {
                activity.timerEvents.append(FITTimerEvent(time: FITDecoder.date(fromFIT: Int64(timestamp)), isStart: true))
            } else if values[1] == 1 || values[1] == 4 {
                activity.timerEvents.append(FITTimerEvent(time: FITDecoder.date(fromFIT: Int64(timestamp)), isStart: false))
            }
        default:
            break
        }
    }

    private func record(values: [UInt8: Int64], timestamp: UInt32) -> FITRecord {
        // 增强字段（73 速度、78 海拔）优先于普通字段（6、2）。
        let altitudeRaw = values[78] ?? values[2]
        let speedRaw = values[73] ?? values[6]
        return FITRecord(
            timestamp: FITDecoder.date(fromFIT: Int64(timestamp)),
            latitude: values[0].map { Double($0) * 180 / 2_147_483_648 },
            longitude: values[1].map { Double($0) * 180 / 2_147_483_648 },
            altitude: altitudeRaw.map { Double($0) / 5 - 500 },
            heartRate: values[3].map(Int.init),
            cadence: values[4].map(Int.init),
            distance: values[5].map { Double($0) / 100 },
            speed: speedRaw.map { Double($0) / 1000 },
            power: values[7].map(Int.init)
        )
    }

    /// 读取一个标量（数组字段只取第一个元素）。无效值与字符串、浮点数返回 nil。
    private func scalar(at offset: Int, size: Int, baseType: UInt8, bigEndian: Bool) -> Int64? {
        let type = baseType & 0x1F
        let elementSize: Int
        let signed: Bool
        let invalid: UInt64
        switch type {
        case 0, 2, 13: (elementSize, signed, invalid) = (1, false, 0xFF)           // enum / uint8 / byte
        case 1: (elementSize, signed, invalid) = (1, true, 0x7F)                    // sint8
        case 3: (elementSize, signed, invalid) = (2, true, 0x7FFF)                  // sint16
        case 4: (elementSize, signed, invalid) = (2, false, 0xFFFF)                 // uint16
        case 5: (elementSize, signed, invalid) = (4, true, 0x7FFF_FFFF)             // sint32
        case 6: (elementSize, signed, invalid) = (4, false, 0xFFFF_FFFF)            // uint32
        case 10: (elementSize, signed, invalid) = (1, false, 0)                     // uint8z
        case 11: (elementSize, signed, invalid) = (2, false, 0)                     // uint16z
        case 12: (elementSize, signed, invalid) = (4, false, 0)                     // uint32z
        case 14: (elementSize, signed, invalid) = (8, true, 0x7FFF_FFFF_FFFF_FFFF)  // sint64
        case 15: (elementSize, signed, invalid) = (8, false, UInt64.max)            // uint64
        case 16: (elementSize, signed, invalid) = (8, false, 0)                     // uint64z
        default: return nil                                                         // 字符串、浮点数
        }
        guard size >= elementSize else { return nil }
        var raw: UInt64 = 0
        for i in 0..<elementSize {
            let byte = bigEndian ? bytes[offset + i] : bytes[offset + elementSize - 1 - i]
            raw = raw << 8 | UInt64(byte)
        }
        if raw == invalid { return nil }
        if signed {
            let shift = UInt64(64 - elementSize * 8)
            return Int64(bitPattern: raw << shift) >> shift
        }
        return Int64(truncatingIfNeeded: raw)
    }
}

private func readUInt16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
}

private func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(readUInt16LE(bytes, offset)) | UInt32(readUInt16LE(bytes, offset + 2)) << 16
}
