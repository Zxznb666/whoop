import Foundation
import SwiftData
import Testing
@testable import VigorScoring
@testable import VigorStore

@Suite("ScoreRepository")
struct ScoreRepositoryTests {
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: CycleRecord.self, JournalRecord.self, ConfigRecord.self,
            configurations: configuration
        )
    }

    /// 只构造存储层需要的字段；评分内容由 VigorScoring 的测试负责。
    private func cycle(wake: Date, configVersion: Int, state: ScoreState) throws -> CycleResult {
        let features = NightFeatures(
            session: SleepSession(
                start: wake.addingTimeInterval(-8 * 3600),
                end: wake,
                bedtime: nil,
                stages: [],
                asleepDuration: 8 * 3600,
                wakeDay: DateComponents(year: 2026, month: 10, day: 21),
                nightKey: DateComponents(year: 2026, month: 10, day: 20),
                kind: .main,
                timeZoneOffset: 28800,
                longAwakeGaps: []
            ),
            hrv: NightHRV(nightRMSSD: 30, nightValidCount: 3, nightTotalCount: 3, morningRMSSD: nil, morningValidCount: 0, sdnnMean: nil, dispersion: nil, method: .overnight),
            windows: [],
            restingHeartRate: RestingHeartRate(value: 52, source: .sampledP10, sampleCount: 40, meanHeartRate: 58, lowestTimePosition: 0.5),
            meanHeartRate: 58,
            heartRateCount: 100,
            partialWear: false,
            longestHeartRateGapMinutes: 10,
            heartRateCoverage: 1,
            awakenings: 1,
            respiratoryRate: 14,
            wristTemperature: 36.4,
            spo2MedianPercent: 97,
            spo2BelowFraction: 0,
            breathingDisturbance: nil,
            breathingDisturbanceUnit: nil,
            appleRestingHeartRate: 53
        )
        return CycleResult(
            wakeDay: DateComponents(year: 2026, month: 10, day: 21),
            wakeTime: wake,
            features: features,
            quality: QualityReport(total: 0.9, level: .high, components: QualityComponents(hrv: 1, heartRate: 1, sleep: 1, vitals: 1), reasons: []),
            baselines: [:],
            zHRV: 0.2,
            zRHR: 0.1,
            zResp: 0,
            temperatureDelta: 0,
            sleepMetrics: SleepMetrics(totalSleepHours: 7.5, efficiency: 0.92, efficiencyIsSleepPeriod: false, sleepLatencyMinutes: 12, wasoMinutes: 20, awakenings: 1, remLatencyMinutes: 60, restorativeHours: 3, restorativeFraction: 0.4),
            sri: 80,
            need: SleepNeedComponents(base: 7.5, loadAddition: 0, napCredit: 0, debtRepayment: 0, baseNeed: 7.5),
            sleepScore: SleepScore(score: 88, performance: 100, durationAchieved: 1, efficiencyComponent: 0.8, consistencyComponent: 0.8, restorativeComponent: 0.5, zSleep: 0.7),
            debtAfterNight: 0,
            illnessSignals: IllnessSignals(temperature: false, respiratory: false, hrv: false, restingHeartRate: false),
            illness: .none,
            illnessConfounded: false,
            exclusion: nil,
            recovery: RecoveryScorer.score(RecoveryInputs(zHRV: 0.2, zRHR: 0.1, zSleep: 0.7)),
            recoveryState: state,
            load: CycleLoad(trimp: 40, strain: 9, countedMinutes: 900, unwornMinutes: 0, zoneMinutes: [0, 0, 0, 0, 0], maxHeartRate: 185, restingHeartRate: 52, activityModelEnabled: false, workouts: [], stress: nil),
            acwr: 1.0,
            loadTarget: LoadTarget(lower: 14, upper: 18),
            trend: nil,
            bedtimeAdvice: nil,
            algorithmVersion: 1,
            configVersion: configVersion,
            inputHash: 0xABCD_EF01
        )
    }

    @Test("写入后读回的周期与原始结果相等")
    func roundTrip() async throws {
        let repository = ScoreRepository(modelContainer: try makeContainer())
        let wake = Date(timeIntervalSince1970: 1_800_000_000)
        let original = try cycle(wake: wake, configVersion: 1, state: .final)
        try await repository.upsert([original])
        let loaded = try await repository.cycles(from: wake.addingTimeInterval(-1), to: wake.addingTimeInterval(1))
        #expect(loaded == [original])
    }

    @Test("锁定的周期在配置版本不变时不被覆盖；配置版本变化或强制重算时覆盖")
    func lockedCyclesStayUnlessConfigChanges() async throws {
        let repository = ScoreRepository(modelContainer: try makeContainer())
        let wake = Date(timeIntervalSince1970: 1_800_000_000)
        try await repository.upsert([try cycle(wake: wake, configVersion: 1, state: .locked)])
        #expect(try await repository.lockedCount() == 1)

        let changed = try cycle(wake: wake, configVersion: 1, state: .final)
        let skipped = try await repository.upsert([changed])
        #expect(skipped == 0)

        let newConfig = try cycle(wake: wake, configVersion: 2, state: .final)
        #expect(try await repository.upsert([newConfig]) == 1)
        let loaded = try await repository.cycles(from: wake, to: wake)
        #expect(loaded.first?.configVersion == 2)

        let forced = try cycle(wake: wake, configVersion: 2, state: .final)
        #expect(try await repository.upsert([forced], force: true) == 1)
    }

    @Test("日志与配置的存取")
    func journalAndConfig() async throws {
        let repository = ScoreRepository(modelContainer: try makeContainer())
        let night = Date(timeIntervalSince1970: 1_800_000_000)
        try await repository.saveJournal(JournalEntry(night: night, behaviors: ["alcohol": true], energy: 3))
        let entries = try await repository.journal(from: night, to: night)
        #expect(entries.first?.behaviors["alcohol"] == true)

        var config = ScoringConfig.default
        config.configVersion = 3
        try await repository.saveConfig(config)
        #expect(try await repository.currentConfig()?.configVersion == 3)
    }

    @Test("共享状态文件：编码再解码后相等")
    func sharedStateRoundTrip() throws {
        let state = SharedState(
            recovery: 72, recoveryZone: "green", strain: 9.5, strainTargetLower: 14, strainTargetUpper: 18,
            sleepScore: 88, suggestedBedtime: Date(timeIntervalSince1970: 1_800_000_000), stateRaw: "final",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100), appGroupAvailable: false
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vigor-shared-\(UUID().uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(state).write(to: url)
        #expect(try SharedStateStore.read(from: url) == state)
        try? FileManager.default.removeItem(at: url)
    }
}
