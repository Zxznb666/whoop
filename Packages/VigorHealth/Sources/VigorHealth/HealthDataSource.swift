import Foundation
import VigorScoring

public enum DataSourceKind: String, Sendable {
    case live
    case synthetic
    case imported
}

public protocol HealthDataSource: Sendable {
    var kind: DataSourceKind { get }
    func requestAuthorization() async throws
    func snapshot(from: Date, to: Date, progress: @Sendable (Double, String) -> Void) async throws -> HealthSnapshot
}

public enum HealthDataError: LocalizedError {
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "当前设备无法读取健康数据。"
        }
    }
}
