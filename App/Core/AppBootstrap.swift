import Foundation
import HealthKit
import VigorEngine

/// 启动时的装配：注册后台任务、开启观察者，并提供统一的刷新入口。
@MainActor
final class AppBootstrap {
    static let shared = AppBootstrap()

    let environment = AppEnvironment()

    /// 正在执行的刷新；同一时间最多一个
    private var running: Task<Void, Never>?
    /// 刷新进行中到达的请求，合并成一次（取读取范围更大的模式）
    private var queuedMode: RefreshMode?

    /// 在应用启动时调用一次。注册失败只记录日志，不会崩溃。
    func start() {
        BackgroundSync.register {
            await AppBootstrap.shared.refreshNow(mode: .window(days: 30))
        }
        BackgroundSync.scheduleNext()
        guard HKHealthStore.isHealthDataAvailable() else {
            DiagnosticsLog.record("当前设备不支持 HealthKit，跳过后台观察者")
            return
        }
        BackgroundSync.observe(store: HKHealthStore()) {
            await AppBootstrap.shared.refreshNow()
        }
    }

    /// 刷新并评分，写共享状态，发送通知。
    ///
    /// 观察者在启动时会同时触发多次：进行中到达的请求不另起一次读取，而是在当前刷新结束后合并补跑一次。
    /// 返回时，包括本次请求在内的所有排队请求都已处理完。
    func refreshNow(mode: RefreshMode = .incremental) async {
        queuedMode = RefreshMode.stronger(queuedMode, mode)
        if running == nil {
            running = Task {
                while let next = self.queuedMode {
                    self.queuedMode = nil
                    await self.perform(next)
                }
                self.running = nil
            }
        }
        await running?.value
    }

    private func perform(_ mode: RefreshMode) async {
        guard let sync = environment.sync else {
            DiagnosticsLog.record("刷新跳过：存储未就绪")
            return
        }
        let settings = ScoringSettings(
            baseSleepNeedHours: AppSettings.baseSleepNeedHours,
            maxHeartRate: AppSettings.maxHeartRateOverride,
            targetWakeMinutes: AppSettings.targetWakeMinutes
        )
        do {
            let planned = try await sync.refresh(
                mode: mode,
                settings: settings,
                now: Date(),
                announcedRecovery: NotificationScheduler.announcedRecovery,
                sent: NotificationScheduler.sent
            )
            await NotificationScheduler.schedule(planned)
        } catch {
            DiagnosticsLog.record("刷新失败：\(error)")
        }
    }
}
