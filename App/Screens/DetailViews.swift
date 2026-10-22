import Charts
import SwiftUI
import UniformTypeIdentifiers
import VigorDesign
import VigorScoring

struct RecoveryDetailView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                if let today = model.today, let recovery = today.recovery {
                    SectionCard {
                        VStack(spacing: 10) {
                            ScoreRing(
                                value: recovery.score,
                                color: VigorTokens.color(for: recovery.zone),
                                title: "恢复 · \(VigorTokens.label(for: recovery.zone))区",
                                valueText: "\(Int(recovery.score.rounded()))",
                                subtitle: today.recoveryState == .preliminary ? "初步" : "最终"
                            )
                            QualityBadge(level: today.quality.level, reasons: today.quality.reasons)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("贡献拆解").font(.headline)
                            ContributionWaterfall(contributions: recovery.contributions, score: recovery.score)
                            Text("从基线 \(Int(RecoveryScorer.baseline.rounded()))% 出发，每一项正负贡献精确相加到今日分数（Shapley 值）。")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(specialNotes(recovery, today: today), id: \.self) { note in
                                Label(note, systemImage: "info.circle").font(.caption)
                            }
                        }
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("HRV 来源").font(.headline)
                            Text(hrvSource(today)).font(.callout)
                            if let z = today.zHRV {
                                Text(String(format: "z-score %.2f", z)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("近 30 天恢复").font(.headline)
                            Chart(model.cycles.suffix(30)) { cycle in
                                BarMark(
                                    x: .value("日期", cycle.wakeTime, unit: .day),
                                    y: .value("恢复", cycle.recovery?.score ?? 0)
                                )
                                .foregroundStyle(cycle.recovery.map { VigorTokens.color(for: $0.zone) } ?? .gray)
                            }
                            .chartYScale(domain: 0...100)
                            .frame(height: 160)
                        }
                    }
                } else {
                    Text(model.message ?? "暂无数据").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("恢复")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func specialNotes(_ recovery: RecoveryResult, today: CycleResult) -> [String] {
        var notes: [String] = []
        if recovery.contradiction { notes.append("信号矛盾：HRV 偏高但静息心率也偏高，已按 1 计算") }
        if recovery.capped { notes.append("生病预警封顶：今日分数不超过 33") }
        if today.features.hrv.nightValidCount == 0, today.features.hrv.sdnnMean != nil {
            notes.append("HRV 来自 SDNN 估算，质量较低")
        }
        return notes
    }

    private func hrvSource(_ today: CycleResult) -> String {
        let hrv = today.features.hrv
        switch hrv.method {
        case .overnight:
            let morning = hrv.morningValidCount > 0 ? "，并有 \(hrv.morningValidCount) 次晨测参与" : ""
            return "今晚用了 \(hrv.nightValidCount) 段夜间序列（共 \(hrv.nightTotalCount) 段）\(morning)。"
        case .morning: return "没有夜间有效序列，使用了晨测。"
        case .sdnnFallback: return "没有心跳序列，退回 Apple 的 SDNN。"
        case .none: return "没有可用的 HRV。"
        }
    }
}

struct SleepView: View {
    let model: AppModel
    @State private var showCorrection = false

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                if let today = model.today {
                    Button("修正睡眠时段…") { showCorrection = true }
                        .buttonStyle(.bordered)
                    SectionCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("昨夜睡眠").font(.headline)
                                Spacer()
                                Text("睡眠分 \(Int(today.sleepScore.score.rounded()))").font(.subheadline).foregroundStyle(VigorTokens.sleep)
                            }
                            Hypnogram(segments: SleepEvents.hypnogram(today.features.session.stages))
                            Text(String(format: "睡着 %.1f 小时 · 效率 %.0f%% · 觉醒 %d 次", today.sleepMetrics.totalSleepHours, today.sleepMetrics.efficiency * 100, today.sleepMetrics.awakenings))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("睡眠需求构成").font(.headline)
                            needChart(today.need)
                            Text(String(format: "需求 %.1f 小时（基础 %.1f，负荷追加 %.0f 分钟，负债偿还 %.0f 分钟，小睡抵扣 %.0f 分钟）",
                                        today.need.total,
                                        today.need.base,
                                        today.need.loadAddition * 60,
                                        today.need.debtRepayment * 60,
                                        -today.need.napCredit * 60))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("指标").font(.headline)
                            row("睡眠表现", String(format: "%.0f%%", today.sleepScore.performance))
                            row("入睡耗时", today.sleepMetrics.sleepLatencyMinutes.map { String(format: "%.0f 分钟", $0) } ?? "—")
                            row("夜间清醒", String(format: "%.0f 分钟", today.sleepMetrics.wasoMinutes))
                            row("觉醒次数", "\(today.sleepMetrics.awakenings)")
                            row("REM 潜伏期", today.sleepMetrics.remLatencyMinutes.map { String(format: "%.0f 分钟", $0) } ?? "—")
                            row("规律指数 SRI", today.sri.map { String(format: "%.0f", max(0, $0)) } ?? "数据不足")
                            if let advice = today.bedtimeAdvice {
                                Divider()
                                row("建议入睡（100%）", timeText(advice.bedtimeAt100))
                                row("建议入睡（85%）", timeText(advice.bedtimeAt85))
                                row("建议入睡（70%）", timeText(advice.bedtimeAt70))
                            }
                        }
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("睡眠负债（14 天）").font(.headline)
                            Chart(model.cycles.suffix(14)) { cycle in
                                LineMark(x: .value("日期", cycle.wakeTime, unit: .day), y: .value("负债", cycle.debtAfterNight))
                                    .foregroundStyle(VigorTokens.sleep)
                            }
                            .frame(height: 140)
                        }
                    }
                } else {
                    Text(model.message ?? "暂无数据").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showCorrection) {
            if let today = model.today {
                SleepCorrectionSheet(model: model, cycle: today)
            }
        }
        .navigationTitle("睡眠")
    }

    private struct NeedSegment: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let color: Color
    }

    /// 堆叠条：各部分首尾相接，总高度即睡眠需求。
    private func needChart(_ need: SleepNeedComponents) -> some View {
        let parts: [(String, Double, Color)] = [
            ("基础", need.base, VigorTokens.sleep),
            ("负荷追加", need.loadAddition, VigorTokens.load),
            ("负债偿还", need.debtRepayment, VigorTokens.heart),
        ]
        var running = 0.0
        let segments = parts.map { name, hours, color -> NeedSegment in
            let start = running
            running += hours
            return NeedSegment(id: name, start: start, end: running, color: color)
        }
        return Chart(segments) { segment in
            RectangleMark(
                x: .value("需求", "需求"),
                yStart: .value("起点", segment.start),
                yEnd: .value("终点", segment.end)
            )
            .foregroundStyle(segment.color)
        }
        .frame(height: 80)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Text(value).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct StrainView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                if let today = model.today {
                    SectionCard {
                        HStack {
                            ScoreRing(
                                value: today.load.strain,
                                maximum: 21,
                                color: VigorTokens.load,
                                title: "今日负荷",
                                valueText: String(format: "%.1f", today.load.strain),
                                targetRange: today.loadTarget.map { $0.lower...$0.upper }
                            )
                            .frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 6) {
                                if let target = today.loadTarget {
                                    Text("目标 \(Int(target.lower))–\(Int(target.upper))").font(.headline)
                                }
                                if let acwr = today.acwr {
                                    Text(String(format: "负荷平衡 ACWR %.2f", acwr)).font(.callout)
                                    Text(acwrText(acwr)).font(.caption).foregroundStyle(.secondary)
                                }
                                Text("TRIMP \(Int(today.load.trimp.rounded()))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("心率区间（分钟）").font(.headline)
                            if today.load.zoneMinutes.allSatisfy({ $0 == 0 }) {
                                Text("今天没有分钟达到心率储备的 50%（Z1 以上）。")
                                    .font(.callout).foregroundStyle(.secondary)
                            } else {
                                Chart(Array(today.load.zoneMinutes.enumerated()), id: \.offset) { index, minutes in
                                    BarMark(x: .value("区间", "Z\(index + 1)"), y: .value("分钟", minutes))
                                        .foregroundStyle(VigorTokens.load)
                                }
                                .frame(height: 140)
                            }
                            Text(today.load.activityModelEnabled ? "空窗已用活动能量估算" : "空窗按静息心率处理（样本不足，回归未启用）")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("近 30 天负荷").font(.headline)
                            Chart(model.cycles.suffix(30)) { cycle in
                                BarMark(x: .value("日期", cycle.wakeTime, unit: .day), y: .value("负荷", cycle.load.strain))
                                    .foregroundStyle(VigorTokens.load)
                            }
                            .chartYScale(domain: 0...21)
                            .frame(height: 160)
                        }
                    }
                    if !today.load.workouts.isEmpty {
                        NavigationLink(value: Route.workout(today.load.workouts[0].id)) {
                            Label("查看训练详情", systemImage: "list.bullet")
                        }
                    }
                    if let cycling = model.cycling, !cycling.pmc.isEmpty {
                        CyclingLoadCard(output: cycling)
                    }
                } else {
                    Text(model.message ?? "暂无数据").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("负荷")
    }

    private func acwrText(_ acwr: Double) -> String {
        switch acwr {
        case ..<0.8: "欠训练"
        case 0.8...1.3: "适宜"
        case 1.3...1.5: "负荷上升较快"
        default: "受伤风险升高"
        }
    }
}

struct WorkoutListView: View {
    let model: AppModel
    @State private var showFiles = false

    private var rides: [RideResult] {
        (model.cycling?.rides ?? []).sorted { $0.start > $1.start }
    }

    var body: some View {
        List {
            if !rides.isEmpty {
                Section("骑行") {
                    ForEach(rides) { ride in
                        NavigationLink(value: Route.rideDetail(ride.id)) {
                            RideRow(ride: ride)
                        }
                    }
                }
                if rides.contains(where: CyclingText.needsFITHint) {
                    Section {
                        Button("导入 FIT 文件以获得完整的心率和功率") { showFiles = true }
                    }
                }
            }
            Section("其他训练") {
                ForEach(model.cycles.suffix(14).reversed().flatMap { $0.load.workouts }) { workout in
                VStack(alignment: .leading, spacing: 4) {
                    Text(WorkoutName.text(workout.activityType)).font(.headline)
                    Text(String(format: "负荷 %.1f · TRIMP %.0f · 峰值 %@ bpm",
                                workout.strain, workout.trimp,
                                workout.peakHeartRate.map { String(Int($0.rounded())) } ?? "—"))
                        .font(.caption).foregroundStyle(.secondary)
                    if let recovery = workout.recoveryOneMinute {
                        Text(String(format: "1 分钟心率恢复 %.0f bpm", recovery)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [UTType(filenameExtension: "fit") ?? .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { _ = await RideImportCoordinator.importURLs(urls) }
            }
        }
        .navigationTitle("训练")
    }
}

struct MetricDetailView: View {
    let model: AppModel
    let kind: MetricKind
    @State private var span = 30

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                Picker("范围", selection: $span) {
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                    Text("180 天").tag(180)
                }
                .pickerStyle(.segmented)
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.headline)
                        RangeChart(
                            points: points,
                            bandLower: band?.lower,
                            bandUpper: band?.upper,
                            color: color
                        )
                        if let summary = summary {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("关于").font(.headline)
                        Text(about).font(.callout)
                    }
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch kind {
        case .hrv: "HRV（RMSSD）"
        case .restingHeartRate: "夜间静息心率"
        case .respiratoryRate: "呼吸率"
        case .wristTemperature: "手腕温度"
        case .oxygen: "血氧"
        }
    }

    private var color: Color {
        switch kind {
        case .hrv, .restingHeartRate: VigorTokens.heart
        case .respiratoryRate, .oxygen: VigorTokens.breathing
        case .wristTemperature: VigorTokens.temperature
        }
    }

    private var about: String {
        switch kind {
        case .hrv: "RMSSD 反映副交感神经活性。我们用睡眠期间的逐拍心跳序列计算，剔除伪迹后按段加权合并。"
        case .restingHeartRate: "睡眠期间心率样本的第 10 百分位，比单个最低值稳定。"
        case .respiratoryRate: "睡眠期间呼吸率的中位数。"
        case .wristTemperature: "与个人基线的偏差，不是绝对温度。"
        case .oxygen: "睡眠期间血氧的中位数。"
        }
    }

    private var values: [(Date, Double)] {
        model.cycles.suffix(span).compactMap { cycle in
            switch kind {
            case .hrv: cycle.features.hrv.displayRMSSD.map { (cycle.wakeTime, $0) }
            case .restingHeartRate: cycle.features.restingHeartRate.value.map { (cycle.wakeTime, $0) }
            case .respiratoryRate: cycle.features.respiratoryRate.map { (cycle.wakeTime, $0) }
            case .wristTemperature: cycle.temperatureDelta.map { (cycle.wakeTime, $0) }
            case .oxygen: cycle.features.spo2MedianPercent.map { (cycle.wakeTime, $0) }
            }
        }
    }

    private var points: [RangeChart.Point] {
        values.map { RangeChart.Point(date: $0.0, value: $0.1) }
    }

    private var summary: String? {
        guard !values.isEmpty else { return nil }
        let numbers = values.map(\.1)
        let average = numbers.reduce(0, +) / Double(numbers.count)
        return String(format: "均值 %.1f，范围 %.1f – %.1f", average, numbers.min() ?? 0, numbers.max() ?? 0)
    }

    /// 基线范围带：最近一晚的 μ ± σ（HRV 按 ln 基线还原到 ms）。
    private var band: (lower: Double, upper: Double)? {
        guard let last = model.cycles.last else { return nil }
        switch kind {
        case .hrv:
            guard let stat = last.baselines[.lnRMSSDNight], let mu = stat.mu else { return nil }
            return (exp(mu - stat.sigma), exp(mu + stat.sigma))
        case .restingHeartRate:
            guard let stat = last.baselines[.restingHeartRate], let mu = stat.mu else { return nil }
            return (mu - stat.sigma, mu + stat.sigma)
        default:
            return nil
        }
    }
}

struct BrowseView: View {
    let model: AppModel

    var body: some View {
        List {
            Section("心脏") {
                NavigationLink("心肺适能", value: Route.cardioFitness)
                NavigationLink("HRV", value: Route.metric(.hrv))
                NavigationLink("夜间静息心率", value: Route.metric(.restingHeartRate))
            }
            Section("呼吸与体温") {
                NavigationLink("呼吸率", value: Route.metric(.respiratoryRate))
                NavigationLink("手腕温度", value: Route.metric(.wristTemperature))
                NavigationLink("血氧", value: Route.metric(.oxygen))
            }
            Section("睡眠与训练") {
                NavigationLink("睡眠", value: Route.sleep)
                NavigationLink("训练", value: Route.workout(UUID()))
                NavigationLink("报告", value: Route.report)
            }
            Section("骑行") {
                NavigationLink("体能管理（CTL / ATL / TSB）", value: Route.pmc)
                NavigationLink("FTP 与 90 天最佳功率", value: Route.ftp)
                NavigationLink("FTP 历史（近 365 天）", value: Route.ftpHistory)
                NavigationLink("有氧效率 EF 趋势", value: Route.efTrend)
                NavigationLink("骑行列表", value: Route.workout(UUID()))
            }
            if let age = model.bodyAge {
                Section("身体年龄（示意，待校准）") {
                    LabeledContent("估算身体年龄", value: String(format: "%.0f 岁", age.bodyAge))
                    LabeledContent("偏移", value: Formatters.signed(age.offsetYears, digits: 1, unit: " 年"))
                    if !age.missing.isEmpty {
                        Text("缺少：" + age.missing.joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("浏览")
    }
}
