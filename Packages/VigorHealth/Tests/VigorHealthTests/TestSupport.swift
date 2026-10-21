import Foundation
import VigorScoring
@testable import VigorHealth

/// 测试统一使用 Asia/Shanghai，避免受本机时区影响。
func shanghaiCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

/// 默认的合成快照：2026-10-21 结束，共 30 晚。
func defaultSyntheticSnapshot(seed: UInt64 = 42) -> HealthSnapshot {
    SyntheticSnapshot.make(
        nights: 30,
        seed: seed,
        endingAt: shanghaiDate(2026, 10, 21, 12),
        calendar: shanghaiCalendar()
    )
}

func shanghaiDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return shanghaiCalendar().date(from: components)!
}
