import Foundation
import Testing
@testable import VigorScoring

@Suite("分钟级心率去重")
struct MinuteDedupeTests {
    let origin = Date(timeIntervalSince1970: 1_767_000_000) // 整分钟

    private func grid(_ tagged: [TaggedHeartRate]) -> MinuteGrid {
        MinuteGrid.build(
            origin: origin,
            end: origin.addingTimeInterval(600),
            taggedHeartRate: tagged,
            activeEnergy: [],
            steps: []
        )
    }

    private func samples(minute: Int, bpm: Double, origin source: HeartRateOrigin) -> [TaggedHeartRate] {
        (0..<60).map { second in
            TaggedHeartRate(
                date: origin.addingTimeInterval(Double(minute * 60 + second)),
                bpm: bpm,
                origin: source
            )
        }
    }

    @Test("同一分钟同时有手表训练心率和 Garmin 心率 → 取手表的")
    func watchWorkoutBeatsOtherWorkout() {
        let tagged = samples(minute: 2, bpm: 150, origin: .watchWorkout) + samples(minute: 2, bpm: 120, origin: .otherWorkout)
        #expect(grid(tagged).heartRate[2] == 150)
    }

    @Test("FIT 导入优先于一切，且不会与其他来源相加或混合平均")
    func fitImportWinsWithoutMixing() {
        let tagged = samples(minute: 3, bpm: 140, origin: .fitImport) + samples(minute: 3, bpm: 155, origin: .watchWorkout)
        #expect(grid(tagged).heartRate[3] == 140)
    }

    @Test("同一次骑行同时有 FIT 与手表心率：分钟心率与只用 FIT 时完全相同（TRIMP 不翻倍）")
    func overlappingSourcesDoNotDoubleLoad() {
        let fitOnly = (0..<10).flatMap { samples(minute: $0, bpm: 120 + Double($0), origin: .fitImport) }
        let withWatch = fitOnly + (0..<10).flatMap { samples(minute: $0, bpm: 120 + Double($0), origin: .watchWorkout) }
        let a = grid(fitOnly)
        let b = grid(withWatch)
        #expect(a.heartRate.prefix(10).elementsEqual(b.heartRate.prefix(10), by: { $0 == $1 }))
        let loadA = (0..<10).reduce(0.0) { $0 + Strain.trimpPerMinute(hrr: Strain.hrr(heartRate: a.heartRate[$1], restingHeartRate: 55, maxHeartRate: 185), sex: .male) }
        let loadB = (0..<10).reduce(0.0) { $0 + Strain.trimpPerMinute(hrr: Strain.hrr(heartRate: b.heartRate[$1], restingHeartRate: 55, maxHeartRate: 185), sex: .male) }
        #expect(abs(loadA - loadB) < 1e-9)
    }

    @Test("手表被动采样低于训练期间的来源，但高于其他来源")
    func passiveRanking() {
        let tagged = samples(minute: 4, bpm: 90, origin: .other) + samples(minute: 4, bpm: 80, origin: .watchPassive)
        #expect(grid(tagged).heartRate[4] == 80)
    }

    @Test("只有 Garmin 训练时，同一分钟的 Garmin 心率优先于手表的被动心率")
    func garminWorkoutBeatsWatchPassiveWithinSameMinute() {
        let garminWorkout = WorkoutSample(uuid: UUID(), activityType: "cycling", start: origin, end: origin.addingTimeInterval(600), sourceBundleID: "com.garmin.connect", productType: "iPhone15,2")
        let watchPassive = HeartRateSample(date: origin.addingTimeInterval(90), bpm: 96, productType: "Watch7,1")
        let garmin = HeartRateSample(date: origin.addingTimeInterval(95), bpm: 140, sourceBundleID: "com.garmin.connect", productType: "iPhone15,2")
        let tagged = HeartRateOriginClassifier.tag([watchPassive, garmin], workouts: [garminWorkout])
        // 手表样本落在 Garmin 训练里：不是手表训练，只能是被动采样
        #expect(tagged.map(\.origin) == [.watchPassive, .otherWorkout])
        let grid = grid(tagged)
        #expect(grid.heartRate[1] == 140)
    }

    @Test("手表样本落在手表自己的训练中才算训练期间")
    func watchWorkoutRequiresWatchOwnedWorkout() {
        let watchWorkout = WorkoutSample(uuid: UUID(), activityType: "cycling", start: origin, end: origin.addingTimeInterval(600), productType: "Watch7,1")
        let inside = HeartRateSample(date: origin.addingTimeInterval(60), bpm: 130, productType: "Watch7,1")
        let tagged = HeartRateOriginClassifier.tag([inside], workouts: [watchWorkout])
        #expect(tagged.map(\.origin) == [.watchWorkout])
    }

    @Test("分类：训练区间内的 Apple Watch 心率为训练期间，区间外为被动采样")
    func classification() {
        let workout = WorkoutSample(uuid: UUID(), activityType: "cycling", start: origin, end: origin.addingTimeInterval(600), productType: "Watch7,1")
        let inside = HeartRateSample(date: origin.addingTimeInterval(60), bpm: 130, productType: "Watch7,1")
        let outside = HeartRateSample(date: origin.addingTimeInterval(1200), bpm: 70, productType: "Watch7,1")
        let garmin = HeartRateSample(date: origin.addingTimeInterval(120), bpm: 128, sourceBundleID: "com.garmin.connect", productType: "iPhone15,2")
        let tagged = HeartRateOriginClassifier.tag([inside, outside, garmin], workouts: [workout])
        #expect(tagged.map(\.origin) == [.watchWorkout, .watchPassive, .otherWorkout])
    }
}
