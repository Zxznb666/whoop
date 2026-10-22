import Foundation
import Testing
import VigorFIT
@testable import VigorScoring

@Suite("FTP 历史、EF 趋势与 20 分钟功率变化（M6 补完 C4）")
struct FTPHistoryTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()
    let origin = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 GMT（周四）

    func day(_ offset: Double) -> Date {
        origin.addingTimeInterval(offset * 86_400)
    }

    func ride(end: Date, best20: Double? = nil, ef: Double? = nil) -> RideResult {
        RideResult(
            id: "r-\(end.timeIntervalSince1970)", start: end.addingTimeInterval(-3600), end: end,
            sourceLabels: [], memberCount: 1, movingSeconds: 3600, heartRateOrigin: nil, powerSource: .healthKit,
            powerCoverage: 1, normalizedPower: nil, intensityFactor: nil, tss: nil, mechanicalWorkKJ: nil,
            wattsPerKilogram: nil, averageHeartRate: nil, efficiencyFactor: ef, aerobicDecoupling: nil,
            zoneSeconds: nil, powerCurve: best20.map { [1200: $0] } ?? [:],
            compensatedMinutes: 0, loadMayBeUnderestimated: false, measuredTRIMP: 0
        )
    }

    @Test("只有一次骑行（第 0 天最佳 20 分钟 280 W）：第 0 到 90 天为 266 W，之后为 nil")
    func estimatedWindow() throws {
        let rides = [ride(end: day(0), best20: 280)]
        let onDay0 = FTPHistory.resolve(at: day(0), rides: rides, healthKitFTP: [], manual: [], calendar: calendar)
        #expect(onDay0.watts == 266)
        #expect(onDay0.source == .estimated)
        let onDay90 = FTPHistory.resolve(at: day(90), rides: rides, healthKitFTP: [], manual: [], calendar: calendar)
        #expect(onDay90.watts == 266)
        let onDay91 = FTPHistory.resolve(at: day(91), rides: rides, healthKitFTP: [], manual: [], calendar: calendar)
        #expect(onDay91.watts == nil)
        #expect(onDay91.source == nil)
    }

    @Test("手动设置从第 30 天开始为 250，来源为“手动”")
    func manualFromDay30() {
        let rides = [ride(end: day(0), best20: 280)]
        let manual = [ManualFTPEntry(date: day(30), watts: 250)]
        let before = FTPHistory.resolve(at: day(29), rides: rides, healthKitFTP: [], manual: manual, calendar: calendar)
        #expect(before.watts == 266)
        let after = FTPHistory.resolve(at: day(30), rides: rides, healthKitFTP: [], manual: manual, calendar: calendar)
        #expect(after.watts == 250)
        #expect(after.source == .manual)
    }

    @Test("清除手动值（记录为 nil）后，回到自动估算")
    func clearedManualFallsBack() {
        let rides = [ride(end: day(0), best20: 280)]
        let manual = [ManualFTPEntry(date: day(30), watts: 250), ManualFTPEntry(date: day(40), watts: nil)]
        let cleared = FTPHistory.resolve(at: day(41), rides: rides, healthKitFTP: [], manual: manual, calendar: calendar)
        #expect(cleared.watts == 266)
        #expect(cleared.source == .estimated)
    }

    @Test("HealthKit 样本在第 60 天为 270、没有手动值：第 60 天起为 270")
    func healthKitFromDay60() {
        let rides = [ride(end: day(0), best20: 280)]
        let samples = [ValueSample(start: day(60), end: day(60), value: 270)]
        let before = FTPHistory.resolve(at: day(59), rides: rides, healthKitFTP: samples, manual: [], calendar: calendar)
        #expect(before.watts == 266)
        let after = FTPHistory.resolve(at: day(60), rides: rides, healthKitFTP: samples, manual: [], calendar: calendar)
        #expect(after.watts == 270)
        #expect(after.source == .healthKit)
    }

    @Test("历史点为周一 00:00，覆盖约 365 天")
    func weeklyMondays() {
        let now = day(200)
        let points = FTPHistory.make(rides: [], healthKitFTP: [], manual: [], now: now, calendar: calendar)
        #expect(points.count >= 52)
        #expect(points.allSatisfy { calendar.component(.weekday, from: $0.date) == 2 })
        #expect(points.allSatisfy { $0.date <= now })
        #expect(points.allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
        #expect(points.last.map { now.timeIntervalSince($0.date) < 7 * 86_400 } == true)
    }

    @Test("EF 从第 0 天的 1.40 线性增长到第 90 天的 1.49：斜率 0.001 / 天")
    func efficiencySlope() throws {
        let rides = (0...9).map { step -> RideResult in
            let offset = Double(step * 10)
            return ride(end: day(offset), ef: 1.40 + 0.001 * offset)
        }
        let slope = try #require(CyclingTrends.efficiencySlopePerDay(rides: rides, now: day(90), calendar: calendar))
        #expect(abs(slope - 0.001) < 1e-9)
    }

    @Test("EF 数据不足（少于 3 次）时没有斜率")
    func efficiencySlopeNeedsThreePoints() {
        let rides = [ride(end: day(0), ef: 1.4), ride(end: day(10), ef: 1.45)]
        #expect(CyclingTrends.efficiencySlopePerDay(rides: rides, now: day(90), calendar: calendar) == nil)
    }

    @Test("最佳 20 分钟功率：本期 90 天 264 W，上期 90 天 240 W")
    func twentyMinuteChange() throws {
        let rides = [ride(end: day(45), best20: 240), ride(end: day(135), best20: 264)]
        let change = try #require(CyclingTrends.bestTwentyMinuteChange(rides: rides, now: day(180), calendar: calendar))
        #expect(change.current == 264)
        #expect(change.previous == 240)
    }
}
