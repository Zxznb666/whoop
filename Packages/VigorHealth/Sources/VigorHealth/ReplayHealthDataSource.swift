import Foundation
import VigorScoring

/// 用已有快照回放数据，供模拟器与离线分析使用。
public struct ReplayHealthDataSource: HealthDataSource {
    public let kind: DataSourceKind
    private let source: HealthSnapshot

    public init(snapshot: HealthSnapshot, kind: DataSourceKind = .imported) {
        precondition(kind != .live, "回放数据源只能是 synthetic 或 imported")
        self.kind = kind
        self.source = snapshot
    }

    public func requestAuthorization() async throws {}

    public func snapshot(
        from: Date,
        to: Date,
        progress: @Sendable (Double, String) -> Void
    ) async throws -> HealthSnapshot {
        progress(0, "读取快照")
        let snapshot = HealthSnapshot(
            schemaVersion: source.schemaVersion,
            exportedAt: source.exportedAt,
            rangeStart: from,
            rangeEnd: to,
            profile: source.profile,
            sleep: source.sleep.filter { overlaps($0.start, $0.end, from, to) },
            heartRate: source.heartRate.filter { $0.date >= from && $0.date <= to },
            hrvSDNN: source.hrvSDNN.filter { overlaps($0.start, $0.end, from, to) },
            restingHeartRate: source.restingHeartRate.filter { overlaps($0.start, $0.end, from, to) },
            respiratoryRate: source.respiratoryRate.filter { overlaps($0.start, $0.end, from, to) },
            wristTemperature: source.wristTemperature.filter { overlaps($0.start, $0.end, from, to) },
            oxygenSaturation: source.oxygenSaturation.filter { overlaps($0.start, $0.end, from, to) },
            heartbeatSeries: source.heartbeatSeries.filter { overlaps($0.start, $0.end, from, to) }
        )
        progress(1, "完成")
        return snapshot
    }

    private func overlaps(_ start: Date, _ end: Date, _ from: Date, _ to: Date) -> Bool {
        end >= from && start <= to
    }
}
