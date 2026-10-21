import Charts
import SwiftUI
import VigorDesign
import VigorHealth
import VigorScoring

/// 实验室中基于流水线结果的区块（PRD §6.11）：基线曲线、周期明细、睡眠负债、消融、参数与版本、校准、导出。
struct PipelineLabSections: View {
    let app: AppModel
    @State private var lab: PipelineLabModel
    @State private var selectedWake: Date?
    @State private var exportURLs: [URL] = []
    @State private var confirmAdopt = false
    @State private var confirmRollback: ScoringConfig?
    @State private var confirmSleepNeed: Double?

    init(app: AppModel) {
        self.app = app
        _lab = State(initialValue: PipelineLabModel(config: app.config))
    }

    var body: some View {
        Group {
            baselineSection
            cycleSection
            debtSection
            ablationSection
            versionSection
            calibrationSection
            exportSection
        }
        .task {
            lab.candidate = app.config
            await lab.reloadHistory()
        }
        .alert("采用新版本？", isPresented: $confirmAdopt) {
            Button("采用", role: .destructive) { Task { await lab.adopt(app: app) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会以新版本覆盖已锁定的周期。旧版本保留在历史中，可以随时回滚。")
        }
        .confirmationDialog("回滚到这个版本？", isPresented: Binding(
            get: { confirmRollback != nil },
            set: { if !$0 { confirmRollback = nil } }
        ), titleVisibility: .visible) {
            Button("重算并对比") {
                if let old = confirmRollback { Task { await lab.rollback(to: old, app: app) } }
            }
        } message: {
            Text("参数会以新版本号重新生效，历史版本不会被删除。")
        }
        .alert("采用基础睡眠需求？", isPresented: Binding(
            get: { confirmSleepNeed != nil },
            set: { if !$0 { confirmSleepNeed = nil } }
        )) {
            Button("采用") {
                if let hours = confirmSleepNeed { Task { await lab.adoptSleepNeed(hours, app: app) } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(String(format: "基础睡眠需求会从 %.2f 小时改为 %.2f 小时。", AppSettings.baseSleepNeedHours, confirmSleepNeed ?? 0))
        }
    }

    // MARK: 基线曲线

    private var baselineSection: some View {
        Section {
            if baselinePoints.isEmpty {
                Text("还没有足够的周期。").foregroundStyle(.secondary)
            } else {
                Chart(baselinePoints) { point in
                    AreaMark(
                        x: .value("醒来", point.day),
                        yStart: .value("μ − σ", point.mu - point.sigma),
                        yEnd: .value("μ + σ", point.mu + point.sigma)
                    )
                    .foregroundStyle(VigorTokens.load.opacity(0.15))
                    LineMark(x: .value("醒来", point.day), y: .value("μ", point.mu))
                        .foregroundStyle(VigorTokens.load)
                    PointMark(x: .value("醒来", point.day), y: .value("ln RMSSD", point.observed))
                        .foregroundStyle(point.shrunk ? Color.secondary : Color.primary)
                        .symbolSize(14)
                }
                .frame(height: 200)
                .padding(.vertical, 8)
                Text("曲线为 μ ± σ（ln RMSSD）。灰色的点处于冷启动收缩阶段（有效样本不足 14 晚），基线仍偏向人群先验。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("基线曲线（夜间 ln RMSSD，最近 60 个周期）")
        }
    }

    private struct BaselinePoint: Identifiable {
        var id: Date { day }
        var day: Date
        var mu: Double
        var sigma: Double
        var observed: Double
        var shrunk: Bool
    }

    private var baselinePoints: [BaselinePoint] {
        app.cycles.suffix(60).compactMap { cycle in
            guard let stat = cycle.baselines[.lnRMSSDNight], let mu = stat.mu,
                  let rmssd = cycle.features.hrv.nightRMSSD, rmssd > 0
            else { return nil }
            return BaselinePoint(
                day: cycle.wakeTime,
                mu: mu,
                sigma: stat.sigma,
                observed: log(rmssd),
                shrunk: stat.count < 14
            )
        }
    }

    // MARK: 周期明细

    private var cycleSection: some View {
        Section {
            if app.cycles.isEmpty {
                Text("暂无周期。").foregroundStyle(.secondary)
            } else {
                Picker("周期", selection: $selectedWake) {
                    ForEach(app.cycles.reversed(), id: \.wakeTime) { cycle in
                        Text(Formatters.wakeDay(cycle.wakeTime)).tag(Optional(cycle.wakeTime))
                    }
                }
                if let cycle = selectedCycle {
                    cycleDetail(cycle)
                }
            }
        } header: {
            Text("周期明细")
        }
    }

    private var selectedCycle: CycleResult? {
        if let selectedWake, let match = app.cycles.first(where: { $0.wakeTime == selectedWake }) {
            return match
        }
        return app.cycles.last
    }

    @ViewBuilder
    private func cycleDetail(_ cycle: CycleResult) -> some View {
        if let recovery = cycle.recovery {
            VStack(alignment: .leading, spacing: 6) {
                Text("恢复 Shapley 贡献").font(.subheadline.weight(.semibold))
                ContributionWaterfall(contributions: recovery.contributions, score: recovery.score)
                    .frame(height: 180)
                LabeledContent("未封顶分数", value: Formatters.number(recovery.uncappedScore, digits: 1))
                if recovery.capped {
                    LabeledContent("生病封顶", value: "是")
                }
                LabeledContent("权重", value: recovery.weights
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key) \(Formatters.number($0.value * 100, digits: 0))%" }
                    .joined(separator: "  "))
            }
            .padding(.vertical, 4)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("数据质量分量").font(.subheadline.weight(.semibold))
            LabeledContent("总分", value: Formatters.percent(cycle.quality.total))
            LabeledContent("HRV", value: Formatters.percent(cycle.quality.components.hrv))
            LabeledContent("心率", value: Formatters.percent(cycle.quality.components.heartRate))
            LabeledContent("睡眠", value: Formatters.percent(cycle.quality.components.sleep))
            LabeledContent("生命体征", value: Formatters.percent(cycle.quality.components.vitals))
            ForEach(cycle.quality.reasons, id: \.self) { reason in
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        VStack(alignment: .leading, spacing: 4) {
            Text("HRV 段表").font(.subheadline.weight(.semibold))
            ForEach(cycle.features.windows.prefix(40), id: \.seriesID) { window in
                NavigationLink {
                    SegmentDetailView(segment: window)
                } label: {
                    SegmentTableRow(window: window)
                }
            }
            if cycle.features.windows.isEmpty {
                Text("这一晚没有 HRV 片段。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: 睡眠负债

    private var debtSection: some View {
        Section {
            if app.cycles.isEmpty {
                Text("暂无数据。").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("日期").frame(maxWidth: .infinity, alignment: .leading)
                    Text("需要").frame(width: 56, alignment: .trailing)
                    Text("实睡").frame(width: 56, alignment: .trailing)
                    Text("负债").frame(width: 56, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(app.cycles.suffix(14).reversed(), id: \.wakeTime) { cycle in
                    HStack {
                        Text(Formatters.wakeDay(cycle.wakeTime)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(Formatters.number(cycle.need.total, digits: 1)).frame(width: 56, alignment: .trailing)
                        Text(Formatters.number(cycle.sleepMetrics.totalSleepHours, digits: 1)).frame(width: 56, alignment: .trailing)
                        Text(Formatters.number(cycle.debtAfterNight, digits: 1)).frame(width: 56, alignment: .trailing)
                    }
                    .font(.callout)
                    .monospacedDigit()
                }
                Text("负债 = 上一晚的负债 + 需要 − 实睡（小时，下限 0）。负债递推只使用之前的夜晚。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("睡眠负债递推（最近 14 晚）")
        }
    }

    // MARK: 消融

    private var ablationSection: some View {
        Section {
            ForEach(LabAnalysis.Component.allCases, id: \.self) { component in
                let result = LabAnalysis.ablation(cycles: app.cycles, removing: component)
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.title).font(.callout.weight(.semibold))
                    if let shift = result.meanShift, let actual = result.actualMean, let ablated = result.ablatedMean {
                        Text(String(format: "平均 %.1f → %.1f（%+.1f），%d 晚", actual, ablated, shift, result.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("没有足够的数据。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("HRV 是恢复分数的必需分量，不提供消融。去掉某个分量后，剩余分量的权重按比例放大（与评分器的缺失规则一致）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("消融对比")
        }
    }

    // MARK: 参数与版本

    /// 候选参数的双向绑定（Stepper 需要 Binding；`lab` 是 @State 持有的 @Observable 对象）。
    private func candidate<Value>(_ keyPath: WritableKeyPath<ScoringConfig, Value>) -> Binding<Value> {
        Binding(
            get: { lab.candidate[keyPath: keyPath] },
            set: { lab.candidate[keyPath: keyPath] = $0 }
        )
    }

    private var versionSection: some View {
        Section {
            LabeledContent("当前版本", value: "\(app.config.configVersion)")
            Stepper(value: candidate(\.earlyNightWeight), in: 0.1...2, step: 0.1) {
                LabeledContent("早段权重", value: Formatters.number(lab.candidate.earlyNightWeight, digits: 1))
            }
            Stepper(value: candidate(\.middleNightWeight), in: 0.1...2, step: 0.1) {
                LabeledContent("中段权重", value: Formatters.number(lab.candidate.middleNightWeight, digits: 1))
            }
            Stepper(value: candidate(\.lateNightWeight), in: 0.1...2, step: 0.1) {
                LabeledContent("晚段权重", value: Formatters.number(lab.candidate.lateNightWeight, digits: 1))
            }
            Stepper(value: candidate(\.deepStageWeight), in: 0.1...2, step: 0.1) {
                LabeledContent("深睡权重", value: Formatters.number(lab.candidate.deepStageWeight, digits: 1))
            }
            Stepper(value: candidate(\.remStageWeight), in: 0.1...2, step: 0.1) {
                LabeledContent("REM 权重", value: Formatters.number(lab.candidate.remStageWeight, digits: 1))
            }
            Stepper(value: candidate(\.fullQualityBeats), in: 30...120, step: 5) {
                LabeledContent("满分所需拍数", value: "\(Int(lab.candidate.fullQualityBeats))")
            }
            Button("用候选参数重算并对比") {
                Task { await lab.recompute(app: app) }
            }
            .disabled(lab.isWorking)

            if lab.isWorking {
                ProgressView("重算中…")
            }
            if let comparison = lab.comparison {
                LabeledContent("平均绝对变化", value: Formatters.number(comparison.meanAbsoluteChange, digits: 2))
                LabeledContent("最大绝对变化", value: Formatters.number(comparison.maximumAbsoluteChange, digits: 1))
                LabeledContent("明显变化（≥ \(Int(LabAnalysis.notableChange)) 分）", value: "\(comparison.notableCount) 晚")
                ForEach(comparison.changes.filter { ($0.delta.map(abs) ?? 0) >= 1 }.suffix(8), id: \.wakeTime) { change in
                    LabeledContent(Formatters.wakeDay(change.wakeTime)) {
                        Text("\(Formatters.number(change.before, digits: 0)) → \(Formatters.number(change.after, digits: 0))")
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
                Button("采用为新版本") { confirmAdopt = true }
                    .disabled(lab.candidateOutput == nil)
            }
            if let message = lab.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            ForEach(lab.history, id: \.configVersion) { old in
                Button("回滚到版本 \(old.configVersion)") {
                    confirmRollback = old
                }
                .font(.callout)
            }
        } header: {
            Text("参数与版本")
        } footer: {
            Text("候选参数只影响重算结果，采用后才写入存储。每次采用都会生成新的版本号。")
        }
    }

    // MARK: 校准

    private var calibrationSection: some View {
        Section {
            let available = LabAnalysis.calibrationSamples(cycles: app.cycles, journal: app.journal, calendar: app.calendar).count
            Button("用主观精力拟合（岭回归）") {
                lab.runCalibration(app: app)
            }
            .disabled(available < Calibration.minimumDays)
            if available < Calibration.minimumDays {
                Text("有主观精力的天数为 \(available)，校准至少需要 \(Calibration.minimumDays) 天，目前已禁用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let report = lab.calibrationReport {
                LabeledContent("训练 / 验证", value: "\(report.trainCount) / \(report.validationCount) 晚")
                LabeledContent("默认 Spearman", value: Formatters.number(report.defaultSpearman, digits: 3))
                LabeledContent("拟合后 Spearman", value: Formatters.number(report.fittedSpearman, digits: 3))
                LabeledContent("提升", value: Formatters.number(report.improvement, digits: 3))
                Text(report.recommended ? "验证集提升达到 0.05，可以考虑采用。" : "提升不足 0.05，不建议采用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("恢复权重的采用需要把权重接入评分器，本版本只显示报告，不写入配置（见 DECISIONS D-088）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let personalized = app.output?.personalizedNeed {
                let updated = personalized.candidate ?? personalized.updatedBase
                LabeledContent("基础睡眠需求（当前）", value: String(format: "%.2f 小时", AppSettings.baseSleepNeedHours))
                LabeledContent("建议值", value: String(format: "%.2f 小时", updated))
                if let hint = personalized.hint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
                Button("采用建议的基础睡眠需求") {
                    confirmSleepNeed = updated
                }
                .disabled(abs(updated - AppSettings.baseSleepNeedHours) < 0.01)
            }
        } header: {
            Text("校准")
        }
    }

    // MARK: 导出

    private var exportSection: some View {
        Section {
            Button("生成导出文件（CSV · JSON · 调试快照）") {
                do {
                    exportURLs = try lab.exportFiles(app: app)
                } catch {
                    lab.message = error.localizedDescription
                }
            }
            ForEach(exportURLs, id: \.self) { url in
                ShareLink(item: url) {
                    Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                        .font(.callout)
                }
            }
            if let message = lab.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("导出")
        } footer: {
            Text("CSV 为每日汇总；JSON 为夜间特征；调试快照是 HealthKit 原始快照（包含健康数据，请妥善保管）。")
        }
    }
}

/// 段表的一行：时间、分期、位置、有效拍数、剔除率、RMSSD、权重与是否采用、丢弃原因。
private struct SegmentTableRow: View {
    let window: HRVWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Formatters.clockRange(window.start, window.end))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(stageText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Formatters.rmssd(window.rmssd)).font(.callout).monospacedDigit()
            }
            HStack {
                Text("位置 \(Formatters.number(window.position, digits: 2))")
                Text("有效 \(window.acceptedCount)")
                Text("剔除 \(Formatters.percent(window.rejectRate))")
                Text("权重 \(Formatters.number(window.weight, digits: 2))")
                Text(window.adopted ? "采用" : "未采用")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            if let reason = window.invalidReason {
                Text("丢弃：\(reason)").font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private var stageText: String {
        guard let stage = window.stage else { return "清醒" }
        return VigorTokens.label(for: stage)
    }
}
