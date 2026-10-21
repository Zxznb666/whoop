import Foundation
import HealthKit
import VigorEngine

/// 启动时的装配：注册后台任务、开启观察者，并提供统一的刷新入口。
@MainActor
final class AppBootstrap {
    static let shared = AppBootstrap()

    let environment = AppEnvironment()
    private let historyDays = 180

    /// 在应用启动时调用一次。注册失败只记录日志，不会崩溃。
    func start() {
        BackgroundSync.register {
            await AppBootstrap.shared.refreshNow()
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            DiagnosticsLog.record("当前设备不支持 HealthKit，跳过后台观察者")
            return
        }
        BackgroundSync.observe(store: HKHealthStore()) {
            Task { await AppBootstrap.shared.refreshNow() }
        }
    }

    /// 读取近 180 天的数据，评分，持久化，写共享状态，并发送通知。
    func refreshNow(now: Date = Date()) async {
        guard let sync = environment.sync else {
            DiagnosticsLog.record("刷新跳过：存储未就绪")
            return
        }
        let start = Calendar.current.date(byAdding: .day, value: -historyDays, to: now) ?? now
        do {
            let planned = try await sync.refresh(
                from: start,
                to: now,
                now: now,
                announcedRecovery: NotificationScheduler.announcedRecovery,
                sent: NotificationScheduler.sent
            )
            await NotificationScheduler.schedule(planned)
        } catch {
            DiagnosticsLog.record("刷新失败：\(error)")
        }
    }
}
