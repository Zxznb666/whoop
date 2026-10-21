import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("合成场景 v3：骑行")
struct SyntheticRideTests {
    static let endingAt: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    }()

    static func scenario() -> SyntheticScenario {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return SyntheticScenario.make(nights: 120, seed: 42, endingAt: endingAt, calendar: calendar)
    }

    /// Garmin 写入的骑行训练（每次骑行一条，与手表训练分开计数）。
    static func garminRides(_ snapshot: HealthSnapshot) -> [WorkoutSample] {
        snapshot.workouts.filter { $0.sourceBundleID == "com.garmin.connect.mobile" }
    }

    @Test("每周 2–3 次骑行：120 晚约 17 周，骑行次数在 35–52 之间")
    func rideFrequency() {
        let rides = Self.garminRides(Self.scenario().snapshot)
        #expect(rides.count >= 35 && rides.count <= 52, "骑行次数 \(rides.count)")
    }

    @Test("四类来源轮换：有 FIT 的骑行约一半，手表训练与 FIT 同时存在的骑行有心率样本")
    func fourCategories() {
        let scenario = Self.scenario()
        let rides = Self.garminRides(scenario.snapshot)
        // FIT 文件只在类别 0 与 1 中出现
        #expect(scenario.snapshot.importedRides.count > 0)
        let fitRatio = Double(scenario.snapshot.importedRides.count) / Double(rides.count)
        #expect(abs(fitRatio - 0.5) < 0.1, "FIT 占比 \(fitRatio)")
        // 类别 0 的 FIT 与手表都有心率；FIT 的心率每秒都有
        let withFITHeartRate = scenario.snapshot.importedRides.filter { $0.heartRate.contains { $0 != nil } }
        #expect(withFITHeartRate.count == scenario.snapshot.importedRides.count)
        // 手表训练（有 Watch 来源的骑行训练）约占一半的骑行
        let watchRides = scenario.snapshot.workouts.filter { $0.activityType == "cycling" && $0.productType?.hasPrefix("Watch") == true }
        #expect(watchRides.count > 0 && watchRides.count < rides.count)
    }

    @Test("类别 3：手表训练中有一段 10 分钟的心率掉线（没有 FIT 文件）")
    func heartRateDropoutInCategoryThree() {
        let scenario = Self.scenario()
        let watchRides = scenario.snapshot.workouts.filter { $0.activityType == "cycling" && $0.productType == "Watch7,1" }
        let dropouts = watchRides.compactMap { ride -> TimeInterval? in
            let samples = scenario.snapshot.heartRate
                .filter { $0.productType == "Watch7,1" && $0.date >= ride.start && $0.date <= ride.end }
                .map(\.date)
                .sorted()
            guard samples.count > 1 else { return nil }
            return zip(samples, samples.dropFirst()).map { $1.timeIntervalSince($0) }.max()
        }
        #expect(dropouts.contains { $0 >= 600 }, "最长间隔 \(dropouts.max() ?? 0) 秒")
    }

    @Test("骑行时段内没有白天的心率样本（只剩来源为骑行的样本）")
    func noDaytimeSamplesInsideRides() {
        let snapshot = Self.scenario().snapshot
        for ride in Self.garminRides(snapshot) {
            let daytime = snapshot.heartRate.filter {
                $0.sourceBundleID == nil && $0.date > ride.start && $0.date < ride.end
            }
            #expect(daytime.isEmpty)
        }
    }

    @Test("骑行的功率样本与 FIT 功率都存在，且功率在合理范围内")
    func powerRange() {
        let snapshot = Self.scenario().snapshot
        #expect(!snapshot.cyclingPower.isEmpty)
        #expect(snapshot.cyclingPower.allSatisfy { $0.value >= 150 && $0.value <= 260 })
        #expect(snapshot.importedRides.allSatisfy { ride in
            ride.power.compactMap { $0 }.allSatisfy { $0 >= 150 && $0 <= 260 }
        })
    }
}
