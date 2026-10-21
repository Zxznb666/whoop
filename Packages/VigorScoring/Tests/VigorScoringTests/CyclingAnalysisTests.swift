import Foundation
import Testing
import VigorFIT
@testable import VigorScoring

@Suite("骑行分组、功率补偿与分析")
struct CyclingAnalysisTests {
    static let day: TimeInterval = 86_400
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()
    let origin = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 GMT，整分钟

    @Test("分组：重叠 60% → 同一组")
    func sixtyPercentOverlapGroups() {
        let a = RideCandidate(source: .imported("a"), start: origin, end: origin.addingTimeInterval(3600))
        let b = RideCandidate(source: .imported("b"), start: origin.addingTimeInterval(1440), end: origin.addingTimeInterval(5040))
        let groups = RideGrouping.group([a, b])
        #expect(groups.count == 1)
        #expect(groups.first?.members.count == 2)
    }

    @Test("分组：重叠 30% → 两组")
    func thirtyPercentOverlapSplits() {
        let a = RideCandidate(source: .imported("a"), start: origin, end: origin.addingTimeInterval(3600))
        let b = RideCandidate(source: .imported("b"), start: origin.addingTimeInterval(2520), end: origin.addingTimeInterval(6120))
        #expect(RideGrouping.group([a, b]).count == 2)
    }

    @Test("分组：传递闭包（A 与 B、B 与 C 重叠，A 与 C 不重叠 → 同一组）")
    func transitiveGrouping() {
        let a = RideCandidate(source: .imported("a"), start: origin, end: origin.addingTimeInterval(3600))
        let b = RideCandidate(source: .imported("b"), start: origin.addingTimeInterval(1800), end: origin.addingTimeInterval(5400))
        let c = RideCandidate(source: .imported("c"), start: origin.addingTimeInterval(3600), end: origin.addingTimeInterval(7200))
        #expect(RideGrouping.group([a, b, c]).count == 1)
    }

    @Test("功率→心率模型：精确的线性关系 HR = 60 + 0.2·P30 → 斜率与截距精确")
    func powerHeartModelRecoversLine() throws {
        let x = (0..<1500).map { Double(($0 * 37) % 300) }
        let y = x.map { 60 + 0.2 * $0 }
        let model = try #require(PowerHeartModel.fit(x: x, y: y))
        #expect(abs(model.slope - 0.2) < 1e-9)
        #expect(abs(model.intercept - 60) < 1e-6)
        #expect(model.pairCount == 1500)
    }

    @Test("功率→心率模型：配对秒数不足 1200 → 不启用")
    func powerHeartModelNeedsPairs() {
        let x = (0..<1199).map(Double.init)
        #expect(PowerHeartModel.fit(x: x, y: x) == nil)
    }

    @Test("FTP 自动估算：最近 90 天最佳 20 分钟 280 W → 266 W")
    func autoFTPFromBestTwentyMinutes() throws {
        let start = origin
        let ride = RideStream.simple(
            fileID: "ftp", start: start,
            heartRate: [Int?](repeating: 140, count: 1200),
            power: [Int?](repeating: 280, count: 1200)
        )
        let grid = MinuteGrid.build(origin: origin, end: start.addingTimeInterval(1200), heartRate: [], activeEnergy: [], steps: [])
        let input = CyclingInput(
            importedRides: [ride], restingHeartRate: 55, maxHeartRate: 185, sex: .male,
            now: start.addingTimeInterval(Self.day), calendar: calendar
        )
        let output = CyclingAnalysis.run(input, grid: grid)
        let ftp = try #require(output.ftp)
        #expect(ftp.source == .estimated)
        #expect(abs(ftp.watts - 266) < 1e-9)
    }

    @Test("手表训练与 Garmin 写入的同一次骑行合并为一条")
    func overlappingSourcesMergeIntoOneRide() {
        let watch = WorkoutSample(uuid: UUID(), activityType: "cycling", start: origin, end: origin.addingTimeInterval(3600), productType: "Watch7,1")
        let garmin = WorkoutSample(uuid: UUID(), activityType: "cycling", start: origin.addingTimeInterval(30), end: origin.addingTimeInterval(3630), sourceBundleID: "com.garmin.connect", productType: "iPhone15,2")
        let grid = MinuteGrid.build(origin: origin, end: origin.addingTimeInterval(3700), heartRate: [], activeEnergy: [], steps: [])
        let output = CyclingAnalysis.run(CyclingInput(
            workouts: [watch, garmin], restingHeartRate: 55, maxHeartRate: 185, sex: .male,
            now: origin.addingTimeInterval(Self.day), calendar: calendar
        ), grid: grid)
        #expect(output.rides.count == 1)
        #expect(output.rides.first?.sourceLabels.sorted() == ["Apple Watch", "Garmin 写入"])
    }

    @Test("心率缺失 10 分钟且没有模型、没有 k（历史骑行不足 5 次）→ 空窗并标记“负荷可能低估”")
    func gapWithoutAnyEstimateIsFlagged() throws {
        let grid = gridWithGap(gapMinutes: 5..<15, minutes: 20)
        let input = hkRideInput(manualFTP: nil, minutes: 20)
        let output = CyclingAnalysis.run(input, grid: grid)
        let ride = try #require(output.rides.first)
        #expect(ride.loadMayBeUnderestimated)
        #expect(ride.compensatedMinutes == 10)
        #expect((5..<15).allSatisfy { output.compensation[$0] == 0 })
    }

    @Test("心率缺失且有 k（至少 5 次历史骑行）→ 用 k·TSS 补偿")
    func gapUsesKTimesTSS() throws {
        // 历史骑行：第 100 分钟起，每次 30 分钟，NP 200，心率来自分钟网格（140 bpm）
        let history = (0..<5).map { index in
            RideStream.simple(
                fileID: "h\(index)",
                start: origin.addingTimeInterval(Double(100 + index * 40) * 60),
                heartRate: [Int?](repeating: nil, count: 1800),
                power: [Int?](repeating: 200, count: 1800)
            )
        }
        let grid = gridWithGap(gapMinutes: 5..<15, minutes: 300, hr: 140)
        var input = hkRideInput(manualFTP: 250, minutes: 20)
        input.importedRides = history
        let output = CyclingAnalysis.run(input, grid: grid)
        let k = try #require(output.trimpPerTSS)
        // 历史：30 分钟、NP 200、FTP 250 → TSS = 1800 × 200 × 0.8 / (250 × 3600) × 100 = 53.33
        let trimpPerMinute = Strain.trimpPerMinute(hrr: Strain.hrr(heartRate: 140, restingHeartRate: 55, maxHeartRate: 185), sex: .male)
        #expect(abs(k - trimpPerMinute * 30 / (1800 * 200 * 0.8 / (250 * 3600) * 100)) < 1e-6)
        let perMinute = k * 60 * pow(200.0 / 250, 2) * 100 / 3600
        #expect(abs((output.compensation[5] ?? -1) - perMinute) < 1e-6)
        let rideToday = try #require(output.rides.first(where: { $0.start == origin }))
        #expect(rideToday.loadMayBeUnderestimated == false)
    }

    @Test("心率缺失且模型可用 → 用 HR = a + b·P30(t−20) 估算，不标记低估")
    func gapUsesPowerModel() throws {
        var hr = [Int?](repeating: nil, count: 3600)
        var watts = [Int?](repeating: 0, count: 3600)
        for second in 0..<3600 {
            watts[second] = (second / 60) % 2 == 0 ? 150 : 250
        }
        let p30 = CyclingAnalysis.rollingWindowAverage(watts.map { Double($0 ?? 0) }, window: 30)
        for second in 0..<3600 {
            let lagged = second - PowerHeartModel.lagSeconds
            let x = lagged >= 0 ? p30[lagged] : 0
            hr[second] = Int((60 + 0.2 * x).rounded())
        }
        // 第 20–29 分钟心率缺失
        for second in 1200..<1800 { hr[second] = nil }
        let ride = RideStream.simple(fileID: "model", start: origin, heartRate: hr, power: watts)
        let heartSamples = (0..<3600).compactMap { second -> TaggedHeartRate? in
            guard let bpm = hr[second] else { return nil }
            return TaggedHeartRate(date: origin.addingTimeInterval(Double(second)), bpm: Double(bpm), origin: .fitImport)
        }
        let grid = MinuteGrid.build(
            origin: origin, end: origin.addingTimeInterval(3600),
            taggedHeartRate: heartSamples, activeEnergy: [], steps: []
        )
        let input = CyclingInput(
            importedRides: [ride], manualFTP: 250,
            restingHeartRate: 55, maxHeartRate: 185, sex: .male,
            now: origin.addingTimeInterval(Self.day), calendar: calendar
        )
        let output = CyclingAnalysis.run(input, grid: grid)
        let model = try #require(output.powerModel)
        #expect(abs(model.slope - 0.2) < 0.05)
        let result = try #require(output.rides.first)
        #expect(result.compensatedMinutes == 10)
        #expect(result.loadMayBeUnderestimated == false)
        #expect((20..<30).allSatisfy { (output.compensation[$0] ?? 0) > 0 })
    }

    // MARK: 构造数据

    /// 分钟 `gapMinutes` 之外有心率（每分钟一条测量）。
    private func gridWithGap(gapMinutes: Range<Int>, minutes: Int, hr: Double = 140) -> MinuteGrid {
        var samples: [TaggedHeartRate] = []
        for minute in 0..<minutes where !gapMinutes.contains(minute) {
            samples.append(TaggedHeartRate(date: origin.addingTimeInterval(Double(minute * 60 + 30)), bpm: hr, origin: .watchWorkout))
        }
        return MinuteGrid.build(
            origin: origin,
            end: origin.addingTimeInterval(Double(minutes * 60)),
            taggedHeartRate: samples,
            activeEnergy: [],
            steps: []
        )
    }

    /// 一次 HealthKit 骑行（从 origin 开始，200 W），不含心率；心率由网格提供。
    private func hkRideInput(manualFTP: Double?, minutes: Int) -> CyclingInput {
        CyclingInput(
            workouts: [WorkoutSample(uuid: UUID(), activityType: "cycling", start: origin, end: origin.addingTimeInterval(Double(minutes * 60)), productType: "Watch7,1")],
            cyclingPower: [ValueSample(start: origin, end: origin.addingTimeInterval(Double(minutes * 60)), value: 200)],
            manualFTP: manualFTP,
            restingHeartRate: 55, maxHeartRate: 185, sex: .male,
            now: origin.addingTimeInterval(Self.day), calendar: calendar
        )
    }
}
