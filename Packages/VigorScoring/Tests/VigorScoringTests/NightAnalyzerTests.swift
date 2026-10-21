import Foundation
import Testing
@testable import VigorScoring

@Suite("NightAnalyzer")
struct NightAnalyzerTests {
    private func series(start: Date, rr: [Double], id: UUID = UUID()) -> HeartbeatSeries {
        var beats = [Beat(t: 0, precededByGap: false)]
        var time: TimeInterval = 0
        for interval in rr {
            time += interval / 1000
            beats.append(Beat(t: time, precededByGap: false))
        }
        return HeartbeatSeries(id: id, start: start, end: start.addingTimeInterval(time.rounded(.up)), beats: beats)
    }

    /// 23:00–07:00 的主睡眠，夜间 HR 每 5 分钟 60 bpm，一段夜间序列，醒后 20 分钟一段晨测（有正念记录）。
    private func snapshot(morningMindful: Bool = true) -> HealthSnapshot {
        let bedtime = shanghaiDate(2026, 10, 21, 23)
        let wake = shanghaiDate(2026, 10, 22, 7)
        let rr = (0..<61).map { $0 % 2 == 0 ? 1000.0 : 1020.0 }
        let heartRate = stride(from: bedtime, to: wake, by: 300).map { HeartRateSample(date: $0, bpm: 60) }
        let mindful = morningMindful
            ? [ValueSample(start: wake.addingTimeInterval(1200), end: wake.addingTimeInterval(1320), value: 1)]
            : []
        return HealthSnapshot(
            exportedAt: wake,
            rangeStart: bedtime,
            rangeEnd: wake,
            profile: UserProfile(birthYear: nil, sex: .unknown),
            sleep: [SleepStageSample(start: bedtime, end: wake, stage: .core, sourceIsWatch: true)],
            heartRate: heartRate,
            hrvSDNN: [],
            restingHeartRate: [],
            respiratoryRate: [],
            wristTemperature: [],
            oxygenSaturation: [],
            heartbeatSeries: [
                series(start: bedtime.addingTimeInterval(3600), rr: rr),
                series(start: wake.addingTimeInterval(1200), rr: rr),
            ],
            mindfulSessions: mindful
        )
    }

    @Test("一晚一段主睡眠：夜间得到 RMSSD，醒后的晨测归入当晚")
    func oneNight() throws {
        let nights = NightAnalyzer.analyze(snapshot(), calendar: shanghaiCalendar())
        let night = try #require(nights.first)
        #expect(nights.count == 1)
        #expect(night.hrv.nightValidCount == 1)
        #expect(night.hrv.morningValidCount == 1)
        #expect(night.hrv.nightRMSSD != nil)
        #expect(night.hrv.morningRMSSD != nil)
        #expect(night.windows.count == 2)
        #expect(!night.partialWear)
    }

    @Test("没有正念记录的醒后序列被忽略")
    func morningWithoutMindfulIgnored() throws {
        let night = try #require(NightAnalyzer.analyze(snapshot(morningMindful: false), calendar: shanghaiCalendar()).first)
        #expect(night.hrv.morningRMSSD == nil)
        #expect(night.windows.count == 1)
    }

    @Test("心率点之间超过 60 分钟没有数据 → 部分未佩戴")
    func partialWear() throws {
        var snap = snapshot()
        snap.heartRate = snap.heartRate.filter { $0.date < shanghaiDate(2026, 10, 22, 0, 30) }
        let night = try #require(NightAnalyzer.analyze(snap, calendar: shanghaiCalendar()).first)
        #expect(night.partialWear)
    }

    @Test("夜间静息心率：样本池中的 60 bpm 与序列平均心率一起计算")
    func restingHeartRateFromNight() throws {
        let night = try #require(NightAnalyzer.analyze(snapshot(), calendar: shanghaiCalendar()).first)
        #expect(night.restingHeartRate.source == .sampledP10)
        #expect(night.restingHeartRate.value == 60)
    }
}
