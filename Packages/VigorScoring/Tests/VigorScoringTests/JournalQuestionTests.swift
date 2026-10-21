import Foundation
import Testing
@testable import VigorScoring

@Suite("日志题目与自动填充")
struct JournalQuestionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    /// 醒来日 2026-10-21 的零点；统计的是 10-20 当天。
    private var night: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
    }

    private func at(_ hour: Int, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test("默认题目与 PRD §6.5 一致，标识唯一，且不包含“不适”（由单独开关确认）")
    func defaultsMatchPRD() {
        let defaults = JournalQuestion.defaults
        #expect(defaults.count == 9)
        #expect(Set(defaults.map(\.id)).count == defaults.count)
        #expect(defaults.first?.id == "alcohol")
        #expect(!defaults.contains { $0.id == "unwell" })
    }

    @Test("题目列表的编解码往返保持顺序、题型与单位")
    func questionCodecRoundTrip() throws {
        let questions = [
            JournalQuestion(id: "alcohol", title: "饮酒"),
            JournalQuestion(id: "water", title: "饮水", kind: .quantity(unit: "杯")),
        ]
        let data = try JournalQuestion.encode(questions)
        let decoded = try JournalQuestion.decode(data)
        #expect(decoded == questions)
        #expect(decoded.map(\.id) == ["alcohol", "water"])
        if case let .quantity(unit) = decoded[1].kind {
            #expect(unit == "杯")
        } else {
            Issue.record("数量题的题型丢失")
        }
    }

    @Test("旧版本的日志记录（没有 quantities 字段）仍可解码，数量为空")
    func legacyEntryDecodes() throws {
        let json = """
        {"night": 800000000, "behaviors": {"alcohol": true}, "energy": 3, "feltUnwell": false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let entry = try decoder.decode(JournalEntry.self, from: Data(json.utf8))
        #expect(entry.behaviors == ["alcohol": true])
        #expect(entry.quantities.isEmpty)
        #expect(entry.energy == 3)
        #expect(entry.feltUnwell == false)
    }

    @Test("自动填充：统计醒来日前一天的样本，没有记录的指标为空")
    func autoFillUsesPreviousDay() {
        let snapshot = HealthSnapshot(
            exportedAt: at(8),
            rangeStart: at(0, day: 1),
            rangeEnd: at(8, day: 21),
            profile: UserProfile(birthYear: nil, sex: .unknown),
            sleep: [],
            heartRate: [],
            hrvSDNN: [],
            restingHeartRate: [],
            respiratoryRate: [],
            wristTemperature: [],
            oxygenSaturation: [],
            heartbeatSeries: [],
            mindfulSessions: [
                ValueSample(start: at(9), end: at(9).addingTimeInterval(600), value: 600),
                ValueSample(start: at(20), end: at(20).addingTimeInterval(300), value: 300),
                // 醒来日当天的样本不计入“昨天”
                ValueSample(start: at(9, day: 21), end: at(9, day: 21).addingTimeInterval(600), value: 600),
            ],
            timeInDaylight: [ValueSample(start: at(12), end: at(12), value: 42)],
            dietaryCaffeine: [
                ValueSample(start: at(8), end: at(8), value: 95),
                ValueSample(start: at(15), end: at(15), value: 80),
            ],
            alcoholicBeverages: [],
            stateOfMind: [
                StateOfMindSample(date: at(22), valence: 0.5, labels: []),
                StateOfMindSample(date: at(10), valence: -0.5, labels: []),
            ]
        )
        let fill = JournalAutoFill.summarize(snapshot, night: night, calendar: calendar)
        #expect(fill.caffeineMilligrams == 175)
        #expect(fill.mindfulMinutes == 15)
        #expect(fill.daylightMinutes == 42)
        #expect(fill.alcoholicDrinks == nil)
        #expect(fill.meanMoodValence == 0)
        #expect(fill.moodCount == 2)
    }

    @Test("没有快照时全部为空")
    func autoFillWithoutSnapshot() {
        let fill = JournalAutoFill.summarize(nil, night: night, calendar: calendar)
        #expect(fill == JournalAutoFill())
    }
}
