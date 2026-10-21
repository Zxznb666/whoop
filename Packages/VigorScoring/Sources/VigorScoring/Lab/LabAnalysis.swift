import Foundation

/// 实验室的纯计算（PRD §6.11）：配置版本对比、消融与校准样本。全部是纯函数，界面只负责展示。
public enum LabAnalysis {
    /// 恢复分数变化达到该值时计入“明显变化”
    public static let notableChange = 5.0

    // MARK: 版本对比

    public struct DayChange: Sendable, Hashable, Identifiable {
        public var id: Date { wakeTime }
        public var wakeTime: Date
        public var before: Double?
        public var after: Double?

        public var delta: Double? {
            guard let before, let after else { return nil }
            return after - before
        }
    }

    public struct Comparison: Sendable, Hashable {
        /// 按醒来时间升序，只包含两个版本都存在的周期
        public var changes: [DayChange]
        public var meanAbsoluteChange: Double?
        public var maximumAbsoluteChange: Double?
        public var notableCount: Int
    }

    /// 逐日对比两次流水线结果的恢复分数（按醒来时间对齐）。
    public static func compare(before: [CycleResult], after: [CycleResult]) -> Comparison {
        let previous = Dictionary(before.map { ($0.wakeTime, $0.recovery?.score) }, uniquingKeysWith: { _, last in last })
        let changes = after.compactMap { cycle -> DayChange? in
            guard let old = previous[cycle.wakeTime] else { return nil }
            return DayChange(wakeTime: cycle.wakeTime, before: old, after: cycle.recovery?.score)
        }
        let deltas = changes.compactMap { $0.delta.map(abs) }
        return Comparison(
            changes: changes,
            meanAbsoluteChange: deltas.isEmpty ? nil : deltas.reduce(0, +) / Double(deltas.count),
            maximumAbsoluteChange: deltas.max(),
            notableCount: deltas.filter { $0 >= notableChange }.count
        )
    }

    // MARK: 消融

    /// 可以被去掉的分量。HRV 是恢复分数的必需分量，不能去掉（`RecoveryScorer` 在缺失时返回 nil）。
    public enum Component: String, Sendable, Hashable, CaseIterable {
        case restingHeartRate
        case sleep

        public var title: String {
            switch self {
            case .restingHeartRate: "去掉静息心率"
            case .sleep: "去掉睡眠"
            }
        }
    }

    public struct Ablation: Sendable, Hashable {
        public var component: Component
        public var count: Int
        /// 去掉分量后的平均分数减去实际平均分数（负值表示去掉后分数下降）
        public var meanShift: Double?
        public var ablatedMean: Double?
        public var actualMean: Double?
    }

    /// 去掉一个分量后，按剩余分量重新计算恢复分数（权重按比例放大，与 `RecoveryScorer` 的缺失规则一致）。
    public static func ablatedRecovery(_ cycle: CycleResult, removing component: Component) -> Double? {
        guard let recovery = cycle.recovery else { return nil }
        let inputs = RecoveryInputs(
            zHRV: recovery.zHRV,
            zRHR: component == .restingHeartRate ? nil : recovery.zRHR,
            zSleep: component == .sleep ? nil : recovery.zSleep,
            penalties: recovery.penalties,
            illnessPossible: cycle.illness == .possiblyUnwell
        )
        return RecoveryScorer.score(inputs)?.score
    }

    public static func ablation(cycles: [CycleResult], removing component: Component) -> Ablation {
        var actual: [Double] = []
        var ablated: [Double] = []
        for cycle in cycles {
            guard let score = cycle.recovery?.score, let shifted = ablatedRecovery(cycle, removing: component) else { continue }
            actual.append(score)
            ablated.append(shifted)
        }
        guard !actual.isEmpty else {
            return Ablation(component: component, count: 0, meanShift: nil, ablatedMean: nil, actualMean: nil)
        }
        let actualMean = actual.reduce(0, +) / Double(actual.count)
        let ablatedMean = ablated.reduce(0, +) / Double(ablated.count)
        return Ablation(
            component: component,
            count: actual.count,
            meanShift: ablatedMean - actualMean,
            ablatedMean: ablatedMean,
            actualMean: actualMean
        )
    }

    // MARK: 校准

    /// 校准的特征：与恢复分数相同的三个 z-score，缺失记为 0（中性）。默认权重与 `RecoveryScorer` 一致。
    public static let calibrationWeights = [0.55, 0.25, 0.20]

    /// 每个有主观精力记录的醒来日：([zHRV, zRHR, zSleep], 精力)，按时间升序。
    /// 精力记在醒来日，与周期对齐（同一天的日志 = 同一个醒来日，见 `JournalEntry`）。
    public static func calibrationSamples(cycles: [CycleResult], journal: [JournalEntry], calendar: Calendar) -> [(features: [Double], energy: Double)] {
        let energyByDay = Dictionary(
            journal.compactMap { entry in entry.energy.map { (calendar.startOfDay(for: entry.night), Double($0)) } },
            uniquingKeysWith: { _, last in last }
        )
        return cycles.sorted { $0.wakeTime < $1.wakeTime }.compactMap { cycle in
            guard let energy = energyByDay[calendar.startOfDay(for: cycle.wakeTime)] else { return nil }
            let features = [cycle.zHRV ?? 0, cycle.zRHR ?? 0, cycle.recovery?.zSleep ?? 0]
            return (features, energy)
        }
    }
}
