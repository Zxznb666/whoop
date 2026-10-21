import BackgroundTasks
import Foundation
import HealthKit

/// 后台任务与 HealthKit 观察者（PRD §5.14、施工文档 §5 阶段 5 第 2 条）。
/// 任何注册失败都只记录到诊断日志，不会导致崩溃。
enum BackgroundSync {
    static let taskIdentifier = "com.example.vigor.nightly"

    /// 必须在应用启动完成前调用。`runRefresh` 负责一次完整的刷新。
    static func register(runRefresh: @escaping @Sendable () async -> Void) {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // BGTask 不是 Sendable。它只在系统回调与 setTaskCompleted 之间使用，不存在并发访问（见 DECISIONS D-050）。
            nonisolated(unsafe) let completion = processing
            let work = Task {
                await runRefresh()
                completion.setTaskCompleted(success: true)
            }
            processing.expirationHandler = { work.cancel() }
            scheduleNext()
        }
        if !registered {
            DiagnosticsLog.record("后台任务注册失败：\(taskIdentifier)")
        }
    }

    /// 下一次凌晨 3 点左右运行一次全量重算。
    static func scheduleNext(now: Date = Date()) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        var calendar = Calendar.current
        calendar.timeZone = .current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        request.earliestBeginDate = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: tomorrow)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            DiagnosticsLog.record("后台任务提交失败：\(error.localizedDescription)")
        }
    }

    /// 对睡眠、HRV、心率、心跳序列、训练、手腕温度、呼吸率开启观察者与后台推送（睡眠与训练为 immediate，其余 hourly）。
    static func observe(store: HKHealthStore, onChange: @escaping @Sendable () -> Void) {
        let immediate: [HKSampleType] = [HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
        let hourly: [HKSampleType] = [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKSeriesType.heartbeat(),
            HKQuantityType(.appleSleepingWristTemperature),
            HKQuantityType(.respiratoryRate),
        ]
        for type in immediate {
            start(type, frequency: .immediate, store: store, onChange: onChange)
        }
        for type in hourly {
            start(type, frequency: .hourly, store: store, onChange: onChange)
        }
    }

    private static func start(
        _ type: HKSampleType,
        frequency: HKUpdateFrequency,
        store: HKHealthStore,
        onChange: @escaping @Sendable () -> Void
    ) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            if let error {
                DiagnosticsLog.record("观察者错误（\(type.identifier)）：\(error.localizedDescription)")
            } else {
                onChange()
            }
            completion()
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
            if let error {
                DiagnosticsLog.record("后台推送失败（\(type.identifier)）：\(error.localizedDescription)")
            } else if !success {
                DiagnosticsLog.record("后台推送未启用（\(type.identifier)）")
            }
        }
    }
}
