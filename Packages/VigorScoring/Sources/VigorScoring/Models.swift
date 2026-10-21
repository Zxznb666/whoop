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

/// 睡眠分期样本。来源信息用于判断来源优先级（PRD §5.2 步骤 1–2）。
public struct SleepStageSample: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    public var sourceBundleID: String?
    public var sourceName: String?
    /// 例如 "Watch7,1"、"iPhone15,2"；为空表示未知来源
    public var productType: String?
    public var creationDate: Date?
    public var timeZoneID: String?

    /// 由 productType 推导：Apple Watch 来源时为 true。
    public var sourceIsWatch: Bool {
        productType?.hasPrefix("Watch") == true
    }

    public init(
        start: Date,
        end: Date,
        stage: SleepStage,
        sourceBundleID: String? = nil,
        sourceName: String? = nil,
        productType: String? = nil,
        creationDate: Date? = nil,
        timeZoneID: String? = nil
    ) {
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.productType = productType
        self.creationDate = creationDate
        self.timeZoneID = timeZoneID
    }

    /// M0 兼容入口：只区分 Apple Watch 与其他来源。
    public init(start: Date, end: Date, stage: SleepStage, sourceIsWatch: Bool) {
        self.init(start: start, end: end, stage: stage, productType: sourceIsWatch ? "Watch7,1" : "iPhone15,2")
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

/// 呼吸紊乱：保存原始值与单位字符串，等真实数据到了再校准（施工文档 §4.7）。
public struct BreathingDisturbanceSample: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var value: Double
    public var unit: String

    public init(start: Date, end: Date, value: Double, unit: String) {
        self.start = start
        self.end = end
        self.value = value
        self.unit = unit
    }
}

public struct WorkoutSample: Codable, Sendable, Hashable {
    public var uuid: UUID
    /// HKWorkoutActivityType 的可读名称，例如 "running"、"cycling"、"traditionalStrengthTraining"
    public var activityType: String
    public var start: Date
    public var end: Date
    public var activeEnergyKilocalories: Double?
    public var distanceMeters: Double?

    public init(
        uuid: UUID,
        activityType: String,
        start: Date,
        end: Date,
        activeEnergyKilocalories: Double? = nil,
        distanceMeters: Double? = nil
    ) {
        self.uuid = uuid
        self.activityType = activityType
        self.start = start
        self.end = end
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.distanceMeters = distanceMeters
    }
}

public struct StateOfMindSample: Codable, Sendable, Hashable {
    public var date: Date
    /// −1…1
    public var valence: Double
    public var labels: [String]

    public init(date: Date, valence: Double, labels: [String]) {
        self.date = date
        self.valence = valence
        self.labels = labels
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
    public var heightMeters: Double?
    public var weightKilograms: Double?

    public init(birthYear: Int?, sex: BiologicalSex, heightMeters: Double? = nil, weightKilograms: Double? = nil) {
        self.birthYear = birthYear
        self.sex = sex
        self.heightMeters = heightMeters
        self.weightKilograms = weightKilograms
    }
}

/// 快照 schema v2。v1 的字段保持不变；v2 新增字段在解码 v1 时填空数组（见 `SnapshotCoding`）。
public struct HealthSnapshot: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var exportedAt: Date
    public var rangeStart: Date
    public var rangeEnd: Date
    public var profile: UserProfile
    public var sleep: [SleepStageSample]
    /// 在床样本，通常来自 iPhone 的睡眠专注模式
    public var inBed: [SleepStageSample]
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
    public var mindfulSessions: [ValueSample]
    public var workouts: [WorkoutSample]
    /// 单位 kcal
    public var activeEnergy: [ValueSample]
    /// 单位 步
    public var steps: [ValueSample]
    /// 单位 mL/(kg·min)
    public var vo2Max: [ValueSample]
    /// 1 分钟心率恢复，单位 bpm
    public var heartRateRecovery: [ValueSample]
    public var breathingDisturbances: [BreathingDisturbanceSample]
    /// 单位 分钟
    public var timeInDaylight: [ValueSample]
    /// 单位 mg
    public var dietaryCaffeine: [ValueSample]
    /// 单位 杯（标准饮品）
    public var alcoholicBeverages: [ValueSample]
    public var stateOfMind: [StateOfMindSample]

    public init(
        schemaVersion: Int = HealthSnapshot.currentSchemaVersion,
        exportedAt: Date,
        rangeStart: Date,
        rangeEnd: Date,
        profile: UserProfile,
        sleep: [SleepStageSample],
        inBed: [SleepStageSample] = [],
        heartRate: [HeartRateSample],
        hrvSDNN: [ValueSample],
        restingHeartRate: [ValueSample],
        respiratoryRate: [ValueSample],
        wristTemperature: [ValueSample],
        oxygenSaturation: [ValueSample],
        heartbeatSeries: [HeartbeatSeries],
        mindfulSessions: [ValueSample] = [],
        workouts: [WorkoutSample] = [],
        activeEnergy: [ValueSample] = [],
        steps: [ValueSample] = [],
        vo2Max: [ValueSample] = [],
        heartRateRecovery: [ValueSample] = [],
        breathingDisturbances: [BreathingDisturbanceSample] = [],
        timeInDaylight: [ValueSample] = [],
        dietaryCaffeine: [ValueSample] = [],
        alcoholicBeverages: [ValueSample] = [],
        stateOfMind: [StateOfMindSample] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.profile = profile
        self.sleep = sleep
        self.inBed = inBed
        self.heartRate = heartRate
        self.hrvSDNN = hrvSDNN
        self.restingHeartRate = restingHeartRate
        self.respiratoryRate = respiratoryRate
        self.wristTemperature = wristTemperature
        self.oxygenSaturation = oxygenSaturation
        self.heartbeatSeries = heartbeatSeries
        self.mindfulSessions = mindfulSessions
        self.workouts = workouts
        self.activeEnergy = activeEnergy
        self.steps = steps
        self.vo2Max = vo2Max
        self.heartRateRecovery = heartRateRecovery
        self.breathingDisturbances = breathingDisturbances
        self.timeInDaylight = timeInDaylight
        self.dietaryCaffeine = dietaryCaffeine
        self.alcoholicBeverages = alcoholicBeverages
        self.stateOfMind = stateOfMind
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, rangeStart, rangeEnd, profile, sleep, inBed, heartRate
        case hrvSDNN, restingHeartRate, respiratoryRate, wristTemperature, oxygenSaturation
        case heartbeatSeries, mindfulSessions, workouts, activeEnergy, steps, vo2Max
        case heartRateRecovery, breathingDisturbances, timeInDaylight, dietaryCaffeine
        case alcoholicBeverages, stateOfMind
    }

    /// v2 新增的数组字段缺失时（例如旧快照）按空数组处理。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        rangeStart = try c.decode(Date.self, forKey: .rangeStart)
        rangeEnd = try c.decode(Date.self, forKey: .rangeEnd)
        profile = try c.decode(UserProfile.self, forKey: .profile)
        sleep = try c.decode([SleepStageSample].self, forKey: .sleep)
        inBed = try c.decodeIfPresent([SleepStageSample].self, forKey: .inBed) ?? []
        heartRate = try c.decode([HeartRateSample].self, forKey: .heartRate)
        hrvSDNN = try c.decode([ValueSample].self, forKey: .hrvSDNN)
        restingHeartRate = try c.decode([ValueSample].self, forKey: .restingHeartRate)
        respiratoryRate = try c.decode([ValueSample].self, forKey: .respiratoryRate)
        wristTemperature = try c.decode([ValueSample].self, forKey: .wristTemperature)
        oxygenSaturation = try c.decode([ValueSample].self, forKey: .oxygenSaturation)
        heartbeatSeries = try c.decode([HeartbeatSeries].self, forKey: .heartbeatSeries)
        mindfulSessions = try c.decodeIfPresent([ValueSample].self, forKey: .mindfulSessions) ?? []
        workouts = try c.decodeIfPresent([WorkoutSample].self, forKey: .workouts) ?? []
        activeEnergy = try c.decodeIfPresent([ValueSample].self, forKey: .activeEnergy) ?? []
        steps = try c.decodeIfPresent([ValueSample].self, forKey: .steps) ?? []
        vo2Max = try c.decodeIfPresent([ValueSample].self, forKey: .vo2Max) ?? []
        heartRateRecovery = try c.decodeIfPresent([ValueSample].self, forKey: .heartRateRecovery) ?? []
        breathingDisturbances = try c.decodeIfPresent([BreathingDisturbanceSample].self, forKey: .breathingDisturbances) ?? []
        timeInDaylight = try c.decodeIfPresent([ValueSample].self, forKey: .timeInDaylight) ?? []
        dietaryCaffeine = try c.decodeIfPresent([ValueSample].self, forKey: .dietaryCaffeine) ?? []
        alcoholicBeverages = try c.decodeIfPresent([ValueSample].self, forKey: .alcoholicBeverages) ?? []
        stateOfMind = try c.decodeIfPresent([StateOfMindSample].self, forKey: .stateOfMind) ?? []
    }
}
