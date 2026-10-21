import Foundation

/// 某一晚的指标值与其是否可以进入基线（PRD §5.6 第 5 条）。
/// 由流水线在按时间顺序处理时逐晚填入；第 N 晚的基线只读取 N 之前的记录。
public struct BaselineObservation: Sendable, Hashable {
    public var values: [BaselineMetric: Double]
    /// 数据质量至少为中，且没有被排除
    public var isValid: Bool

    public init(values: [BaselineMetric: Double], isValid: Bool) {
        self.values = values
        self.isValid = isValid
    }
}

public enum BaselineHistory {
    /// 第 `index` 晚之前、有效且包含该指标的值（升序）。
    public static func values(
        for metric: BaselineMetric,
        before index: Int,
        in observations: [BaselineObservation]
    ) -> [Double] {
        observations[..<min(index, observations.count)].compactMap { observation in
            observation.isValid ? observation.values[metric] : nil
        }
    }

    /// 第 `index` 晚的基线（只使用它之前的记录）。
    public static func statistic(
        for metric: BaselineMetric,
        before index: Int,
        in observations: [BaselineObservation],
        profile: UserProfile,
        year: Int
    ) -> BaselineStatistic {
        Baseline.statistic(
            values: values(for: metric, before: index, in: observations),
            prior: PopulationPriors.prior(for: metric, profile: profile, year: year),
            sigmaFloor: Baseline.sigmaFloor(for: metric)
        )
    }
}
