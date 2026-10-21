import Foundation
import VigorEngine
import VigorHealth
import VigorScoring
import VigorStore

/// 应用的依赖装配：持久化、同步引擎与数据源。模拟器使用合成数据，真机使用实时 HealthKit（PRD §8.4）。
@MainActor
final class AppEnvironment {
    private(set) var repository: ScoreRepository?
    private(set) var sync: SyncEngine?
    private(set) var setupError: String?

    init(calendar: Calendar = .current) {
        do {
            let container = try VigorStoreFactory.makeContainer()
            let repository = ScoreRepository(modelContainer: container)
            self.repository = repository
            self.sync = SyncEngine(source: Self.defaultSource(), repository: repository, calendar: calendar)
        } catch {
            setupError = error.localizedDescription
            DiagnosticsLog.record("存储初始化失败：\(error)")
        }
    }

    static func defaultSource() -> any HealthDataSource {
        #if targetEnvironment(simulator)
        let snapshot = SyntheticScenario.make(nights: 120, endingAt: Date(), calendar: .current).snapshot
        return ReplayHealthDataSource(snapshot: snapshot, kind: .synthetic)
        #else
        return LiveHealthDataSource()
        #endif
    }
}
