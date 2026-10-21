import Foundation
import VigorStore
import WatchConnectivity

/// 手机端的 WatchConnectivity（PRD §6.8）：每次刷新成功后，把共享状态推送给手表。
/// 手表不可达或推送失败时只记录日志；手表会显示上一次收到的缓存。
@MainActor
final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()
    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    /// 覆盖式推送：WatchConnectivity 只保留最新的一份上下文，适合“当前状态”。
    func push(_ state: SharedState) {
        guard let session, session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext([SharedStateStore.watchPayloadKey: try SharedStateStore.encode(state)])
        } catch {
            DiagnosticsLog.record("手表推送失败：\(error.localizedDescription)")
        }
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in DiagnosticsLog.record("WatchConnectivity 激活失败：\(error.localizedDescription)") }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // 切换手表后需要重新激活
        session.activate()
    }
}
