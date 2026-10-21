import Foundation
import Testing
@testable import VigorFIT

@Suite("FIT 解码器")
struct FITDecoderTests {
    @Test("CRC-16 与标准检查值一致（123456789 → 0xBB3D）")
    func crcCheckValue() {
        #expect(FITCRC.compute(Array("123456789".utf8)) == 0xBB3D)
    }

    @Test("往返：全部编码选项组合下解码结果与原始数据逐字段相等")
    func roundTripAllOptions() throws {
        let original = FITTestEncoder.sampleActivity()
        for bits in 0..<16 {
            let options = FITEncoderOptions(
                compressedTimestamps: bits & 1 != 0,
                bigEndian: bits & 2 != 0,
                developerFields: bits & 4 != 0,
                headerCRC: bits & 8 != 0
            )
            let decoded = try FITDecoder.decode(FITTestEncoder.encode(original, options))
            expectSameActivity(decoded, original)
        }
    }

    @Test("压缩时间戳头确实被使用（编码结果更短）")
    func compressedHeadersAreUsed() {
        let original = FITTestEncoder.sampleActivity()
        let plain = FITTestEncoder.encode(original)
        let compressed = FITTestEncoder.encode(original, FITEncoderOptions(compressedTimestamps: true))
        #expect(compressed.count < plain.count)
    }

    @Test("无效值解码为 nil（心率 uint8 0xFF、功率 uint16 0xFFFF、sint32 0x7FFFFFFF）")
    func invalidValuesAreNil() throws {
        let decoded = try FITDecoder.decode(FITTestEncoder.encode(FITTestEncoder.sampleActivity()))
        #expect(decoded.records[10].heartRate == nil)
        #expect(decoded.records[0].power == nil)
        var activity = FITTestEncoder.sampleActivity()
        activity.records[5].latitude = nil
        let roundTrip = try FITDecoder.decode(FITTestEncoder.encode(activity))
        #expect(roundTrip.records[5].latitude == nil)
    }

    @Test("改动一个字节 → CRC 校验失败")
    func flippedByteFailsCRC() {
        var bytes = [UInt8](FITTestEncoder.encode(FITTestEncoder.sampleActivity()))
        bytes[200] ^= 0x01
        #expect(throws: FITError.crcMismatch) {
            try FITDecoder.decode(Data(bytes))
        }
    }

    @Test("14 字节头中改动头部 → 头 CRC 失败")
    func flippedHeaderFailsHeaderCRC() {
        var bytes = [UInt8](FITTestEncoder.encode(FITTestEncoder.sampleActivity(), FITEncoderOptions(headerCRC: true)))
        bytes[5] ^= 0x01
        #expect(throws: FITError.headerCRCMismatch) {
            try FITDecoder.decode(Data(bytes))
        }
    }

    @Test("签名不是 .FIT → 头部无效")
    func badSignatureIsInvalidHeader() {
        var bytes = [UInt8](FITTestEncoder.encode(FITTestEncoder.sampleActivity()))
        bytes[8] = UInt8(ascii: "X")
        #expect(throws: FITError.invalidHeader) {
            try FITDecoder.decode(Data(bytes))
        }
    }

    @Test("截断的文件报错而不是崩溃")
    func truncatedFileThrows() {
        let bytes = [UInt8](FITTestEncoder.encode(FITTestEncoder.sampleActivity()))
        #expect(throws: FITError.truncated) {
            try FITDecoder.decode(Data(bytes.prefix(bytes.count / 2)))
        }
    }
}

/// 逐字段比较；浮点数允许 1e-6 的换算误差（厘米、毫米、半圆换算都有舍入）。
func expectSameActivity(_ a: FITActivity, _ b: FITActivity, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a.fileID == b.fileID, sourceLocation: sourceLocation)
    #expect(a.sessions.count == b.sessions.count, sourceLocation: sourceLocation)
    for (x, y) in zip(a.sessions, b.sessions) {
        #expect(x.startTime == y.startTime, sourceLocation: sourceLocation)
        #expect(x.sport == y.sport, sourceLocation: sourceLocation)
        #expect(approxEqual(x.totalElapsedSeconds, y.totalElapsedSeconds), sourceLocation: sourceLocation)
        #expect(approxEqual(x.totalDistance, y.totalDistance), sourceLocation: sourceLocation)
    }
    #expect(a.laps == b.laps, sourceLocation: sourceLocation)
    #expect(a.timerEvents == b.timerEvents, sourceLocation: sourceLocation)
    #expect(a.records.count == b.records.count, sourceLocation: sourceLocation)
    for (x, y) in zip(a.records, b.records) {
        #expect(x.timestamp == y.timestamp, sourceLocation: sourceLocation)
        #expect(approxEqual(x.latitude, y.latitude), sourceLocation: sourceLocation)
        #expect(approxEqual(x.longitude, y.longitude), sourceLocation: sourceLocation)
        #expect(approxEqual(x.altitude, y.altitude), sourceLocation: sourceLocation)
        #expect(x.heartRate == y.heartRate, sourceLocation: sourceLocation)
        #expect(x.cadence == y.cadence, sourceLocation: sourceLocation)
        #expect(approxEqual(x.distance, y.distance), sourceLocation: sourceLocation)
        #expect(approxEqual(x.speed, y.speed), sourceLocation: sourceLocation)
        #expect(x.power == y.power, sourceLocation: sourceLocation)
    }
}

private func approxEqual(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (x?, y?): abs(x - y) < 1e-6
    default: false
    }
}
