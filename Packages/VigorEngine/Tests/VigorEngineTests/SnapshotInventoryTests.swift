import Foundation
import Testing
import VigorScoring
@testable import VigorEngine

@Suite("SnapshotInventory")
struct SnapshotInventoryTests {
    @Test("空快照判定为没有读到任何数据")
    func emptySnapshot() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let snapshot = HealthSnapshot(
            exportedAt: start,
            rangeStart: start,
            rangeEnd: start.addingTimeInterval(86_400),
            profile: UserProfile(birthYear: nil, sex: .unknown),
            sleep: [],
            heartRate: [],
            hrvSDNN: [],
            restingHeartRate: [],
            respiratoryRate: [],
            wristTemperature: [],
            oxygenSaturation: [],
            heartbeatSeries: []
        )
        let inventory = SnapshotInventory(snapshot)
        #expect(inventory.isEmpty)
        #expect(inventory.sleepSources.isEmpty)
    }

    @Test("统计睡眠分期总数、手表来源条数与来源列表")
    func countsSleepSources() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let watch = SleepStageSample(start: start, end: start.addingTimeInterval(1800), stage: .core, sourceIsWatch: true)
        let phone = SleepStageSample(start: start, end: start.addingTimeInterval(600), stage: .core, sourceIsWatch: false)
        let snapshot = HealthSnapshot(
            exportedAt: start,
            rangeStart: start,
            rangeEnd: start.addingTimeInterval(86_400),
            profile: UserProfile(birthYear: nil, sex: .unknown),
            sleep: [watch, phone],
            heartRate: [HeartRateSample(date: start, bpm: 55)],
            hrvSDNN: [],
            restingHeartRate: [],
            respiratoryRate: [],
            wristTemperature: [],
            oxygenSaturation: [],
            heartbeatSeries: []
        )
        let inventory = SnapshotInventory(snapshot)
        #expect(!inventory.isEmpty)
        #expect(inventory.sleepStages == 2)
        #expect(inventory.sleepStagesFromWatch == 1)
        #expect(inventory.heartRate == 1)
        #expect(inventory.sleepSources.count == 2)
        #expect(inventory.summary.contains("睡眠分期 2 条（手表 1 条）"))
    }
}
