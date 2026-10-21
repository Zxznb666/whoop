import Foundation
import Testing
@testable import VigorEngine

@Suite("日志提醒")
struct JournalReminderTests {
    private let calendar = shanghaiCalendar()
    private let wake = shanghaiDate(2026, 10, 21, 7)
    private var night: Date { calendar.startOfDay(for: wake) }

    @Test("醒来后未填写日志：发出一条提醒，触发时间在醒来 30 分钟之后")
    func remindsWhenNotJournaled() {
        let planned = NotificationPlanner.journalReminder(
            latestWake: wake,
            journaledNights: [],
            sent: [],
            now: wake.addingTimeInterval(60),
            calendar: calendar
        )
        #expect(planned.count == 1)
        #expect(planned.first?.kind == .journalReminder)
        #expect(planned.first?.identifier == "journalReminder-\(Int(wake.timeIntervalSince1970))")
        #expect(planned.first?.fireDate == wake.addingTimeInterval(30 * 60))
    }

    @Test("当天已经填写日志：不发")
    func silentWhenJournaled() {
        let planned = NotificationPlanner.journalReminder(
            latestWake: wake,
            journaledNights: [night],
            sent: [],
            now: wake.addingTimeInterval(60),
            calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test("已经发过的提醒不再发")
    func silentWhenAlreadySent() {
        let identifier = "journalReminder-\(Int(wake.timeIntervalSince1970))"
        let planned = NotificationPlanner.journalReminder(
            latestWake: wake,
            journaledNights: [],
            sent: [identifier],
            now: wake.addingTimeInterval(60),
            calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test("醒来超过 12 小时：不发（晚上同步时不提醒“昨天”的问卷）")
    func silentAfterWindow() {
        let planned = NotificationPlanner.journalReminder(
            latestWake: wake,
            journaledNights: [],
            sent: [],
            now: wake.addingTimeInterval(12 * 3600 + 1),
            calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test("没有任何周期时不发")
    func silentWithoutCycles() {
        let planned = NotificationPlanner.journalReminder(
            latestWake: nil,
            journaledNights: [],
            sent: [],
            now: wake,
            calendar: calendar
        )
        #expect(planned.isEmpty)
    }
}
