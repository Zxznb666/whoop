import Foundation

/// 睡眠事件统计与睡眠图显示（PRD §5.2 “分期的使用原则”）。
public enum SleepEvents {
    /// 觉醒次数：持续 ≥ `minDuration` 的清醒段个数。统计时长仍使用原始分期。
    public static func awakeningCount(in session: SleepSession, config: ScoringConfig = .default) -> Int {
        session.stages.filter { sample in
            sample.stage == .awake && sample.end.timeIntervalSince(sample.start) >= config.awakeningMinDuration
        }.count
    }

    /// 睡眠图的显示用分期：不足 `hypnogramMinDuration` 的片段并入较长的相邻片段，
    /// 合并后相邻的同类分期再合并为一段。只影响显示，不改变任何统计。
    public static func hypnogram(_ stages: [SleepStageSample], config: ScoringConfig = .default) -> [SleepStageSample] {
        var segments = stages.sorted { $0.start < $1.start }
        while segments.count > 1,
              let index = segments.indices.min(by: { duration(segments[$0]) < duration(segments[$1]) }),
              duration(segments[index]) < config.hypnogramMinDuration
        {
            let previous = index > 0 ? index - 1 : nil
            let next = index < segments.count - 1 ? index + 1 : nil
            let neighbor: Int
            if let previous, let next {
                neighbor = duration(segments[previous]) >= duration(segments[next]) ? previous : next
            } else {
                neighbor = previous ?? next ?? index
            }
            if neighbor < index {
                segments[neighbor].end = segments[index].end
            } else {
                segments[neighbor].start = segments[index].start
            }
            segments.remove(at: index)
            coalesceAdjacentSameStage(&segments)
        }
        return segments
    }

    private static func duration(_ sample: SleepStageSample) -> TimeInterval {
        sample.end.timeIntervalSince(sample.start)
    }

    private static func coalesceAdjacentSameStage(_ segments: inout [SleepStageSample]) {
        var index = segments.count - 1
        while index > 0 {
            if segments[index - 1].stage == segments[index].stage {
                segments[index - 1].end = segments[index].end
                segments.remove(at: index)
            }
            index -= 1
        }
    }
}
