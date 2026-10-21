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

@Suite("周报推送")
struct WeeklyReportTests {
    private let calendar = shanghaiCalendar()

    @Test("周日 20:30 发送一次；同一周已发送则不再发")
    func sundayEveningOnce() {
        // 2026-10-25 是周日
        let sunday = shanghaiDate(2026, 10, 25, 20, 30)
        let planned = NotificationPlanner.weeklyReport(now: sunday, sent: [], calendar: calendar)
        #expect(planned.count == 1)
        #expect(planned.first?.kind == .weeklyReport)
        let identifier = try? #require(planned.first?.identifier)
        let again = NotificationPlanner.weeklyReport(now: sunday, sent: Set(identifier.map { [$0] } ?? []), calendar: calendar)
        #expect(again.isEmpty)
    }

    @Test("非周日、时间不在 20:00–21:59 之间：不发")
    func outsideWindowSilent() {
        #expect(NotificationPlanner.weeklyReport(now: shanghaiDate(2026, 10, 25, 19, 59), sent: [], calendar: calendar).isEmpty)
        #expect(NotificationPlanner.weeklyReport(now: shanghaiDate(2026, 10, 25, 22, 0), sent: [], calendar: calendar).isEmpty)
        #expect(NotificationPlanner.weeklyReport(now: shanghaiDate(2026, 10, 26, 20, 30), sent: [], calendar: calendar).isEmpty)
    }
}
