import Foundation

public enum SleepStage: String, Codable, Sendable, Hashable {
    case inBed
    case awake
    case core
    case deep
    case rem
    case asleepUnspecified

    public var isAsleep: Bool {
        self == .core || self == .deep || self == .rem || self == .asleepUnspecified
    }
}

public struct SleepStageSample: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    public var sourceIsWatch: Bool

    public init(start: Date, end: Date, stage: SleepStage, sourceIsWatch: Bool) {
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceIsWatch = sourceIsWatch
    }
}

public struct HeartRateSample: Codable, Sendable, Hashable {
    public var date: Date
    public var bpm: Double

    public init(date: Date, bpm: Double) {
        self.date = date
        self.bpm = bpm
    }
}

public struct ValueSample: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var value: Double

    public init(start: Date, end: Date, value: Double) {
        self.start = start
        self.end = end
        self.value = value
    }
}

/// t 为距序列开始的秒数。
public struct Beat: Codable, Sendable, Hashable {
    public var t: TimeInterval
    public var precededByGap: Bool

    public init(t: TimeInterval, precededByGap: Bool) {
        self.t = t
        self.precededByGap = precededByGap
    }
}

public struct HeartbeatSeries: Codable, Sendable, Hashable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var beats: [Beat]

    public init(id: UUID, start: Date, end: Date, beats: [Beat]) {
        self.id = id
        self.start = start
        self.end = end
        self.beats = beats
    }
}

public enum BiologicalSex: String, Codable, Sendable, Hashable {
    case male
    case female
    case other
    case unknown
}

public struct UserProfile: Codable, Sendable, Hashable {
    public var birthYear: Int?
    public var sex: BiologicalSex

    public init(birthYear: Int?, sex: BiologicalSex) {
        self.birthYear = birthYear
        self.sex = sex
    }
}

public struct HealthSnapshot: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var rangeStart: Date
    public var rangeEnd: Date
    public var profile: UserProfile
    public var sleep: [SleepStageSample]
    public var heartRate: [HeartRateSample]
    /// 单位 ms
    public var hrvSDNN: [ValueSample]
    /// 单位 bpm
    public var restingHeartRate: [ValueSample]
    /// 单位 次/分
    public var respiratoryRate: [ValueSample]
    /// 单位 °C
    public var wristTemperature: [ValueSample]
    /// 0–1 的小数
    public var oxygenSaturation: [ValueSample]
    public var heartbeatSeries: [HeartbeatSeries]

    public init(
        schemaVersion: Int,
        exportedAt: Date,
        rangeStart: Date,
        rangeEnd: Date,
        profile: UserProfile,
        sleep: [SleepStageSample],
        heartRate: [HeartRateSample],
        hrvSDNN: [ValueSample],
        restingHeartRate: [ValueSample],
        respiratoryRate: [ValueSample],
        wristTemperature: [ValueSample],
        oxygenSaturation: [ValueSample],
        heartbeatSeries: [HeartbeatSeries]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.profile = profile
        self.sleep = sleep
        self.heartRate = heartRate
        self.hrvSDNN = hrvSDNN
        self.restingHeartRate = restingHeartRate
        self.respiratoryRate = respiratoryRate
        self.wristTemperature = wristTemperature
        self.oxygenSaturation = oxygenSaturation
        self.heartbeatSeries = heartbeatSeries
    }
}
