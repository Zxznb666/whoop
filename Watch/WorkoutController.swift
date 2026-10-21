import Foundation
import HealthKit
import Observation
import VigorScoring
import VigorStore

/// 训练模式（PRD §6.8）：`HKWorkoutSession` + `HKLiveWorkoutBuilder`。
/// 实时负荷直接使用 `VigorScoring` 的 TRIMP 函数，与手机端的周期负荷口径一致；结束后 HealthKit 保存训练记录。
@MainActor
@Observable
final class WorkoutController: NSObject {
    static let activities: [(type: HKWorkoutActivityType, title: String)] = [
        (.running, "跑步"),
        (.cycling, "骑行"),
        (.traditionalStrengthTraining, "力量"),
    ]

    private(set) var isRunning = false
    private(set) var heartRate: Double?
    /// 当前心率所在的区间（0–4，对应 Z1–Z5）
    private(set) var zoneIndex: Int?
    private(set) var sessionTRIMP = 0.0
    private(set) var startedAt: Date?
    private(set) var errorText: String?

    private var resting = 60.0
    private var maximum = 184.0
    /// 训练开始前的全天累积负荷（手机同步时的值）
    private var dayBaseStrain = 0.0
    private var lastSampleAt: Date?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// 本次训练的负荷（与周期负荷同一公式）。
    var sessionStrain: Double { Strain.strain(fromTRIMP: sessionTRIMP) }

    /// 全天累积负荷的估算：手机上次同步的负荷 + 本次训练。手机未同步时只显示本次训练。
    var dayStrain: Double { dayBaseStrain + sessionStrain }

    func start(_ activity: HKWorkoutActivityType, state: SharedState?) async {
        guard !isRunning else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            errorText = "当前设备无法使用健康数据"
            return
        }
        resting = state?.restingHeartRate ?? 60
        maximum = state?.maxHeartRate ?? MaxHeartRate.initial(birthYear: nil, year: Calendar.current.component(.year, from: Date()))
        dayBaseStrain = state?.strain ?? 0
        do {
            try await healthStore.requestAuthorization(
                toShare: [HKWorkoutType.workoutType()],
                read: [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKWorkoutType.workoutType()]
            )
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activity
            configuration.locationType = .unknown
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            self.session = session
            self.builder = builder
            sessionTRIMP = 0
            lastSampleAt = now
            startedAt = now
            errorText = nil
            isRunning = true
        } catch {
            errorText = "无法开始训练：\(error.localizedDescription)"
        }
    }

    func end() async {
        guard let session, let builder else { return }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
        } catch {
            errorText = "保存训练失败：\(error.localizedDescription)"
        }
        self.session = nil
        self.builder = nil
        isRunning = false
        heartRate = nil
        zoneIndex = nil
    }

    /// 每个心率样本：按与上一个样本的时间间隔累积 TRIMP（间隔超过 15 秒视为缺测，只计 15 秒）。
    private func ingest(bpm: Double, at date: Date) {
        heartRate = bpm
        let hrr = Strain.hrr(heartRate: bpm, restingHeartRate: resting, maxHeartRate: maximum)
        zoneIndex = Strain.zoneIndex(hrr: hrr)
        let seconds = lastSampleAt.map { min(max(date.timeIntervalSince($0), 0), 15) } ?? 0
        sessionTRIMP += Strain.trimpPerMinute(hrr: hrr, sex: .other) * seconds / 60
        lastSampleAt = date
    }
}

extension WorkoutController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let quantity = workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()
        else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let date = Date()
        Task { @MainActor in self.ingest(bpm: bpm, at: date) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WorkoutController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.errorText = "训练出错：\(message)" }
    }
}
