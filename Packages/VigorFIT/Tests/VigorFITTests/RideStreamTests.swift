import Foundation
import Testing
@testable import VigorFIT

@Suite("逐秒骑行数据")
struct RideStreamTests {
    @Test("逐秒数组对齐到会话开始时间，缺失为 nil，时长与记录范围一致")
    func streamIsAlignedToSessionStart() throws {
        let activity = try FITDecoder.decode(FITTestEncoder.encode(FITTestEncoder.sampleActivity()))
        let stream = try #require(RideStream.make(from: activity))
        #expect(stream.start == activity.sessions[0].startTime)
        #expect(stream.durationSeconds == 130) // 最后一条记录位于第 129 秒
        #expect(stream.heartRate[0] == 100)
        #expect(stream.heartRate[10] == nil)
        #expect(stream.power[0] == nil)
        #expect(stream.power[1] == 201)
        #expect(stream.heartRate[70] == nil) // 第 60–99 秒之间是采样间隔，没有记录
        #expect(stream.heartRate[100] == 100 + 60 % 50)
        #expect(stream.heartRate[105] == 100 + 65 % 50)
    }

    @Test("暂停区间来自计时器的停止与开始事件")
    func pausesFromTimerEvents() throws {
        let activity = try FITDecoder.decode(FITTestEncoder.encode(FITTestEncoder.sampleActivity()))
        let stream = try #require(RideStream.make(from: activity))
        #expect(stream.pauses == [50..<60])
    }

    @Test("结束时仍未恢复的暂停延伸到末尾")
    func openPauseExtendsToEnd() throws {
        var activity = FITTestEncoder.sampleActivity()
        activity.timerEvents = [
            FITTimerEvent(time: activity.records[0].timestamp, isStart: true),
            FITTimerEvent(time: activity.records[0].timestamp.addingTimeInterval(80), isStart: false),
        ]
        let stream = try #require(RideStream.make(from: activity))
        #expect(stream.pauses == [80..<130])
    }

    @Test("没有采样点时不生成")
    func emptyActivityProducesNoStream() {
        let activity = FITActivity(fileID: FITFileID(), sessions: [], laps: [], records: [], timerEvents: [])
        #expect(RideStream.make(from: activity) == nil)
    }

    @Test("导入同一文件两次得到相同的去重标识")
    func fileIdentityIsStable() throws {
        let a = try FITDecoder.decode(FITTestEncoder.encode(FITTestEncoder.sampleActivity()))
        let b = try FITDecoder.decode(FITTestEncoder.encode(FITTestEncoder.sampleActivity(), FITEncoderOptions(compressedTimestamps: true)))
        #expect(a.fileID.identity == b.fileID.identity)
        #expect(a.fileID.identity == "3456789-1767000000")
    }
}
