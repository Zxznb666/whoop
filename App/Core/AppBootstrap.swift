import Foundation
import HealthKit
import VigorEngine
import VigorHealth
import VigorScoring
import VigorStore
import WidgetKit

/// 启动时的装配：注册后台任务、开启观察者，并提供统一的刷新入口。
@MainActor
final class AppBootstrap {
    static let shared = AppBootstrap()

    let environment = AppEnvironment()

    /// 正在执行的刷新；同一时间最多一个
    private var running: Task<Void, Never>?
    /// 刷新进行中到达的请求，合并成一次（取读取范围更大的模式）
    private var queuedMode: RefreshMode?
    /// HealthKit 观察者是否已开启；授权之前开启会失败且不会自动重试，所以要等授权后再开
    private var observersStarted = false

    /// 最近一次刷新的结果，供欢迎页显示导入是否成功
    enum RefreshOutcome {
        case success(cycleCount: Int, inventory: SnapshotInventory?)
        case failure(String)
        case notAuthorized
    }
    private(set) var lastOutcome: RefreshOutcome?

    /// 在应用启动时调用一次。注册失败只记录日志，不会崩溃。
    func start() {
        PhoneWatchLink.shared.activate()
        BackgroundSync.register {
            await AppBootstrap.shared.refreshNow(mode: .window(days: 30))
        }
        BackgroundSync.scheduleNext()
        Task { await startObserversIfAuthorized() }
    }

    /// 授权之后才开启观察者：启动时已授权就立即开启；否则由欢迎页在授权成功后调用。
    func startObserversIfAuthorized() async {
        guard !observersStarted else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            DiagnosticsLog.record("当前设备不支持 HealthKit，跳过后台观察者")
            return
        }
        guard await LiveHealthDataSource().authorizationRequested() else { return }
        observersStarted = true
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
        #if !targetEnvironment(simulator)
        // 还没弹出过授权时，读取一定失败；直接跳过，不往诊断日志里写一串“未授权”的错误
        guard await LiveHealthDataSource().authorizationRequested() else {
            lastOutcome = .notAuthorized
            return
        }
        #endif
        let settings = await currentSettings()
        do {
            let planned = try await sync.refresh(
                mode: mode,
                settings: settings,
                now: Date(),
                announcedRecovery: NotificationScheduler.announcedRecovery,
                sent: NotificationScheduler.sent
            )
            let reminders = await journalReminders(now: Date())
            let weekly = NotificationPlanner.weeklyReport(now: Date(), sent: NotificationScheduler.sent, calendar: .current)
            await NotificationScheduler.schedule(planned + reminders + weekly)
            await publishToWidgetsAndWatch()
            let status = await sync.status
            lastOutcome = .success(cycleCount: status.lastCycleCount, inventory: status.inventory)
            // 全量导入时把读到的数据条数记进诊断日志，便于判断“没数据”是权限问题还是识别问题
            if mode == .full, let inventory = status.inventory {
                DiagnosticsLog.record("全量导入：评分 \(status.lastCycleCount) 天；\(inventory.summary)")
            }
            // 让已经显示的界面（摘要等）重新读取存储；否则授权导入后仍显示授权前的空状态
            NotificationCenter.default.post(name: .vigorDataChanged, object: nil)
        } catch {
            lastOutcome = .failure(error.localizedDescription)
            DiagnosticsLog.record("刷新失败：\(error)")
        }
    }

    /// 评分设置：用户偏好（UserDefaults）加上存储中的手动修正与排除（F7）。
    /// 存储读取失败时只使用偏好，并记录诊断信息。
    func currentSettings() async -> ScoringSettings {
        var settings = ScoringSettings(
            baseSleepNeedHours: AppSettings.baseSleepNeedHours,
            maxHeartRate: AppSettings.maxHeartRateOverride,
            targetWakeMinutes: AppSettings.targetWakeMinutes,
            manualFTP: AppSettings.manualFTP,
            heartRateSourcePreferences: AppSettings.heartRateSourcePreferences
        )
        guard let repository = environment.repository else { return settings }
        do {
            settings.sleepOverrides = try await repository.sleepOverrides()
            settings.manualExcludedNights = try await repository.manualExclusions()
            settings.importedRides = try await repository.importedRides()
        } catch {
            DiagnosticsLog.record("读取手动修正失败：\(error)")
        }
        return settings
    }

    /// 刷新成功后：补充手表训练需要的心率参数，写回共享状态，推送给手表并刷新小组件。
    /// App Group 不可用时小组件会显示“打开元气以更新”，这里不报错。
    private func publishToWidgetsAndWatch() async {
        guard var state = SharedStateStore.readLatest(groupID: VigorConstants.appGroupID) else { return }
        if let repository = environment.repository,
           let latest = try? await repository.cycles(from: Date().addingTimeInterval(-86_400), to: Date()).last {
            state.restingHeartRate = latest.load.restingHeartRate
            state.maxHeartRate = latest.load.maxHeartRate
        }
        do {
            try SharedStateStore.write(state, groupID: VigorConstants.appGroupID)
        } catch {
            DiagnosticsLog.record("共享状态回写失败：\(error)")
        }
        PhoneWatchLink.shared.push(state)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 醒来后的日志提醒（PRD §6.5）。读取失败只记录，不影响恢复分数的通知。
    private func journalReminders(now: Date) async -> [PlannedNotification] {
        guard let repository = environment.repository else { return [] }
        do {
            let calendar = Calendar.current
            let latest = try await repository.cycles(from: now.addingTimeInterval(-86_400), to: now).last
            let journal = try await repository.journal(from: now.addingTimeInterval(-7 * 86_400), to: now)
            return NotificationPlanner.journalReminder(
                latestWake: latest?.wakeTime,
                journaledNights: Set(journal.map(\.night)),
                sent: NotificationScheduler.sent,
                now: now,
                calendar: calendar
            )
        } catch {
            DiagnosticsLog.record("日志提醒计算失败：\(error)")
            return []
        }
    }
}
