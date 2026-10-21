import Foundation
import Testing
@testable import VigorScoring

@Suite("SleepSessionBuilder")
struct SleepSessionBuilderTests {
    private let calendar = shanghaiCalendar()

    private func sample(_ start: Date, _ end: Date, _ stage: SleepStage = .core, watch: Bool = true) -> SleepStageSample {
        SleepStageSample(start: start, end: end, stage: stage, sourceIsWatch: watch)
    }

    @Test("间隔 50 分钟的两段睡眠合并为一个会话")
    func mergesWhenGapIsUnderOneHour() {
        let first = sample(shanghaiDate(2026, 10, 20, 23), shanghaiDate(2026, 10, 21, 0))
        let second = sample(shanghaiDate(2026, 10, 21, 0, 50), shanghaiDate(2026, 10, 21, 6))
        let sessions = SleepSessionBuilder.sessions(from: [first, second], calendar: calendar, config: .default)
        #expect(sessions.count == 1)
        // 23:00–00:00 为 1 小时，00:50–06:00 为 5 小时 10 分钟
        #expect(sessions[0].asleepDuration == 3600 + 5 * 3600 + 600)
    }

    @Test("间隔 2 小时的两段睡眠拆成两个会话，较长者为主睡眠")
    func splitsWhenGapIsTwoHours() throws {
        let short = sample(shanghaiDate(2026, 10, 21, 3), shanghaiDate(2026, 10, 21, 4))
        let long = sample(shanghaiDate(2026, 10, 21, 6), shanghaiDate(2026, 10, 21, 9))
        let sessions = SleepSessionBuilder.sessions(from: [short, long], calendar: calendar, config: .default)
        #expect(sessions.count == 2)
        let first = try #require(sessions.first)
        let last = try #require(sessions.last)
        #expect(first.isMain == false)
        #expect(last.isMain == true)
        #expect(last.asleepDuration == 3 * 3600)
    }

    @Test("完全重叠的两个 core 样本只计一次")
    func deduplicatesOverlap() throws {
        let a = sample(shanghaiDate(2026, 10, 21, 1), shanghaiDate(2026, 10, 21, 2))
        let b = sample(shanghaiDate(2026, 10, 21, 1), shanghaiDate(2026, 10, 21, 2))
        let sessions = SleepSessionBuilder.sessions(from: [a, b], calendar: calendar, config: .default)
        let session = try #require(sessions.first)
        #expect(session.asleepDuration == 3600)
    }

    @Test("跨零点：23:30 入睡、07:00 醒来，醒来日为次日")
    func wakeDayCrossesMidnight() throws {
        let night = sample(shanghaiDate(2026, 10, 20, 23, 30), shanghaiDate(2026, 10, 21, 7))
        let sessions = SleepSessionBuilder.sessions(from: [night], calendar: calendar, config: .default)
        let session = try #require(sessions.first)
        #expect(session.wakeDay.year == 2026)
        #expect(session.wakeDay.month == 10)
        #expect(session.wakeDay.day == 21)
    }

    @Test("只使用手表样本，丢弃 inBed")
    func ignoresPhoneAndInBedSamples() {
        let phone = sample(shanghaiDate(2026, 10, 21, 1), shanghaiDate(2026, 10, 21, 7), watch: false)
        let inBed = sample(shanghaiDate(2026, 10, 21, 1), shanghaiDate(2026, 10, 21, 7), .inBed)
        let sessions = SleepSessionBuilder.sessions(from: [phone, inBed], calendar: calendar, config: .default)
        #expect(sessions.isEmpty)
    }

    @Test("清醒样本不能作为会话的首尾")
    func awakeCannotBeBoundary() throws {
        let awake = sample(shanghaiDate(2026, 10, 20, 22, 30), shanghaiDate(2026, 10, 20, 23), .awake)
        let core = sample(shanghaiDate(2026, 10, 20, 23), shanghaiDate(2026, 10, 21, 6))
        let sessions = SleepSessionBuilder.sessions(from: [awake, core], calendar: calendar, config: .default)
        let session = try #require(sessions.first)
        #expect(session.start == shanghaiDate(2026, 10, 20, 23))
        #expect(session.stages.count == 1)
    }
}
