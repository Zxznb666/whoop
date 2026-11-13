import Foundation
import VigorHealth
import VigorScoring

// 用法：
//   vigor-export --synthetic <输出目录>          合成场景（seed 42，120 晚，与 Tools/VigorReplay 的黄金快照同一份输入）
//   vigor-export --snapshot <快照.json> <输出目录>  真实快照（Vigor 实验室页导出的调试快照）
// 输出：
//   snapshot.json   快照（去掉逐拍序列 heartbeatSeries 与骑行逐秒数据，Muse 拿不到这些）
//   vigor.json      Vigor 完整管线（逐拍 RMSSD）的逐周期结果，供参考实现对照：
//                   cycles = 完整输入；parityCycles = 去掉 FIT 导入骑行和骑行功率后的结果
// 注意：不传日志（journal）。Muse 读不到 Vigor 的日志，对照时两边都按“无日志”计算。

let arguments = Array(CommandLine.arguments.dropFirst())
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

let snapshot: HealthSnapshot
let outDir: String
let now: Date
if arguments.first == "--synthetic", arguments.count == 2 {
    var parts = DateComponents()
    parts.year = 2026; parts.month = 10; parts.day = 1; parts.hour = 0
    parts.timeZone = calendar.timeZone
    let ending = calendar.date(from: parts)!
    snapshot = SyntheticScenario.make(nights: 120, seed: 42, endingAt: ending, calendar: calendar).snapshot
    outDir = arguments[1]
    now = ending
} else if arguments.first == "--snapshot", arguments.count == 3 {
    snapshot = try SnapshotCoding.decode(Data(contentsOf: URL(fileURLWithPath: arguments[1])))
    outDir = arguments[2]
    now = snapshot.rangeEnd
} else {
    FileHandle.standardError.write(Data("用法：vigor-export --synthetic <dir> | --snapshot <file> <dir>\n".utf8))
    exit(2)
}


func day(_ c: DateComponents) -> String { String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0) }
func num(_ v: Double?) -> Any { v.flatMap { $0.isFinite ? $0 : nil } ?? NSNull() }

func exportCycles(_ output: PipelineOutput) -> [[String: Any]] {
var cycles: [[String: Any]] = []
for c in output.cycles {
    let f = c.features
    cycles.append([
        "wakeDay": day(c.wakeDay),
        "sleepStart": f.session.start.timeIntervalSince1970,
        "sleepEnd": f.session.end.timeIntervalSince1970,
        "bedtime": num(f.session.bedtime?.timeIntervalSince1970),
        "tstHours": c.sleepMetrics.totalSleepHours,
        "efficiency": c.sleepMetrics.efficiency,
        "restorativeHours": c.sleepMetrics.restorativeHours,
        "awakenings": c.sleepMetrics.awakenings,
        "sri": num(c.sri),
        "needHours": c.need.total,
        "debtAfterHours": c.debtAfterNight,
        "sleepScore": c.sleepScore.score,
        "sleepPerformance": c.sleepScore.performance,
        "rmssd": num(f.hrv.nightRMSSD),
        "hrvMethod": f.hrv.method.rawValue,
        "sdnnMean": num(f.hrv.sdnnMean),
        "rhr": num(f.restingHeartRate.value),
        "rhrSource": f.restingHeartRate.source.rawValue,
        "respiratoryRate": num(f.respiratoryRate),
        "wristTemperature": num(f.wristTemperature),
        "temperatureDelta": num(c.temperatureDelta),
        "spo2Median": num(f.spo2MedianPercent),
        "zHRV": num(c.zHRV), "zRHR": num(c.zRHR), "zResp": num(c.zResp),
        "zSleep": c.sleepScore.zSleep,
        "recovery": num(c.recovery?.score),
        "zone": c.recovery?.zone.rawValue ?? NSNull(),
        "illness": c.illness.rawValue,
        "exclusion": c.exclusion?.rawValue ?? NSNull(),
        "quality": c.quality.level.rawValue,
        "qualityTotal": c.quality.total,
        "trimp": c.load.trimp,
        "strain": c.load.strain,
        "countedMinutes": c.load.countedMinutes,
        "unwornMinutes": c.load.unwornMinutes,
        "zoneMinutes": c.load.zoneMinutes,
        "maxHeartRate": c.load.maxHeartRate,
        "loadRestingHeartRate": c.load.restingHeartRate,
        "activityModelEnabled": c.load.activityModelEnabled,
        "workouts": c.load.workouts.map { w -> [String: Any] in
            ["type": w.activityType, "start": w.start.timeIntervalSince1970, "end": w.end.timeIntervalSince1970,
             "trimp": w.trimp, "strain": w.strain, "meanHR": num(w.meanHeartRate), "peakHR": num(w.peakHeartRate)]
        },
    ])
}
return cycles
}

// 完整：和 Vigor App 看到的一样（含 FIT 导入骑行与功率补偿）
let cycles = exportCycles(ScoringPipeline.run(PipelineInput(snapshot: snapshot, now: now, calendar: calendar)))
// 对照：去掉 Muse 读不到的 FIT 导入骑行和骑行功率（不触发功率补偿），用于检验算法移植本身是否一致
var parityInput = snapshot
parityInput.importedRides = []
parityInput.cyclingPower = []
let parityCycles = exportCycles(ScoringPipeline.run(PipelineInput(snapshot: parityInput, now: now, calendar: calendar)))

var slim = snapshot
slim.heartbeatSeries = []
slim.importedRides = []
let dir = URL(fileURLWithPath: outDir, isDirectory: true)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
try SnapshotCoding.encode(slim).write(to: dir.appendingPathComponent("snapshot.json"))
let meta: [String: Any] = [
    "generator": "Muse/reference/vigor-export",
    "vigorAlgorithmVersion": ScoringPipeline.algorithmVersion,
    "timeZone": calendar.timeZone.identifier,
    "now": now.timeIntervalSince1970,
    "cycles": cycles,
    "parityCycles": parityCycles,
]
try JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys, .prettyPrinted]).write(to: dir.appendingPathComponent("vigor.json"))
print("周期 \(cycles.count) 个，已写入 \(dir.path)")
