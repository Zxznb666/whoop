import Foundation
import Testing
import VigorFIT
@testable import VigorScoring

@Suite("心率来源的手动指定（M6 补完 C5）")
struct SourcePreferenceTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()
    let origin = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 GMT，整分钟
    let garmin = "com.garmin.connect.mobile"

    /// 同一 5 分钟内：手表训练（100 bpm）与 Garmin 训练（150 bpm），两者都有心率样本。
    func overlappingSamples() -> (heartRate: [HeartRateSample], workouts: [WorkoutSample]) {
        let watchWorkout = WorkoutSample(
            uuid: UUID(), activityType: "cycling", start: origin, end: origin.addingTimeInterval(300),
            sourceBundleID: "com.apple.health", productType: "Watch7,1"
        )
        let garminWorkout = WorkoutSample(
            uuid: UUID(), activityType: "cycling", start: origin, end: origin.addingTimeInterval(300),
            sourceBundleID: garmin, productType: nil
        )
        let watch = stride(from: 0, to: 300, by: 5).map {
            HeartRateSample(date: origin.addingTimeInterval(Double($0)), bpm: 100, sourceBundleID: "com.apple.health", productType: "Watch7,1")
        }
        let device = stride(from: 0, to: 300, by: 5).map {
            HeartRateSample(date: origin.addingTimeInterval(Double($0)), bpm: 150, sourceBundleID: garmin, productType: nil)
        }
        return (watch + device, [watchWorkout, garminWorkout])
    }

    func grid(_ preferences: [String: SourcePreference], samples: (heartRate: [HeartRateSample], workouts: [WorkoutSample])) -> MinuteGrid {
        MinuteGrid.build(
            origin: origin,
            end: origin.addingTimeInterval(300),
            taggedHeartRate: HeartRateOriginClassifier.tag(samples.heartRate, workouts: samples.workouts, preferences: preferences),
            activeEnergy: [],
            steps: []
        )
    }

    @Test("Garmin 设为优先：同一分钟同时有手表训练心率和 Garmin 心率 → 取 Garmin")
    func preferredWinsOverWatchWorkout() {
        let result = grid([garmin: .preferred], samples: overlappingSamples())
        #expect(result.heartRate[0] == 150)
        #expect(result.heartRateOrigin[0] == .preferredWorkout)
    }

    @Test("Garmin 设为忽略：这一分钟取手表的心率，骑行分组的数量不变")
    func ignoredFallsBackToWatch() throws {
        let samples = overlappingSamples()
        let result = grid([garmin: .ignored], samples: samples)
        #expect(result.heartRate[0] == 100)
        #expect(result.heartRateOrigin[0] == .watchWorkout)

        // 分组只依赖训练记录，忽略心率来源不改变骑行数量
        let defaultRides = CyclingAnalysis.run(cyclingInput(workouts: samples.workouts), grid: grid([:], samples: samples)).rides
        let ignoredRides = CyclingAnalysis.run(cyclingInput(workouts: samples.workouts), grid: result).rides
        #expect(defaultRides.count == 1)
        #expect(ignoredRides.count == defaultRides.count)
        #expect(try #require(ignoredRides.first).averageHeartRate == 100)
    }

    @Test("没有任何偏好：标签与自动规则完全相同")
    func noPreferenceIsAutomatic() {
        let samples = overlappingSamples()
        let explicit = HeartRateOriginClassifier.tag(samples.heartRate, workouts: samples.workouts, preferences: [:])
        let implicit = HeartRateOriginClassifier.tag(samples.heartRate, workouts: samples.workouts)
        #expect(explicit == implicit)
        #expect(explicit.contains { $0.origin == .preferredWorkout } == false)
    }

    @Test("优先的来源不在自己的训练内时，按自动规则处理")
    func preferredOutsideOwnWorkoutIsAutomatic() {
        let sample = HeartRateSample(date: origin.addingTimeInterval(60), bpm: 120, sourceBundleID: garmin, productType: nil)
        let tagged = HeartRateOriginClassifier.tag([sample], workouts: [], preferences: [garmin: .preferred])
        #expect(tagged.first?.origin == .other)
    }

    @Test("旧 rawValue 解码不变；优先级排序为 fitImport > preferredWorkout > watchWorkout > otherWorkout > watchPassive > other")
    func rawValuesAndRanking() {
        #expect(HeartRateOrigin(rawValue: 0) == .other)
        #expect(HeartRateOrigin(rawValue: 1) == .watchPassive)
        #expect(HeartRateOrigin(rawValue: 2) == .otherWorkout)
        #expect(HeartRateOrigin(rawValue: 3) == .watchWorkout)
        #expect(HeartRateOrigin(rawValue: 4) == .fitImport)
        #expect(HeartRateOrigin(rawValue: 5) == .preferredWorkout)
        let ordered: [HeartRateOrigin] = [.fitImport, .preferredWorkout, .watchWorkout, .otherWorkout, .watchPassive, .other]
        #expect(ordered.shuffled().sorted(by: >) == ordered)
        #expect(ordered.max() == .fitImport)
    }

    @Test("来源偏好可以往返编码")
    func preferencesRoundTrip() throws {
        let preferences: [String: SourcePreference] = [garmin: .preferred, "com.other": .ignored]
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode([String: SourcePreference].self, from: data) == preferences)
    }

    private func cyclingInput(workouts: [WorkoutSample]) -> CyclingInput {
        CyclingInput(
            workouts: workouts,
            restingHeartRate: 55, maxHeartRate: 185, sex: .male,
            now: origin.addingTimeInterval(86_400), calendar: calendar
        )
    }
}
