#if os(iOS) || os(watchOS)
import Foundation
import HealthKit
import VigorScoring

/// 从 HealthKit 读取真实数据。真机验证留给用户（模拟器没有 HealthKit 数据）。
public struct LiveHealthDataSource: HealthDataSource {
    public let kind = DataSourceKind.live
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
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
        let sleep = sleepSamples.compactMap { sample -> SleepStageSample? in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value),
                  let stage = Self.stage(for: value)
            else { return nil }
            return SleepStageSample(
                start: sample.startDate,
                end: sample.endDate,
                stage: stage,
                sourceIsWatch: Self.isWatch(sample)
            )
        }

        progress(0.2, "读取心跳序列")
        let seriesSamples: [HKSample] = try await fetch(
            .sample(type: HKSeriesType.heartbeat(), predicate: predicate)
        )
        let heartbeatSamples = seriesSamples.compactMap { $0 as? HKHeartbeatSeriesSample }
        var heartbeatSeries: [HeartbeatSeries] = []
        // 心跳序列读取开销大，逐个顺序执行。
        for (index, sample) in heartbeatSamples.enumerated() {
            var beats: [Beat] = []
            for try await heartbeat in HKHeartbeatSeriesQueryDescriptor(sample).results(for: store) {
                beats.append(Beat(t: heartbeat.timeIntervalSinceStart, precededByGap: heartbeat.precededByGap))
            }
            heartbeatSeries.append(HeartbeatSeries(
                id: sample.uuid,
                start: sample.startDate,
                end: sample.endDate,
                beats: beats
            ))
            progress(
                0.2 + 0.75 * Double(index + 1) / Double(heartbeatSamples.count),
                "读取心跳序列 \(index + 1)/\(heartbeatSamples.count)"
            )
        }

        progress(1, "完成")
        return HealthSnapshot(
            schemaVersion: 1,
            exportedAt: Date(),
            rangeStart: from,
            rangeEnd: to,
            profile: UserProfile(birthYear: birthYear(), sex: biologicalSex()),
            sleep: sleep,
            heartRate: heartRate,
            hrvSDNN: hrvSDNN,
            restingHeartRate: restingHeartRate,
            respiratoryRate: respiratoryRate,
            wristTemperature: wristTemperature,
            oxygenSaturation: oxygenSaturation,
            heartbeatSeries: heartbeatSeries
        )
    }

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.mindfulSession),
            HKSeriesType.heartbeat(),
            HKObjectType.workoutType(),
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
        ]
        for identifier in quantityIdentifiers {
            types.insert(HKQuantityType(identifier))
        }
        return types
    }

    private static var writeTypes: Set<HKSampleType> {
        [HKCategoryType(.mindfulSession)]
    }

    private static let countPerMinute = HKUnit.count().unitDivided(by: .minute())

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

    private static func stage(for value: HKCategoryValueSleepAnalysis) -> SleepStage? {
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

    private static func isWatch(_ sample: HKSample) -> Bool {
        sample.sourceRevision.productType?.hasPrefix("Watch") == true
    }
}
#endif
