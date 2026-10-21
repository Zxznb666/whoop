import Foundation
import Observation
import VigorStore
import WatchConnectivity
import WidgetKit

/// 手表端的数据：由手机经 WatchConnectivity 推送，写入本地缓存；收不到时显示上一次的缓存（PRD §6.8）。
@MainActor
@Observable
final class WatchStore: NSObject {
    static let shared = WatchStore()

    private(set) var state: SharedState?

    override init() {
        super.init()
        state = SharedStateStore.readLatest(groupID: VigorConstants.appGroupID)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 解码、缓存并刷新复杂功能。数据损坏时保留旧缓存。
    func receive(_ data: Data) {
        guard let decoded = try? SharedStateStore.decode(data) else { return }
        state = decoded
        do {
            try SharedStateStore.write(decoded, groupID: VigorConstants.appGroupID)
        } catch {
            // 缓存写失败不影响界面：内存中的状态仍然是最新的
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // 激活时手机可能已经推送过：取最近一次的上下文
        let data = session.receivedApplicationContext[SharedStateStore.watchPayloadKey] as? Data
        guard let data else { return }
        Task { @MainActor in WatchStore.shared.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[SharedStateStore.watchPayloadKey] as? Data
        guard let data else { return }
        Task { @MainActor in WatchStore.shared.receive(data) }
    }
}
