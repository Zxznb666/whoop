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
        // 整体复制后只替换需要裁剪的数组，保证 v2 新增字段不会丢失。
        var snapshot = source
        snapshot.rangeStart = from
        snapshot.rangeEnd = to
        snapshot.sleep = clip(source.sleep, from, to) { ($0.start, $0.end) }
        snapshot.inBed = clip(source.inBed, from, to) { ($0.start, $0.end) }
        snapshot.heartRate = source.heartRate.filter { $0.date >= from && $0.date <= to }
        snapshot.hrvSDNN = clip(source.hrvSDNN, from, to) { ($0.start, $0.end) }
        snapshot.restingHeartRate = clip(source.restingHeartRate, from, to) { ($0.start, $0.end) }
        snapshot.respiratoryRate = clip(source.respiratoryRate, from, to) { ($0.start, $0.end) }
        snapshot.wristTemperature = clip(source.wristTemperature, from, to) { ($0.start, $0.end) }
        snapshot.oxygenSaturation = clip(source.oxygenSaturation, from, to) { ($0.start, $0.end) }
        snapshot.heartbeatSeries = clip(source.heartbeatSeries, from, to) { ($0.start, $0.end) }
        snapshot.mindfulSessions = clip(source.mindfulSessions, from, to) { ($0.start, $0.end) }
        snapshot.workouts = clip(source.workouts, from, to) { ($0.start, $0.end) }
        snapshot.activeEnergy = clip(source.activeEnergy, from, to) { ($0.start, $0.end) }
        snapshot.steps = clip(source.steps, from, to) { ($0.start, $0.end) }
        snapshot.vo2Max = clip(source.vo2Max, from, to) { ($0.start, $0.end) }
        snapshot.heartRateRecovery = clip(source.heartRateRecovery, from, to) { ($0.start, $0.end) }
        snapshot.breathingDisturbances = clip(source.breathingDisturbances, from, to) { ($0.start, $0.end) }
        snapshot.timeInDaylight = clip(source.timeInDaylight, from, to) { ($0.start, $0.end) }
        snapshot.dietaryCaffeine = clip(source.dietaryCaffeine, from, to) { ($0.start, $0.end) }
        snapshot.alcoholicBeverages = clip(source.alcoholicBeverages, from, to) { ($0.start, $0.end) }
        snapshot.stateOfMind = source.stateOfMind.filter { $0.date >= from && $0.date <= to }
        progress(1, "完成")
        return snapshot
    }

    private func clip<T>(_ items: [T], _ from: Date, _ to: Date, _ range: (T) -> (Date, Date)) -> [T] {
        items.filter { item in
            let (start, end) = range(item)
            return end >= from && start <= to
        }
    }
}
