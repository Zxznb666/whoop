import Foundation
import VigorScoring

public enum SyntheticSnapshot {
    /// M0 兼容入口：内部转调合成场景 v2，只返回快照。
    ///
    /// 夜晚序号 `i % 10 == 3` 的夜晚没有心跳序列也没有晨测（用于覆盖 SDNN 兜底）；
    /// `i % 5 == 1` 的夜晚在醒来后 20 分钟有一段晨测序列。
    public static func make(
        nights: Int = 30,
        seed: UInt64 = 42,
        endingAt: Date,
        calendar: Calendar
    ) -> HealthSnapshot {
        SyntheticScenario.make(nights: nights, seed: seed, endingAt: endingAt, calendar: calendar).snapshot
    }
}
