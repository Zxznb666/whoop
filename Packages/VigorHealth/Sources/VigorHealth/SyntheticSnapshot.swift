import Foundation
import VigorScoring

/// SplitMix64 伪随机数生成器。同一种子生成的序列完全一致，保证合成数据可复现。
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// [0, 1) 上的均匀分布。
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992
    }

    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }
}

public enum SyntheticSnapshot {
    /// 生成 `nights` 晚的合成快照，最后一晚醒来于 `endingAt` 所在的本地日期。
    ///
    /// 夜晚序号 `i % 10 == 3` 的夜晚没有心跳序列也没有晨测（用于覆盖 SDNN 兜底）；
    /// `i % 5 == 1` 的夜晚在醒来后 20 分钟有一段晨测序列。
    public static func make(
        nights: Int = 30,
        seed: UInt64 = 42,
        endingAt: Date,
        calendar: Calendar
    ) -> HealthSnapshot {
        var rng = SplitMix64(seed: seed)
        var sleep: [SleepStageSample] = []
        var heartRate: [HeartRateSample] = []
        var sdnn: [ValueSample] = []
        var restingHeartRate: [ValueSample] = []
        var respiratoryRate: [ValueSample] = []
        var wristTemperature: [ValueSample] = []
        var oxygenSaturation: [ValueSample] = []
        var series: [HeartbeatSeries] = []

        let lastWakeDay = calendar.startOfDay(for: endingAt)
        for index in 0..<nights {
            guard let wakeDay = calendar.date(byAdding: .day, value: index - (nights - 1), to: lastWakeDay),
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: wakeDay)
            else { continue }

            let bedtime = whole(previousDay.addingTimeInterval(23 * 3600 + rng.uniform(0...5400)))
            let duration = (rng.uniform(6.5...8.5) * 3600).rounded()
            let wake = bedtime.addingTimeInterval(duration)

            sleep += sleepStages(from: bedtime, duration: duration, rng: &rng)
            heartRate += heartRateSamples(from: bedtime, duration: duration, rng: &rng)

            for _ in 0..<3 {
                let start = whole(bedtime.addingTimeInterval(rng.uniform(0.05...0.95) * duration))
                sdnn.append(ValueSample(start: start, end: start.addingTimeInterval(60), value: rng.uniform(25...60)))
            }
            restingHeartRate.append(ValueSample(start: wake, end: wake, value: rng.uniform(50...58)))
            wristTemperature.append(ValueSample(
                start: wake.addingTimeInterval(-600),
                end: wake,
                value: rng.uniform(35.8...36.4)
            ))
            for date in times(from: bedtime, to: wake, every: 300) {
                respiratoryRate.append(ValueSample(start: date, end: date.addingTimeInterval(300), value: rng.uniform(13...17)))
            }
            for date in times(from: bedtime, to: wake, every: 1200) {
                let value = rng.chance(0.1) ? rng.uniform(0.89...0.92) : rng.uniform(0.94...0.99)
                oxygenSaturation.append(ValueSample(start: date, end: date.addingTimeInterval(60), value: value))
            }

            if index % 10 != 3 {
                let amplitude = rng.uniform(20...60)
                let period = rng.uniform(4...6)
                for _ in 0..<rng.int(4...10) {
                    let start = whole(bedtime.addingTimeInterval(rng.uniform(600...(duration - 660))))
                    series.append(heartbeatSeries(start: start, amplitude: amplitude, period: period, rng: &rng))
                }
                if index % 5 == 1 {
                    series.append(heartbeatSeries(
                        start: wake.addingTimeInterval(1200),
                        amplitude: amplitude,
                        period: period,
                        rng: &rng
                    ))
                }
            }
        }

        return HealthSnapshot(
            schemaVersion: 1,
            exportedAt: endingAt,
            rangeStart: calendar.date(byAdding: .day, value: -nights, to: lastWakeDay) ?? lastWakeDay,
            rangeEnd: endingAt,
            profile: UserProfile(birthYear: nil, sex: .unknown),
            sleep: sleep,
            heartRate: heartRate,
            hrvSDNN: sdnn,
            restingHeartRate: restingHeartRate,
            respiratoryRate: respiratoryRate,
            wristTemperature: wristTemperature,
            oxygenSaturation: oxygenSaturation,
            heartbeatSeries: series.sorted { $0.start < $1.start }
        )
    }

    /// 约 90 分钟一个周期（core → deep → core → rem），前半夜深睡多、后半夜 REM 多，
    /// 穿插 2–4 段 3–8 分钟的清醒。
    private static func sleepStages(from bedtime: Date, duration: TimeInterval, rng: inout SplitMix64) -> [SleepStageSample] {
        var awakeCycles = [1, 2, 3, 4]
        for _ in 0..<rng.int(0...2) {
            let index = rng.int(0...(awakeCycles.count - 1))
            awakeCycles.remove(at: index)
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
        var samples: [SleepStageSample] = []
        for (stage, seconds) in plan where cursor < end {
            let stop = min(cursor.addingTimeInterval(seconds), end)
            samples.append(SleepStageSample(start: cursor, end: stop, stage: stage, sourceIsWatch: true))
            cursor = stop
        }
        return samples
    }

    /// 睡眠期间每 5 分钟一个心率点，数值约 48–62，后半夜逐渐下降。
    private static func heartRateSamples(from bedtime: Date, duration: TimeInterval, rng: inout SplitMix64) -> [HeartRateSample] {
        times(from: bedtime, to: bedtime.addingTimeInterval(duration), every: 300).map { date in
            let progress = date.timeIntervalSince(bedtime) / duration
            let bpm = 58 - 8 * progress + rng.uniform(-2...2)
            return HeartRateSample(date: date, bpm: min(max(bpm, 48), 62))
        }
    }

    /// 约 60 秒的逐拍序列。RR 基线 1050–1200 ms，叠加呼吸性窦性心律不齐（正弦）和随机噪声；
    /// 约 3% 的拍注入 ±40% 的伪迹，约 1% 的拍 precededByGap。
    private static func heartbeatSeries(
        start: Date,
        amplitude: Double,
        period: Double,
        rng: inout SplitMix64
    ) -> HeartbeatSeries {
        let baseRR = rng.uniform(1050...1200)
        let phase = rng.uniform(0...(2 * Double.pi))
        var beats = [Beat(t: 0, precededByGap: false)]
        var time: TimeInterval = 0
        while time < 60 {
            var rr = baseRR + amplitude * sin(2 * Double.pi * time / period + phase) + rng.uniform(-15...15)
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
            id: deterministicUUID(rng: &rng),
            start: start,
            end: start.addingTimeInterval(time.rounded(.up)),
            beats: beats
        )
    }

    private static func deterministicUUID(rng: inout SplitMix64) -> UUID {
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

    /// 精确到整秒。Date 经 secondsSince1970 往返时，整秒值可以逐位相等。
    private static func whole(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded())
    }

    private static func times(from start: Date, to end: Date, every interval: TimeInterval) -> [Date] {
        var result: [Date] = []
        var current = start
        while current < end {
            result.append(current)
            current = current.addingTimeInterval(interval)
        }
        return result
    }
}
