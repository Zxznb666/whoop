import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("SnapshotCache")
struct SnapshotCacheTests {
    /// 缓存 [h, t1] + 窗口 [cut, now] 合并后，应与一次性读取 [h, now] 的样本完全一致（不重不漏）。
    @Test("窗口合并等价于全量读取")
    func windowMergeEqualsFullRead() async throws {
        let source = ReplayHealthDataSource(snapshot: defaultSyntheticSnapshot(), kind: .synthetic)
        let history = shanghaiDate(2026, 9, 25, 0)
        let now = shanghaiDate(2026, 10, 20, 9)
        let previousRefresh = shanghaiDate(2026, 10, 19, 8)
        let cut = shanghaiDate(2026, 10, 17, 9)

        let full = try await source.snapshot(from: history, to: now, progress: { _, _ in })
        let cached = try await source.snapshot(from: history, to: previousRefresh, progress: { _, _ in })
        let fresh = try await source.snapshot(from: cut, to: now, progress: { _, _ in })
        let merged = cached.merging(fresh, cut: cut, keepFrom: history)

        #expect(merged.sleep.count == full.sleep.count)
        #expect(Set(merged.sleep) == Set(full.sleep))
        #expect(merged.heartRate.count == full.heartRate.count)
        #expect(Set(merged.heartRate) == Set(full.heartRate))
        #expect(Set(merged.heartbeatSeries.map(\.id)) == Set(full.heartbeatSeries.map(\.id)))
        #expect(merged.heartbeatSeries.count == full.heartbeatSeries.count)
        #expect(Set(merged.hrvSDNN) == Set(full.hrvSDNN))
        #expect(Set(merged.workouts) == Set(full.workouts))
        #expect(Set(merged.activeEnergy) == Set(full.activeEnergy))
        // v3：骑行功率、FTP 按窗口拼接；导入的骑行每次由调用方完整提供
        #expect(Set(merged.cyclingPower) == Set(full.cyclingPower))
        #expect(Set(merged.ftp) == Set(full.ftp))
        #expect(merged.importedRides == full.importedRides)
        #expect(merged.rangeStart == history)
        #expect(merged.rangeEnd == now)
    }

    @Test("丢弃保留起点之前的样本，结果按开始时间排序")
    func trimsAndSorts() async throws {
        let source = ReplayHealthDataSource(snapshot: defaultSyntheticSnapshot(), kind: .synthetic)
        let history = shanghaiDate(2026, 9, 25, 0)
        let keepFrom = shanghaiDate(2026, 10, 5, 0)
        let now = shanghaiDate(2026, 10, 20, 9)
        let cut = shanghaiDate(2026, 10, 17, 9)

        let cached = try await source.snapshot(from: history, to: now, progress: { _, _ in })
        let fresh = try await source.snapshot(from: cut, to: now, progress: { _, _ in })
        let merged = cached.merging(fresh, cut: cut, keepFrom: keepFrom)

        #expect(merged.rangeStart == keepFrom)
        #expect(merged.heartRate.allSatisfy { $0.date >= keepFrom })
        #expect(merged.sleep.allSatisfy { $0.end >= keepFrom })
        #expect(zip(merged.sleep, merged.sleep.dropFirst()).allSatisfy { $0.start <= $1.start })
    }

    @Test("保存后读回相同；文件损坏时返回 nil")
    func roundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("cache.json")
        let cache = SnapshotCache(url: url)
        #expect(await cache.load() == nil)

        let snapshot = defaultSyntheticSnapshot()
        try await cache.save(snapshot)
        #expect(await cache.load() == snapshot)

        try Data("broken".utf8).write(to: url)
        #expect(await cache.load() == nil)
        try await cache.clear()
        try? FileManager.default.removeItem(at: directory)
    }
}
