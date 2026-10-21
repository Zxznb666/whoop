#if os(iOS) || os(watchOS)
import Foundation
import HealthKit
import VigorScoring

/// 从 HealthKit 读取真实数据（schema v2）。真机验证留给用户（模拟器没有 HealthKit 数据）。
public struct LiveHealthDataSource: HealthDataSource {
    public let kind = DataSourceKind.live
    private let store: HKHealthStore
    /// 心跳序列的本地缓存；为 nil 时每次都从 HealthKit 读取
    private let heartbeatCache: HeartbeatCache?

    public init(store: HKHealthStore = HKHealthStore(), heartbeatCache: HeartbeatCache? = nil) {
        self.store = store
        self.heartbeatCache = heartbeatCache
    }

    public func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
    }

    public func snapshot(
        from: Date,
        to: Date,
        progress: @Sendable (Double, String) -> Void
    ) async throws -> HealthSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.unavailable
        }
        progress(0, "读取健康数据")
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])

        let heartRateSamples: [HKQuantitySample] = try await fetch(
            .quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)
        )
        let heartRate = heartRateSamples.map {
            HeartRateSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: Self.countPerMinute))
        }
        let hrvSDNN = try await quantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: predicate)
        let restingHeartRate = try await quantity(.restingHeartRate, unit: Self.countPerMinute, predicate: predicate)
        let respiratoryRate = try await quantity(.respiratoryRate, unit: Self.countPerMinute, predicate: predicate)
        let wristTemperature = try await quantity(.appleSleepingWristTemperature, unit: .degreeCelsius(), predicate: predicate)
        let oxygenSaturation = try await quantity(.oxygenSaturation, unit: .percent(), predicate: predicate)

        let sleepSamples: [HKCategorySample] = try await fetch(
            .categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)
        )
        var sleep: [SleepStageSample] = []
        var inBed: [SleepStageSample] = []
        for sample in sleepSamples {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            if value == .inBed {
                inBed.append(Self.sleepSample(.inBed, from: sample))
            } else if let stage = Self.stage(for: value) {
                sleep.append(Self.sleepSample(stage, from: sample))
            }
        }

        let mindfulSamples: [HKCategorySample] = try await fetch(
            .categorySample(type: HKCategoryType(.mindfulSession), predicate: predicate)
        )
        let mindfulSessions = mindfulSamples.map {
            ValueSample(start: $0.startDate, end: $0.endDate, value: $0.endDate.timeIntervalSince($0.startDate))
        }

        let workoutSamples: [HKWorkout] = try await fetch(.workout(predicate))
        let workouts = workoutSamples.map { workout in
            WorkoutSample(
                uuid: workout.uuid,
                activityType: Self.workoutName(workout.workoutActivityType),
                start: workout.startDate,
                end: workout.endDate,
                activeEnergyKilocalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie()),
                distanceMeters: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                    .sumQuantity()?.doubleValue(for: .meter())
            )
        }

        let activeEnergy = try await quantity(.activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        let steps = try await quantity(.stepCount, unit: .count(), predicate: predicate)
        let vo2Max = try await quantity(.vo2Max, unit: Self.vo2Unit, predicate: predicate)
        let heartRateRecovery = try await quantity(.heartRateRecoveryOneMinute, unit: Self.countPerMinute, predicate: predicate)
        let breathingSamples: [HKQuantitySample] = try await fetch(
            .quantitySample(type: HKQuantityType(.appleSleepingBreathingDisturbances), predicate: predicate)
        )
        let breathingDisturbances = breathingSamples.map {
            BreathingDisturbanceSample(
                start: $0.startDate,
                end: $0.endDate,
                value: $0.quantity.doubleValue(for: .count()),
                unit: "count"
            )
        }
        let timeInDaylight = try await quantity(.timeInDaylight, unit: .minute(), predicate: predicate)
        let dietaryCaffeine = try await quantity(.dietaryCaffeine, unit: .gramUnit(with: .milli), predicate: predicate)
        let alcoholicBeverages = try await quantity(.numberOfAlcoholicBeverages, unit: .count(), predicate: predicate)

        let stateOfMindSamples: [HKStateOfMind] = try await fetch(.stateOfMind(predicate))
        let stateOfMind = stateOfMindSamples.map {
            StateOfMindSample(date: $0.startDate, valence: $0.valence, labels: $0.labels.map { String(describing: $0) })
        }

        progress(0.2, "读取心跳序列")
        let seriesSamples: [HKSample] = try await fetch(
            .sample(type: HKSeriesType.heartbeat(), predicate: predicate)
        )
        let heartbeatSamples = seriesSamples.compactMap { $0 as? HKHeartbeatSeriesSample }
        var heartbeatSeries: [HeartbeatSeries] = []
        // 心跳序列读取开销大：先查本地缓存，未命中再逐个顺序读取并写回缓存。
        for (index, sample) in heartbeatSamples.enumerated() {
            if let cached = try? await heartbeatCache?.load(sample.uuid) {
                heartbeatSeries.append(cached)
            } else {
                var beats: [Beat] = []
                for try await heartbeat in HKHeartbeatSeriesQueryDescriptor(sample).results(for: store) {
                    beats.append(Beat(t: heartbeat.timeIntervalSinceStart, precededByGap: heartbeat.precededByGap))
                }
                let series = HeartbeatSeries(
                    id: sample.uuid,
                    start: sample.startDate,
                    end: sample.endDate,
                    beats: beats
                )
                try? await heartbeatCache?.store(series)
                heartbeatSeries.append(series)
            }
            progress(
                0.2 + 0.75 * Double(index + 1) / Double(heartbeatSamples.count),
                "读取心跳序列 \(index + 1)/\(heartbeatSamples.count)"
            )
        }

        let height = try await latestQuantity(.height, unit: .meter())
        let weight = try await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))

        progress(1, "完成")
        return HealthSnapshot(
            schemaVersion: HealthSnapshot.currentSchemaVersion,
            exportedAt: Date(),
            rangeStart: from,
            rangeEnd: to,
            profile: UserProfile(
                birthYear: birthYear(),
                sex: biologicalSex(),
                heightMeters: height,
                weightKilograms: weight
            ),
            sleep: sleep,
            inBed: inBed,
            heartRate: heartRate,
            hrvSDNN: hrvSDNN,
            restingHeartRate: restingHeartRate,
            respiratoryRate: respiratoryRate,
            wristTemperature: wristTemperature,
            oxygenSaturation: oxygenSaturation,
            heartbeatSeries: heartbeatSeries,
            mindfulSessions: mindfulSessions,
            workouts: workouts,
            activeEnergy: activeEnergy,
            steps: steps,
            vo2Max: vo2Max,
            heartRateRecovery: heartRateRecovery,
            breathingDisturbances: breathingDisturbances,
            timeInDaylight: timeInDaylight,
            dietaryCaffeine: dietaryCaffeine,
            alcoholicBeverages: alcoholicBeverages,
            stateOfMind: stateOfMind
        )
    }

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.mindfulSession),
            HKSeriesType.heartbeat(),
            HKObjectType.workoutType(),
            HKObjectType.stateOfMindType(),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
            HKQuantityType(.heartRate),
        ]
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .respiratoryRate,
            .oxygenSaturation,
            .appleSleepingWristTemperature,
            .appleSleepingBreathingDisturbances,
            .heartRateRecoveryOneMinute,
            .activeEnergyBurned,
            .stepCount,
            .vo2Max,
            .timeInDaylight,
            .dietaryCaffeine,
            .numberOfAlcoholicBeverages,
            .distanceWalkingRunning,
            .height,
            .bodyMass,
        ]
        for identifier in quantityIdentifiers {
            types.insert(HKQuantityType(identifier))
        }
        return types
    }

    /// 写入权限只包括正念记录（晨测）与训练记录（手表训练模式）。
    static var writeTypes: Set<HKSampleType> {
        [HKCategoryType(.mindfulSession), HKObjectType.workoutType()]
    }

    private static let countPerMinute = HKUnit.count().unitDivided(by: .minute())
    private static let vo2Unit = HKUnit(from: "ml/kg*min")

    private func fetch<Sample: HKSample>(_ predicate: HKSamplePredicate<Sample>) async throws -> [Sample] {
        try await HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        .result(for: store)
    }

    private func quantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async throws -> [ValueSample] {
        let samples: [HKQuantitySample] = try await fetch(
            .quantitySample(type: HKQuantityType(identifier), predicate: predicate)
        )
        return samples.map {
            ValueSample(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        let samples: [HKQuantitySample] = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        .result(for: store)
        return samples.first?.quantity.doubleValue(for: unit)
    }

    private func birthYear() -> Int? {
        try? store.dateOfBirthComponents().year
    }

    private func biologicalSex() -> BiologicalSex {
        guard let object = try? store.biologicalSex() else { return .unknown }
        switch object.biologicalSex {
        case .female: return .female
        case .male: return .male
        case .other: return .other
        default: return .unknown
        }
    }

    static func stage(for value: HKCategoryValueSleepAnalysis) -> SleepStage? {
        switch value {
        case .inBed: .inBed
        case .awake: .awake
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepREM: .rem
        case .asleepUnspecified: .asleepUnspecified
        default: nil
        }
    }

    static func sleepSample(_ stage: SleepStage, from sample: HKCategorySample) -> SleepStageSample {
        SleepStageSample(
            start: sample.startDate,
            end: sample.endDate,
            stage: stage,
            sourceBundleID: sample.sourceRevision.source.bundleIdentifier,
            sourceName: sample.sourceRevision.source.name,
            productType: sample.sourceRevision.productType,
            // HealthKit SDK 未暴露创建时间，留空（见 DECISIONS）
            creationDate: nil,
            timeZoneID: sample.metadata?[HKMetadataKeyTimeZone] as? String
        )
    }

    static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "running"
        case .cycling: "cycling"
        case .walking: "walking"
        case .hiking: "hiking"
        case .traditionalStrengthTraining: "traditionalStrengthTraining"
        case .functionalStrengthTraining: "functionalStrengthTraining"
        case .highIntensityIntervalTraining: "highIntensityIntervalTraining"
        default: "activity\(type.rawValue)"
        }
    }
}
#endif
