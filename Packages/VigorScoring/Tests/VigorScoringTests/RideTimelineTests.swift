import Foundation
import Testing
import VigorFIT
@testable import VigorScoring

@Suite("骑行时间线、降采样与分圈（M6 补完 C1）")
struct RideTimelineTests {
    let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 GMT，整分钟

    func snapshot(
        heartRate: [HeartRateSample] = [],
        workouts: [WorkoutSample] = [],
        cyclingPower: [ValueSample] = []
    ) -> HealthSnapshot {
        HealthSnapshot(
            exportedAt: start,
            rangeStart: start,
            rangeEnd: start.addingTimeInterval(7200),
            profile: UserProfile(birthYear: nil, sex: .unknown),
            sleep: [],
            heartRate: heartRate,
            hrvSDNN: [],
            restingHeartRate: [],
            respiratoryRate: [],
            wristTemperature: [],
            oxygenSaturation: [],
            heartbeatSeries: [],
            workouts: workouts,
            cyclingPower: cyclingPower
        )
    }

    func ride(id: String, seconds: Int) -> RideResult {
        RideResult(
            id: id,
            start: start,
            end: start.addingTimeInterval(Double(seconds)),
            sourceLabels: [],
            memberCount: 1,
            movingSeconds: seconds,
            heartRateOrigin: nil,
            powerSource: .none,
            powerCoverage: nil,
            normalizedPower: nil,
            intensityFactor: nil,
            tss: nil,
            mechanicalWorkKJ: nil,
            wattsPerKilogram: nil,
            averageHeartRate: nil,
            efficiencyFactor: nil,
            aerobicDecoupling: nil,
            zoneSeconds: nil,
            powerCurve: [:],
            compensatedMinutes: 0,
            loadMayBeUnderestimated: false,
            measuredTRIMP: 0
        )
    }

    @Test("FIT 恒定 3600 秒 → 600 个点，心率 140、功率 200")
    func fitConstantHour() {
        let stream = RideStream.simple(
            fileID: "a",
            start: start,
            heartRate: Array(repeating: 140, count: 3600),
            power: Array(repeating: 200, count: 3600)
        )
        let timeline = RideTimelineBuilder.build(ride: ride(id: "fit-a", seconds: 3600), snapshot: snapshot(), importedRides: [stream])
        #expect(timeline.points.count == 600)
        #expect(timeline.points.allSatisfy { $0.heartRate == 140 && $0.power == 200 })
        #expect(timeline.heartRateSource == .fitImport)
        #expect(timeline.powerSource == .fit)
    }

    @Test("骑行 300 秒、maxPoints 600 → 300 个点（每秒一个桶）")
    func shortRideOnePointPerSecond() {
        let stream = RideStream.simple(
            fileID: "a",
            start: start,
            heartRate: Array(repeating: 120, count: 300),
            power: Array(repeating: 180, count: 300)
        )
        let timeline = RideTimelineBuilder.build(ride: ride(id: "fit-a", seconds: 300), snapshot: snapshot(), importedRides: [stream])
        #expect(timeline.points.count == 300)
        #expect(timeline.points.first?.offset == 0.5)
    }

    @Test("HealthKit 功率中间 60 秒空档 → 空档的点为 nil，不是 0")
    func powerGapIsNil() {
        let samples = [
            ValueSample(start: start, end: start.addingTimeInterval(120), value: 200),
            ValueSample(start: start.addingTimeInterval(180), end: start.addingTimeInterval(300), value: 200),
        ]
        let timeline = RideTimelineBuilder.build(
            ride: ride(id: "hk", seconds: 300),
            snapshot: snapshot(cyclingPower: samples),
            importedRides: []
        )
        #expect(timeline.points.count == 300)
        #expect(timeline.points[10].power == 200)
        #expect(timeline.points[150].power == nil)
        #expect(timeline.powerSource == .healthKit)
    }

    @Test("心率同时有 Garmin 与手表被动样本，且只有 Garmin 训练 → 使用 Garmin 的心率")
    func garminPreferredOverWatchPassive() {
        let workout = WorkoutSample(
            uuid: UUID(),
            activityType: "cycling",
            start: start,
            end: start.addingTimeInterval(300),
            sourceBundleID: "com.garmin.connect.mobile",
            productType: nil
        )
        let watch = stride(from: 0, to: 300, by: 5).map {
            HeartRateSample(date: start.addingTimeInterval(Double($0)), bpm: 100, sourceBundleID: "com.apple.health", productType: "Watch6,1")
        }
        let garmin = stride(from: 0, to: 300, by: 5).map {
            HeartRateSample(date: start.addingTimeInterval(Double($0)), bpm: 150, sourceBundleID: "com.garmin.connect.mobile", productType: nil)
        }
        let timeline = RideTimelineBuilder.build(
            ride: ride(id: "hk", seconds: 300),
            snapshot: snapshot(heartRate: watch + garmin, workouts: [workout]),
            importedRides: []
        )
        #expect(timeline.points.allSatisfy { $0.heartRate == 150 })
        #expect(timeline.heartRateSource == .otherWorkout)
    }

    @Test("FIT 两圈：平均功率 250、150，NP 分别为 250、150")
    func lapsSplitByBoundaries() throws {
        var stream = RideStream.simple(
            fileID: "a",
            start: start,
            heartRate: Array(repeating: 140, count: 1200),
            power: Array(repeating: 250, count: 600) + Array(repeating: 150, count: 600)
        )
        stream.laps = [
            FITLap(startTime: start, endTime: start.addingTimeInterval(600)),
            FITLap(startTime: start.addingTimeInterval(600), endTime: start.addingTimeInterval(1200)),
        ]
        let timeline = RideTimelineBuilder.build(ride: ride(id: "fit-a", seconds: 1200), snapshot: snapshot(), importedRides: [stream])
        #expect(timeline.laps.count == 2)
        let first = try #require(timeline.laps.first)
        let second = try #require(timeline.laps.last)
        #expect(first.averagePower == 250)
        #expect(second.averagePower == 150)
        #expect(first.normalizedPower == 250)
        #expect(second.normalizedPower == 150)
        #expect(first.durationSeconds == 600)
    }

    @Test("第 3 圈只有 20 秒 → 该圈 NP 为 nil")
    func shortLapHasNoNormalizedPower() throws {
        var stream = RideStream.simple(
            fileID: "a",
            start: start,
            heartRate: Array(repeating: 140, count: 1220),
            power: Array(repeating: 200, count: 1220)
        )
        stream.laps = [
            FITLap(startTime: start, endTime: start.addingTimeInterval(600)),
            FITLap(startTime: start.addingTimeInterval(600), endTime: start.addingTimeInterval(1200)),
            FITLap(startTime: start.addingTimeInterval(1200), endTime: start.addingTimeInterval(1220)),
        ]
        let timeline = RideTimelineBuilder.build(ride: ride(id: "fit-a", seconds: 1220), snapshot: snapshot(), importedRides: [stream])
        let third = try #require(timeline.laps.last)
        #expect(third.index == 3)
        #expect(third.durationSeconds == 20)
        #expect(third.normalizedPower == nil)
    }

    @Test("非 FIT 骑行没有分圈")
    func noLapsWithoutFIT() {
        let timeline = RideTimelineBuilder.build(ride: ride(id: "hk", seconds: 300), snapshot: snapshot(), importedRides: [])
        #expect(timeline.laps.isEmpty)
    }
}

@Suite("RideTimeline 分圈 NP 口径")
struct RideLapPowerGapTests {
    let base = RideTimelineTests()

    func lapTimeline(power: [Int?]) -> RideTimeline {
        var stream = RideStream.simple(
            fileID: "gap",
            start: base.start,
            heartRate: Array(repeating: 140, count: power.count),
            power: power
        )
        stream.laps = [FITLap(startTime: base.start, endTime: base.start.addingTimeInterval(Double(power.count)))]
        return RideTimelineBuilder.build(
            ride: base.ride(id: "fit-gap", seconds: power.count),
            snapshot: base.snapshot(),
            importedRides: [stream]
        )
    }

    @Test("功率中途掉线 60 秒：分圈 NP 按 D-128 用平均功率填充，而不是按 0 W")
    func longGapUsesRideMean() throws {
        // 前 300 秒 200 W，掉线 60 秒，后 300 秒 200 W：长空档填平均功率 200 → NP = 200（按 0 W 计会明显偏低）
        let power: [Int?] = Array(repeating: 200, count: 300) + Array(repeating: nil, count: 60) + Array(repeating: 200, count: 300)
        let lap = try #require(lapTimeline(power: power).laps.first)
        let np = try #require(lap.normalizedPower)
        #expect(abs(np - 200) < 1e-9)
        #expect(lap.averagePower == 200)
    }

    @Test("功率覆盖不足 50%：分圈不出 NP")
    func lowCoverageHasNoNormalizedPower() throws {
        let power: [Int?] = Array(repeating: 200, count: 200) + Array(repeating: nil, count: 400)
        let lap = try #require(lapTimeline(power: power).laps.first)
        #expect(lap.normalizedPower == nil)
    }
}
