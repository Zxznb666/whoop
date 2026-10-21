import Foundation
import VigorScoring

/// 合成场景中注入的事件清单，供测试断言（施工文档 §4.8）。
/// 所有日期键都是醒来日的当地零点。
public struct SyntheticTruth: Sendable, Equatable {
    public var alcoholNights: Set<Date> = []
    public var lateDinnerNights: Set<Date> = []
    public var sickNights: Set<Date> = []
    public var napDays: Set<Date> = []
    public var missingNights: Set<Date> = []
    public var workoutDays: Set<Date> = []
    public var morningMeasurementNights: Set<Date> = []
    public var otherAppOverlapNights: Set<Date> = []
    public var noSeriesNights: Set<Date> = []

    public init() {}
}

/// 合成场景 v2：快照、日志与注入事件清单。同一种子、同一 `endingAt` 的结果完全可复现。
public struct SyntheticScenario: Sendable, Equatable {
    public var snapshot: HealthSnapshot
    public var journal: [JournalEntry]
    public var truth: SyntheticTruth

    /// 生成 `nights` 晚的合成场景，最后一晚醒来于 `endingAt` 所在的本地日期。
    public static func make(
        nights: Int = 120,
        seed: UInt64 = 42,
        endingAt: Date,
        calendar: Calendar
    ) -> SyntheticScenario {
        var builder = ScenarioBuilder(nights: nights, seed: seed, endingAt: endingAt, calendar: calendar)
        return builder.build()
    }
}

/// 每晚的规划（第一遍生成，决定所有随机属性；第二遍据此写样本）。
private struct NightPlan {
    var index: Int
    var wakeDay: Date
    var bedtime: Date
    var wake: Date
    var duration: TimeInterval
    var alcohol: Bool
    var lateDinner: Bool
    var energy: Int
    var sick: Bool
    var missing: Bool
    /// 同时作用于 RMSSD 与 SDNN：饮酒 × 0.82，生病 × 0.7
    var hrvScale: Double
    var workout: WorkoutPlan?
    var napStart: Date?
}

private struct WorkoutPlan {
    var type: String
    var start: Date
    var end: Date
}

private struct ScenarioBuilder {
    let nights: Int
    let calendar: Calendar
    let endingAt: Date
    var rng: SplitMix64
    var truth = SyntheticTruth()

    var sleep: [SleepStageSample] = []
    var inBed: [SleepStageSample] = []
    var heartRate: [HeartRateSample] = []
    var sdnn: [ValueSample] = []
    var restingHeartRate: [ValueSample] = []
    var respiratoryRate: [ValueSample] = []
    var wristTemperature: [ValueSample] = []
    var oxygenSaturation: [ValueSample] = []
    var series: [HeartbeatSeries] = []
    var mindful: [ValueSample] = []
    var workouts: [WorkoutSample] = []
    var activeEnergy: [ValueSample] = []
    var steps: [ValueSample] = []
    var vo2Max: [ValueSample] = []
    var heartRateRecovery: [ValueSample] = []
    var journal: [JournalEntry] = []

    init(nights: Int, seed: UInt64, endingAt: Date, calendar: Calendar) {
        self.nights = nights
        self.calendar = calendar
        self.endingAt = endingAt
        self.rng = SplitMix64(seed: seed)
    }

    mutating func build() -> SyntheticScenario {
        let plans = planNights()
        for (position, plan) in plans.enumerated() {
            let nextBedtime = position + 1 < plans.count ? plans[position + 1].bedtime : endingAt
            writeDaytime(plan, until: nextBedtime)
            journal.append(JournalEntry(
                night: plan.wakeDay,
                behaviors: ["alcohol": plan.alcohol, "lateDinner": plan.lateDinner],
                energy: plan.energy,
                // 用户没有在日志中确认“不适”，自动排除路径由生病信号触发
                feltUnwell: false
            ))
            recordTruth(plan)
            if plan.missing { continue }
            writeNight(plan)
        }

        let lastWakeDay = calendar.startOfDay(for: endingAt)
        let snapshot = HealthSnapshot(
            schemaVersion: HealthSnapshot.currentSchemaVersion,
            exportedAt: endingAt,
            rangeStart: calendar.date(byAdding: .day, value: -nights, to: lastWakeDay) ?? lastWakeDay,
            rangeEnd: endingAt,
            profile: UserProfile(birthYear: 1994, sex: .male, heightMeters: 1.75, weightKilograms: 70),
            sleep: sleep.sorted { $0.start < $1.start },
            inBed: inBed.sorted { $0.start < $1.start },
            heartRate: heartRate.sorted { $0.date < $1.date },
            hrvSDNN: sdnn.sorted { $0.start < $1.start },
            restingHeartRate: restingHeartRate.sorted { $0.start < $1.start },
            respiratoryRate: respiratoryRate.sorted { $0.start < $1.start },
            wristTemperature: wristTemperature.sorted { $0.start < $1.start },
            oxygenSaturation: oxygenSaturation.sorted { $0.start < $1.start },
            heartbeatSeries: series.sorted { $0.start < $1.start },
            mindfulSessions: mindful.sorted { $0.start < $1.start },
            workouts: workouts.sorted { $0.start < $1.start },
            activeEnergy: activeEnergy.sorted { $0.start < $1.start },
            steps: steps.sorted { $0.start < $1.start },
            vo2Max: vo2Max.sorted { $0.start < $1.start },
            heartRateRecovery: heartRateRecovery.sorted { $0.start < $1.start }
        )
        return SyntheticScenario(snapshot: snapshot, journal: journal, truth: truth)
    }

    // MARK: 第一遍：规划

    mutating func planNights() -> [NightPlan] {
        var plans: [NightPlan] = []
        var blockOffsets: Set<Int> = []
        let lastWakeDay = calendar.startOfDay(for: endingAt)

        for index in 0..<nights {
            guard let wakeDay = calendar.date(byAdding: .day, value: index - (nights - 1), to: lastWakeDay),
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: wakeDay)
            else { continue }

            if index % 7 == 0 {
                // 每周 3–4 次训练，随机分布在 7 天中（Fisher–Yates 洗牌）
                var offsets = Array(0..<7)
                for k in stride(from: 6, to: 0, by: -1) {
                    offsets.swapAt(k, rng.int(0...k))
                }
                blockOffsets = Set(offsets.prefix(rng.int(3...4)))
            }

            let bedtime = whole(previousDay.addingTimeInterval(23 * 3600 + rng.uniform(0...5400)))
            let duration = (rng.uniform(6.5...8.5) * 3600).rounded()
            let wake = bedtime.addingTimeInterval(duration)
            let sick = index == nights - 20 || index == nights - 19
            // 生病夜不饮酒：让生病的注入事件不与饮酒混杂（混杂的情形由测试单独覆盖）
            let alcohol = rng.chance(0.15) && !sick
            let lateDinner = rng.chance(0.10)
            let energy = rng.int(1...5)
            let missing = index == nights - 50

            var workout: WorkoutPlan?
            if blockOffsets.contains(index % 7) {
                let type = ["running", "cycling", "traditionalStrengthTraining"][rng.int(0...2)]
                let minutes = rng.uniform(30...75).rounded()
                let start = whole(wakeDay.addingTimeInterval(rng.uniform(17...19) * 3600))
                workout = WorkoutPlan(type: type, start: start, end: start.addingTimeInterval(minutes * 60))
            }

            var napStart: Date?
            if index % 7 == 4 {
                napStart = whole(wakeDay.addingTimeInterval((14 + rng.uniform(-0.25...0.25)) * 3600))
            }

            plans.append(NightPlan(
                index: index,
                wakeDay: wakeDay,
                bedtime: bedtime,
                wake: wake,
                duration: duration,
                alcohol: alcohol,
                lateDinner: lateDinner,
                energy: energy,
                sick: sick,
                missing: missing,
                hrvScale: (alcohol ? 0.82 : 1) * (sick ? 0.7 : 1),
                workout: workout,
                napStart: napStart
            ))
        }
        return plans
    }

    mutating func recordTruth(_ plan: NightPlan) {
        if plan.alcohol { truth.alcoholNights.insert(plan.wakeDay) }
        if plan.lateDinner { truth.lateDinnerNights.insert(plan.wakeDay) }
        if plan.sick { truth.sickNights.insert(plan.wakeDay) }
        if plan.missing { truth.missingNights.insert(plan.wakeDay) }
        if plan.workout != nil { truth.workoutDays.insert(plan.wakeDay) }
        if plan.napStart != nil { truth.napDays.insert(plan.wakeDay) }
    }

    // MARK: 白天：心率、活动、训练、小睡

    mutating func writeDaytime(_ plan: NightPlan, until end: Date) {
        let napInterval = plan.napStart.map { ($0, $0.addingTimeInterval(25 * 60)) }
        let workoutInterval = plan.workout.map { ($0.start, $0.end) }
        let excluded = [napInterval, workoutInterval].compactMap { $0 }

        if let nap = napInterval {
            sleep.append(watchSample(.core, start: nap.0, end: nap.1))
            for date in times(from: nap.0, to: nap.1, every: 300) {
                heartRate.append(HeartRateSample(date: date, bpm: rng.uniform(55...62)))
            }
        }

        for date in times(from: plan.wake, to: end, every: 300) where !excluded.contains(where: { contains(date, $0) }) {
            heartRate.append(HeartRateSample(date: date, bpm: rng.uniform(65...95)))
            let boost = rng.uniform(0...8)
            let stepCount = rng.uniform(0...120).rounded()
            activeEnergy.append(ValueSample(start: date, end: date.addingTimeInterval(300), value: boost.rounded()))
            steps.append(ValueSample(start: date, end: date.addingTimeInterval(300), value: stepCount))
        }

        if let workout = plan.workout {
            let minutes = workout.end.timeIntervalSince(workout.start) / 60
            let kilocalories = (minutes * 8).rounded()
            workouts.append(WorkoutSample(
                uuid: deterministicUUID(),
                activityType: workout.type,
                start: workout.start,
                end: workout.end,
                activeEnergyKilocalories: kilocalories,
                distanceMeters: workout.type == "traditionalStrengthTraining" ? nil : (minutes * 150).rounded()
            ))
            for date in times(from: workout.start, to: workout.end, every: 5) {
                heartRate.append(HeartRateSample(date: date, bpm: rng.uniform(130...170)))
            }
            heartRateRecovery.append(ValueSample(
                start: workout.end.addingTimeInterval(60),
                end: workout.end.addingTimeInterval(60),
                value: rng.uniform(22...38).rounded()
            ))
            activeEnergy.append(ValueSample(start: workout.start, end: workout.end, value: kilocalories))
        }

        if plan.index % 7 == 6 {
            let date = plan.wake.addingTimeInterval(3600)
            vo2Max.append(ValueSample(start: date, end: date, value: rng.uniform(40...46).rounded(toPlaces: 1)))
        }
    }

    // MARK: 夜间

    mutating func writeNight(_ plan: NightPlan) {
        let bedtime = plan.bedtime
        let wake = plan.wake
        let duration = plan.duration
        let scale = plan.hrvScale
        let rhrShift = (plan.alcohol ? 4.0 : 0) + (plan.sick ? 6.0 : 0)

        let stages = sleepStages(from: bedtime, duration: duration)
        for stage in stages {
            sleep.append(watchSample(stage.stage, start: stage.start, end: stage.end))
        }

        // 在床：iPhone 睡眠专注模式，比入睡早 5–25 分钟，醒来后 5 分钟结束
        inBed.append(SleepStageSample(
            start: whole(bedtime.addingTimeInterval(-rng.uniform(300...1500))),
            end: whole(wake.addingTimeInterval(300)),
            stage: .inBed,
            sourceBundleID: "com.apple.Health",
            sourceName: "iPhone",
            productType: "iPhone15,2",
            creationDate: whole(wake.addingTimeInterval(300)),
            timeZoneID: "Asia/Shanghai"
        ))

        // 其他 App 的分期：每 10 晚一晚，与手表的一段核心睡眠完全重叠（测试来源优先级）
        if plan.index % 10 == 7, let overlap = stages.first(where: { $0.stage == .core && $0.end.timeIntervalSince($0.start) >= 600 }) {
            sleep.append(SleepStageSample(
                start: overlap.start,
                end: overlap.end,
                stage: .core,
                sourceBundleID: "com.example.sleepapp",
                sourceName: "第三方睡眠 App",
                productType: nil,
                creationDate: whole(wake.addingTimeInterval(300)),
                timeZoneID: "Asia/Shanghai"
            ))
            truth.otherAppOverlapNights.insert(plan.wakeDay)
        }

        let lateDinnerBump: (Double) -> Double = { progress in
            plan.lateDinner ? 6 * max(0, 1.0 / 3.0 - progress) * 3 : 0
        }
        for date in times(from: bedtime, to: wake, every: 300) {
            let progress = date.timeIntervalSince(bedtime) / duration
            let bpm = 58 - 8 * progress + rhrShift + lateDinnerBump(progress) + rng.uniform(-2...2)
            heartRate.append(HeartRateSample(date: date, bpm: min(max(bpm, 46), 70)))
        }

        for _ in 0..<3 {
            let start = whole(bedtime.addingTimeInterval(rng.uniform(0.05...0.95) * duration))
            sdnn.append(ValueSample(start: start, end: start.addingTimeInterval(60), value: rng.uniform(25...60) * scale))
        }
        restingHeartRate.append(ValueSample(start: wake, end: wake, value: rng.uniform(50...58) + rhrShift))
        wristTemperature.append(ValueSample(
            start: wake.addingTimeInterval(-600),
            end: wake,
            value: rng.uniform(35.8...36.4) + (plan.sick ? 0.7 : 0)
        ))
        for date in times(from: bedtime, to: wake, every: 300) {
            let respiratory = rng.uniform(13...17) + (plan.sick ? 1.5 : 0)
            respiratoryRate.append(ValueSample(start: date, end: date.addingTimeInterval(300), value: respiratory))
        }
        for date in times(from: bedtime, to: wake, every: 1200) {
            let value = rng.chance(0.1) ? rng.uniform(0.89...0.92) : rng.uniform(0.94...0.99)
            oxygenSaturation.append(ValueSample(start: date, end: date.addingTimeInterval(60), value: value))
        }

        if plan.index % 10 == 3 {
            truth.noSeriesNights.insert(plan.wakeDay)
            return
        }
        let amplitude = rng.uniform(20...60)
        let period = rng.uniform(4...6)
        for _ in 0..<rng.int(4...10) {
            let start = whole(bedtime.addingTimeInterval(rng.uniform(600...(duration - 660))))
            series.append(heartbeatSeries(start: start, amplitude: amplitude, period: period, scale: scale))
        }
        if plan.index % 5 == 1 {
            // 晨测：醒后 20 分钟开始一段 60 秒序列，并写入一条正念记录与之重叠
            let start = wake.addingTimeInterval(1200)
            series.append(heartbeatSeries(start: whole(start), amplitude: amplitude, period: period, scale: 1))
            mindful.append(ValueSample(start: whole(start), end: whole(start.addingTimeInterval(120)), value: 1))
            truth.morningMeasurementNights.insert(plan.wakeDay)
        }
    }

    // MARK: 工具

    func watchSample(_ stage: SleepStage, start: Date, end: Date) -> SleepStageSample {
        SleepStageSample(
            start: start,
            end: end,
            stage: stage,
            sourceBundleID: "com.apple.health.watch",
            sourceName: "Apple Watch",
            productType: "Watch7,1",
            creationDate: whole(end.addingTimeInterval(300)),
            timeZoneID: "Asia/Shanghai"
        )
    }

    /// 约 90 分钟一个周期（core → deep → core → rem），前半夜深睡多、后半夜 REM 多，
    /// 穿插 2–4 段 3–8 分钟的清醒。
    mutating func sleepStages(from bedtime: Date, duration: TimeInterval) -> [(stage: SleepStage, start: Date, end: Date)] {
        var awakeCycles = [1, 2, 3, 4]
        for _ in 0..<rng.int(0...2) {
            awakeCycles.remove(at: rng.int(0...(awakeCycles.count - 1)))
        }

        var plan: [(stage: SleepStage, seconds: TimeInterval)] = []
        var elapsed: TimeInterval = 0
        var cycle = 0
        while elapsed < duration {
            cycle += 1
            let progress = elapsed / duration
            let phases: [(stage: SleepStage, seconds: TimeInterval)] = [
                (.core, rng.uniform(30...40) * 60),
                (.deep, max(5, 35 * (1 - progress) + rng.uniform(-5...5)) * 60),
                (.core, rng.uniform(10...15) * 60),
                (.rem, max(5, 10 + 25 * progress + rng.uniform(-4...4)) * 60),
            ]
            for phase in phases {
                let seconds = phase.seconds.rounded()
                plan.append((phase.stage, seconds))
                elapsed += seconds
            }
            if awakeCycles.contains(cycle), elapsed < duration - 1800 {
                let seconds = (rng.uniform(3...8) * 60).rounded()
                plan.append((.awake, seconds))
                elapsed += seconds
            }
        }

        let end = bedtime.addingTimeInterval(duration)
        var cursor = bedtime
        var result: [(stage: SleepStage, start: Date, end: Date)] = []
        for (stage, seconds) in plan where cursor < end {
            let stop = min(cursor.addingTimeInterval(seconds), end)
            result.append((stage, cursor, stop))
            cursor = stop
        }
        return result
    }

    /// 约 60 秒的逐拍序列。RR 基线 1050–1200 ms，叠加呼吸性窦性心律不齐（正弦）和随机噪声；
    /// `scale` 同时缩放振幅与噪声，从而缩放 RMSSD；约 3% 的拍注入 ±40% 的伪迹，约 1% 的拍 precededByGap。
    mutating func heartbeatSeries(start: Date, amplitude: Double, period: Double, scale: Double) -> HeartbeatSeries {
        let baseRR = rng.uniform(1050...1200)
        let phase = rng.uniform(0...(2 * Double.pi))
        var beats = [Beat(t: 0, precededByGap: false)]
        var time: TimeInterval = 0
        while time < 60 {
            var rr = baseRR + scale * (amplitude * sin(2 * Double.pi * time / period + phase) + rng.uniform(-15...15))
            if rng.chance(0.03) {
                rr *= rng.chance(0.5) ? 1.4 : 0.6
            }
            time += rr / 1000
            let gap = rng.chance(0.01)
            if gap {
                time += rng.uniform(2...5)
            }
            beats.append(Beat(t: time, precededByGap: gap))
        }
        return HeartbeatSeries(
            id: deterministicUUID(),
            start: start,
            end: start.addingTimeInterval(time.rounded(.up)),
            beats: beats
        )
    }

    mutating func deterministicUUID() -> UUID {
        var bytes: [UInt8] = []
        for word in [rng.next(), rng.next()] {
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
            }
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func contains(_ date: Date, _ interval: (Date, Date)) -> Bool {
        date >= interval.0 && date < interval.1
    }

    func whole(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded())
    }

    func times(from start: Date, to end: Date, every interval: TimeInterval) -> [Date] {
        var result: [Date] = []
        var current = start
        while current < end {
            result.append(current)
            current = current.addingTimeInterval(interval)
        }
        return result
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
