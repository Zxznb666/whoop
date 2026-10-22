import Foundation
import VigorScoring

/// 一次读取到的数据条数，用来区分“HealthKit 什么都没返回（读取权限没打开时系统静默返回空）”
/// 与“读到了数据但没有识别出睡眠”这两种情况。
public struct SnapshotInventory: Sendable, Hashable {
    public var sleepStages: Int
    public var sleepStagesFromWatch: Int
    public var inBed: Int
    public var heartRate: Int
    public var hrvSDNN: Int
    public var heartbeatSeries: Int
    public var workouts: Int
    /// 睡眠分期样本的来源（名称 + 产品型号），用于检查来源识别
    public var sleepSources: [String]
    public var firstSleep: Date?
    public var lastSleep: Date?

    public init(_ snapshot: HealthSnapshot) {
        sleepStages = snapshot.sleep.count
        sleepStagesFromWatch = snapshot.sleep.filter(\.sourceIsWatch).count
        inBed = snapshot.inBed.count
        heartRate = snapshot.heartRate.count
        hrvSDNN = snapshot.hrvSDNN.count
        heartbeatSeries = snapshot.heartbeatSeries.count
        workouts = snapshot.workouts.count
        let sources = Set(snapshot.sleep.map { "\($0.sourceName ?? "未知来源")（\($0.productType ?? "无型号")）" })
        sleepSources = sources.sorted()
        firstSleep = snapshot.sleep.map(\.start).min()
        lastSleep = snapshot.sleep.map(\.end).max()
    }

    /// 是否完全没有读到任何健康数据（最可能是读取权限没有打开）。
    public var isEmpty: Bool {
        sleepStages == 0 && inBed == 0 && heartRate == 0 && hrvSDNN == 0 && heartbeatSeries == 0 && workouts == 0
    }

    /// 给用户看的一行摘要。
    public var summary: String {
        var parts = [
            "睡眠分期 \(sleepStages) 条（手表 \(sleepStagesFromWatch) 条）",
            "在床 \(inBed) 条",
            "心率 \(heartRate) 条",
            "HRV \(hrvSDNN) 条",
            "心跳序列 \(heartbeatSeries) 段",
            "训练 \(workouts) 次",
        ]
        if !sleepSources.isEmpty {
            parts.append("睡眠来源：\(sleepSources.joined(separator: "、"))")
        }
        return parts.joined(separator: "，")
    }
}
