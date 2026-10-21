import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("ReplayHealthDataSource")
struct ReplayHealthDataSourceTests {
    @Test("按时间裁剪快照，只保留范围内的样本")
    func trimsToRange() async throws {
        let snapshot = defaultSyntheticSnapshot()
        let source = ReplayHealthDataSource(snapshot: snapshot, kind: .synthetic)
        let from = shanghaiDate(2026, 10, 15, 0)
        let to = shanghaiDate(2026, 10, 18, 0)

        let trimmed = try await source.snapshot(from: from, to: to, progress: { _, _ in })

        #expect(trimmed.rangeStart == from)
        #expect(trimmed.rangeEnd == to)
        #expect(trimmed.heartRate.count > 0)
        #expect(trimmed.heartRate.count < snapshot.heartRate.count)
        #expect(trimmed.heartRate.allSatisfy { $0.date >= from && $0.date <= to })
        #expect(trimmed.heartbeatSeries.allSatisfy { $0.end >= from && $0.start <= to })
    }

    @Test("kind 与 requestAuthorization 行为")
    func kindAndAuthorization() async throws {
        let source = ReplayHealthDataSource(snapshot: defaultSyntheticSnapshot(), kind: .imported)
        #expect(source.kind == .imported)
        try await source.requestAuthorization()
    }
}
