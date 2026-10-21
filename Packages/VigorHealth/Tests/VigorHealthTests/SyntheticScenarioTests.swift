import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("SyntheticScenario v2")
struct SyntheticScenarioTests {
    private func scenario(nights: Int = 120) -> SyntheticScenario {
        SyntheticScenario.make(nights: nights, seed: 42, endingAt: shanghaiDate(2026, 10, 1, 0), calendar: shanghaiCalendar())
    }

    @Test("相同种子与 endingAt 的场景完全相等，且日志数等于夜数")
    func deterministic() {
        let a = scenario()
        let b = scenario()
        #expect(a == b)
        #expect(a.journal.count == 120)
    }

    @Test("生病夜的手腕温度比其他夜晚高（倒数第 20、19 晚）")
    func sickNightsAreWarm() {
        let result = scenario()
        let calendar = shanghaiCalendar()
        // 温度样本的 end 是醒来时刻，按醒来日的本地日期归属
        func isSick(_ sample: ValueSample) -> Bool {
            result.truth.sickNights.contains { calendar.isDate(sample.end, inSameDayAs: $0) }
        }
        let sickValues = result.snapshot.wristTemperature.filter(isSick).map(\.value)
        let healthyValues = result.snapshot.wristTemperature.filter { !isSick($0) }.map(\.value)
        #expect(sickValues.count == 2)
        let sickMean = sickValues.reduce(0, +) / Double(sickValues.count)
        let healthyMean = healthyValues.reduce(0, +) / Double(healthyValues.count)
        #expect(sickMean - healthyMean > 0.5)
    }

    @Test("注入事件确实出现：饮酒夜、晚餐过晚夜、小睡日、未佩戴夜、训练日")
    func truthEventsPresent() {
        let result = scenario()
        #expect(result.truth.alcoholNights.count > 0)
        #expect(result.truth.lateDinnerNights.count > 0)
        #expect(result.truth.napDays.count >= 15)
        #expect(result.truth.missingNights.count == 1)
        #expect(result.truth.workoutDays.count >= 40)
        // 随机生成的训练没有写入来源；骑行训练（v3）带有来源，单独计数
        #expect(result.snapshot.workouts.filter { $0.sourceBundleID == nil }.count == result.truth.workoutDays.count)
        #expect(result.snapshot.importedRides.count > 0)
        #expect(result.snapshot.heartRateRecovery.count == result.truth.workoutDays.count)
    }

    @Test("未佩戴的夜晚没有任何睡眠或心率数据")
    func missingNightHasNoData() throws {
        let result = scenario()
        let missing = try #require(result.truth.missingNights.first)
        let nightEnd = missing.addingTimeInterval(7 * 3600)
        let nightStart = missing.addingTimeInterval(-7 * 3600)
        let sleepInside = result.snapshot.sleep.filter {
            $0.stage.isAsleep && $0.start >= nightStart && $0.end <= nightEnd
        }
        #expect(sleepInside.isEmpty)
        #expect(result.snapshot.heartbeatSeries.allSatisfy { !($0.start >= nightStart && $0.start <= nightEnd) })
    }

    @Test("多来源：每 10 晚一晚出现其他 App 的分期，且来源不是手表")
    func multiSource() {
        let result = scenario()
        let others = result.snapshot.sleep.filter { !$0.sourceIsWatch }
        #expect(others.count == result.truth.otherAppOverlapNights.count)
        #expect(others.allSatisfy { $0.productType == nil })
        #expect(result.snapshot.inBed.count == 120 - 1)
        #expect(result.snapshot.inBed.allSatisfy { $0.productType == "iPhone15,2" })
    }

    @Test("每周训练 3–4 次（按夜序号分成 7 天一周，完整的周逐周检查）")
    func workoutFrequency() {
        let nights = 70
        let result = scenario(nights: nights)
        let calendar = shanghaiCalendar()
        // 第 0 晚的醒来日 = rangeStart 之后一天
        let firstWakeDay = calendar.date(byAdding: .day, value: 1, to: result.snapshot.rangeStart)!
        var perWeek: [Int: Int] = [:]
        for day in result.truth.workoutDays {
            let index = calendar.dateComponents([.day], from: firstWakeDay, to: day).day!
            perWeek[index / 7, default: 0] += 1
        }
        let fullWeeks = nights / 7
        #expect(fullWeeks == 10)
        for week in 0..<fullWeeks {
            #expect((3...4).contains(perWeek[week] ?? 0))
        }
    }

    @Test("夜晚的心跳序列与晨测数量与 M0 规则一致（30 晚中 3 晚无序列）")
    func seriesRulesCarriedOver() {
        let result = SyntheticScenario.make(nights: 30, seed: 42, endingAt: shanghaiDate(2026, 10, 21, 12), calendar: shanghaiCalendar())
        #expect(result.truth.noSeriesNights.count == 3)
        #expect(result.truth.morningMeasurementNights.count == 6)
        #expect(result.snapshot.mindfulSessions.count == 6)
    }
}

@Suite("HeartbeatCodec 与 HeartbeatCache")
struct HeartbeatCacheTests {
    private func sampleSeries() -> HeartbeatSeries {
        HeartbeatSeries(
            id: UUID(uuid: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)),
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_000_060),
            beats: [
                Beat(t: 0, precededByGap: false),
                Beat(t: 1.0456, precededByGap: false),
                Beat(t: 7.25, precededByGap: true),
            ]
        )
    }

    @Test("二进制编码再解码后完全相等")
    func codecRoundTrip() throws {
        let series = sampleSeries()
        #expect(try HeartbeatCodec.decode(HeartbeatCodec.encode(series)) == series)
    }

    @Test("截断的数据抛出 truncated")
    func truncatedInput() {
        let data = HeartbeatCodec.encode(sampleSeries()).dropLast(3)
        #expect(throws: HeartbeatCodec.DecodingError.truncated) {
            try HeartbeatCodec.decode(Data(data))
        }
    }

    @Test("缓存的存取与删除")
    func cacheStoreLoadRemove() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigor-hb-\(UUID().uuidString)", isDirectory: true)
        let cache = HeartbeatCache(directory: directory)
        let series = sampleSeries()

        #expect(await cache.contains(series.id) == false)
        try await cache.store(series)
        #expect(await cache.contains(series.id))
        #expect(try await cache.load(series.id) == series)

        try await cache.remove(series.id)
        #expect(await cache.contains(series.id) == false)
        #expect(try await cache.load(series.id) == nil)
        try? FileManager.default.removeItem(at: directory)
    }
}
