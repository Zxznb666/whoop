import Foundation

/// 骑行候选：HealthKit 中的骑行训练，或导入的 FIT 骑行（施工文档 §2.1）。
public struct RideCandidate: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// HealthKit 训练；携带写入来源，用于界面展示
        case workout(UUID, productType: String?, sourceBundleID: String?)
        /// 导入的 FIT 骑行，携带 `fileID`
        case imported(String)
    }

    public var source: Source
    public var start: Date
    public var end: Date

    public init(source: Source, start: Date, end: Date) {
        self.source = source
        self.start = start
        self.end = end
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// 一组骑行 = 一次骑行。组的起止时间为各成员的并集。
public struct RideGroup: Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var members: [RideCandidate]
}

public enum RideGrouping {
    /// 两条候选的重叠时长达到较短者时长的这个比例时归入同一组。
    public static let overlapThreshold = 0.5

    /// 按传递闭包分组（并查集）。结果按开始时间升序。
    public static func group(_ candidates: [RideCandidate]) -> [RideGroup] {
        var parent = Array(candidates.indices)
        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current {
                parent[current] = parent[parent[current]]
                current = parent[current]
            }
            return current
        }
        for i in candidates.indices {
            for j in candidates.indices where j > i {
                if overlaps(candidates[i], candidates[j]) {
                    parent[root(j)] = root(i)
                }
            }
        }
        var buckets: [Int: [RideCandidate]] = [:]
        for index in candidates.indices {
            buckets[root(index), default: []].append(candidates[index])
        }
        return buckets.values.map { members in
            RideGroup(
                start: members.map(\.start).min() ?? Date.distantPast,
                end: members.map(\.end).max() ?? Date.distantPast,
                members: members.sorted { $0.start < $1.start }
            )
        }
        .sorted { $0.start < $1.start }
    }

    /// 重叠时长 ÷ 较短者时长 ≥ 50% 视为同一次骑行。
    public static func overlaps(_ a: RideCandidate, _ b: RideCandidate) -> Bool {
        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        let shorter = min(a.duration, b.duration)
        guard overlap > 0, shorter > 0 else { return false }
        return overlap / shorter >= overlapThreshold
    }
}
