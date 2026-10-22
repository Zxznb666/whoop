import Foundation
import Testing
import VigorHealth
import VigorScoring
import VigorStore
@testable import VigorEngine

@Suite("心率来源偏好经 SyncEngine 进入流水线（M6 补完 C5）")
struct SourcePreferenceSyncTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()
    let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 GMT
    let garmin = "com.garmin.connect.mobile"

    /// 一小时的 Garmin 骑行（150 bpm）与同一时段手表被动心率（100 bpm）。
    func snapshot() -> HealthSnapshot {
        let end = start.addingTimeInterval(7200)
        let workout = WorkoutSample(
            uuid: UUID(), activityType: "cycling", start: start, end: start.addingTimeInterval(3600),
            sourceBundleID: garmin, productType: nil
        )
        let device = stride(from: 0, to: 3600, by: 5).map {
            HeartRateSample(date: start.addingTimeInterval(Double($0)), bpm: 150, sourceBundleID: garmin, productType: nil)
        }
        let watch = stride(from: 0, to: 3600, by: 5).map {
            HeartRateSample(date: start.addingTimeInterval(Double($0)), bpm: 100, sourceBundleID: "com.apple.health", productType: "Watch7,1")
        }
        return HealthSnapshot(
            exportedAt: end,
            rangeStart: start,
            rangeEnd: end,
            profile: UserProfile(birthYear: nil, sex: .unknown),
            sleep: [],
            heartRate: device + watch,
            hrvSDNN: [],
            restingHeartRate: [],
            respiratoryRate: [],
            wristTemperature: [],
            oxygenSaturation: [],
            heartbeatSeries: [],
            workouts: [workout]
        )
    }

    /// 用给定的偏好刷新一次，返回保存下来的骑行平均心率。
    func averageHeartRate(preferences: [String: SourcePreference]) async throws -> Double? {
        let repository = ScoreRepository(modelContainer: try VigorStoreFactory.makeContainer(inMemory: true))
        let engine = SyncEngine(
            source: RecordingSource(snapshot: snapshot()),
            repository: repository,
            cache: nil,
            calendar: calendar,
            historyDays: 40,
            appGroupID: "group.invalid.test"
        )
        let settings = ScoringSettings(heartRateSourcePreferences: preferences)
        try await engine.refresh(mode: .full, settings: settings, now: start.addingTimeInterval(7200))
        let output = try #require(try await repository.cyclingOutput())
        #expect(output.rides.count == 1)
        return output.rides.first?.averageHeartRate
    }

    @Test("没有偏好：Garmin 训练中的 Garmin 心率优先（150）")
    func defaultUsesGarmin() async throws {
        #expect(try await averageHeartRate(preferences: [:]) == 150)
    }

    @Test("Garmin 设为忽略：骑行心率变为手表的 100")
    func ignoredReachesPipeline() async throws {
        #expect(try await averageHeartRate(preferences: [garmin: .ignored]) == 100)
    }

    @Test("Garmin 设为优先：仍然是 Garmin 的 150")
    func preferredReachesPipeline() async throws {
        #expect(try await averageHeartRate(preferences: [garmin: .preferred]) == 150)
    }
}
