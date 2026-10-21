import Foundation
import Observation
import VigorHealth
import VigorScoring
import VigorStore

/// 实验室的参数与版本、校准、导出（PRD §6.11）。所有重算都是对全部历史重新跑一次流水线。
@MainActor
@Observable
final class PipelineLabModel {
    /// 正在编辑的候选配置（版本号在重算时才分配）
    var candidate: ScoringConfig
    private(set) var candidateOutput: PipelineOutput?
    private(set) var comparison: LabAnalysis.Comparison?
    private(set) var history: [ScoringConfig] = []
    private(set) var calibrationReport: CalibrationReport?
    private(set) var isWorking = false
    var message: String?

    init(config: ScoringConfig) {
        candidate = config
    }

    /// 从存储读取版本历史（回滚列表）。
    func reloadHistory() async {
        guard let repository = AppBootstrap.shared.environment.repository else { return }
        history = (try? await repository.configHistory()) ?? []
    }

    /// 以候选配置对全部历史重算，并与当前结果逐日对比。版本号分配为“最新版本 + 1”。
    func recompute(app: AppModel) async {
        guard let snapshot = app.snapshot else {
            message = "没有缓存的健康数据，请先同步。"
            return
        }
        isWorking = true
        defer { isWorking = false }

        var config = candidate
        config.configVersion = (history.first?.configVersion ?? app.config.configVersion) + 1
        candidate = config
        let input = PipelineInput(
            snapshot: snapshot,
            journal: app.journal,
            baseSleepNeedHours: AppSettings.baseSleepNeedHours,
            maxHeartRate: AppSettings.maxHeartRateOverride,
            targetWakeMinutes: AppSettings.targetWakeMinutes,
            config: config,
            now: app.lastUpdated ?? Date(),
            calendar: app.calendar
        )
        let output = await Task.detached(priority: .userInitiated) {
            ScoringPipeline.run(input)
        }.value
        candidateOutput = output
        comparison = LabAnalysis.compare(before: app.cycles, after: output.cycles)
        message = "已用版本 \(config.configVersion) 重算 \(output.cycles.count) 个周期。"
    }

    /// 采用候选结果：保存配置版本，并以新版本强制覆盖已锁定的周期（PRD §5.13 的“手动触发”）。
    func adopt(app: AppModel) async {
        guard let output = candidateOutput, let repository = AppBootstrap.shared.environment.repository else {
            message = "请先重算。"
            return
        }
        do {
            try await repository.saveConfig(candidate)
            try await repository.upsert(output.cycles, force: true)
            app.apply(output, config: candidate)
            candidateOutput = nil
            comparison = nil
            await reloadHistory()
            message = "已采用版本 \(candidate.configVersion)。"
        } catch {
            message = "采用失败：\(error.localizedDescription)"
        }
    }

    /// 回滚：把某个历史版本的参数作为新版本重新生效，然后重算。历史不会被删除。
    func rollback(to old: ScoringConfig, app: AppModel) async {
        candidate = old
        await recompute(app: app)
    }

    func runCalibration(app: AppModel) {
        let samples = LabAnalysis.calibrationSamples(cycles: app.cycles, journal: app.journal, calendar: app.calendar)
        calibrationReport = Calibration.evaluate(
            samples: samples,
            defaultWeights: LabAnalysis.calibrationWeights,
            lambda: 1
        )
    }

    /// 采用基础睡眠需求建议值（PRD §5.9.3）。调用前必须由用户确认。
    func adoptSleepNeed(_ hours: Double, app: AppModel) async {
        AppSettings.baseSleepNeedHours = hours
        await app.load(source: app.source)
        message = String(format: "基础睡眠需求已设为 %.2f 小时。", AppSettings.baseSleepNeedHours)
    }

    /// 导出三个文件：每日汇总 CSV、夜间特征 JSON、调试快照（HealthKit 快照 JSON）。
    func exportFiles(app: AppModel) throws -> [URL] {
        let stamp = Self.stamp()
        let directory = FileManager.default.temporaryDirectory
        let csvURL = directory.appendingPathComponent("vigor-daily-\(stamp).csv")
        try DailyExport.csv(cycles: app.cycles, calendar: app.calendar).write(to: csvURL, atomically: true, encoding: .utf8)

        let jsonURL = directory.appendingPathComponent("vigor-features-\(stamp).json")
        try DailyExport.featuresJSON(cycles: app.cycles).write(to: jsonURL, options: .atomic)

        guard let snapshot = app.snapshot else { throw LabExportError.noSnapshot }
        let debugURL = directory.appendingPathComponent("vigor-debug-snapshot-\(stamp).json")
        try SnapshotCoding.encode(snapshot).write(to: debugURL, options: .atomic)
        return [csvURL, jsonURL, debugURL]
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

enum LabExportError: LocalizedError {
    case noSnapshot

    var errorDescription: String? {
        "没有可导出的健康数据，请先同步。"
    }
}
