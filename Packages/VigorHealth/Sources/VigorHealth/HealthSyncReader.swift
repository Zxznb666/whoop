#if os(iOS) || os(watchOS)
import Foundation
import HealthKit

/// 一次增量读取的结果：新增样本与已删除的 HK UUID（施工文档 §5 阶段 1 第 3 条）。
public struct IncrementalResult<Sample: Sendable>: Sendable {
    public var added: [Sample]
    public var deletedUUIDs: Set<UUID>
}

/// 基于 `HKAnchoredObjectQueryDescriptor` 的增量读取。每种类型的锚点序列化后存入 `UserDefaults`。
public actor HealthSyncReader {
    private let store: HKHealthStore
    private let defaults: UserDefaults
    private static let keyPrefix = "vigor.anchor."

    public init(store: HKHealthStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    /// `key` 通常取类型名，例如 "sleepAnalysis"。
    public func incremental<Sample: HKSample>(
        key: String,
        predicate: HKSamplePredicate<Sample>
    ) async throws -> IncrementalResult<Sample> {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [predicate],
            anchor: anchor(for: key)
        )
        let result = try await descriptor.result(for: store)
        saveAnchor(result.newAnchor, for: key)
        return IncrementalResult(
            added: result.addedSamples,
            deletedUUIDs: Set(result.deletedObjects.map(\.uuid))
        )
    }

    /// 清除某个类型的锚点，下次增量读取会从头返回全部样本。
    public func resetAnchor(for key: String) {
        defaults.removeObject(forKey: Self.keyPrefix + key)
    }

    func anchor(for key: String) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: Self.keyPrefix + key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, for key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        defaults.set(data, forKey: Self.keyPrefix + key)
    }
}
#endif
