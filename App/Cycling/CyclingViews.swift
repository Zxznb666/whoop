import Charts
import SwiftUI
import UniformTypeIdentifiers
import VigorDesign
import VigorScoring

/// 骑行相关的界面（M6 §6）：训练列表中的骑行、骑行详情、负荷页的骑行体能卡片、PMC 与 FTP 页、设置中的 FTP 与导入。
enum CyclingText {
    static func number(_ value: Double?, digits: Int = 0, unit: String = "") -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", value) + unit
    }

    static func heartRateSource(_ origin: HeartRateOrigin?) -> String {
        switch origin {
        case .fitImport?: "心率带（FIT）"
        case .watchWorkout?: "Apple Watch 训练"
        case .otherWorkout?: "其他 App 训练"
        case .watchPassive?: "手表被动采样"
        case .other?: "其他来源"
        case nil: "无心率"
        }
    }

    static func powerSource(_ source: PowerSource) -> String {
        switch source {
        case .fit: "FIT"
        case .healthKit: "手表 / 健康"
        case .none: "无功率"
        }
    }

    static func ftpSource(_ source: FTPSource) -> String {
        switch source {
        case .manual: "手动设置"
        case .healthKit: "健康中的 FTP"
        case .estimated: "自动估算（最近 90 天最佳 20 分钟 × 0.95）"
        }
    }

    static let durationNames: [(Int, String)] = [(5, "5 秒"), (60, "1 分钟"), (300, "5 分钟"), (1200, "20 分钟"), (3600, "60 分钟")]

    /// 需要导入 FIT 的骑行：没有 FIT，也没有手表记录的心率（M6 §6 训练列表）。
    static func needsFITHint(_ ride: RideResult) -> Bool {
        !ride.sourceLabels.contains("FIT 导入")
            && !ride.sourceLabels.contains("Apple Watch")
            && (ride.heartRateOrigin.map { $0 < .otherWorkout } ?? true)
    }

    /// 功率覆盖不足 50%（有功率来源但不可用于指标）。
    static func powerInsufficient(_ ride: RideResult) -> Bool {
        ride.powerSource != .none && (ride.powerCoverage ?? 1) < 0.5
    }

    static func sourceBadge(_ ride: RideResult) -> String {
        "心率：\(heartRateSource(ride.heartRateOrigin)) · 功率：\(powerSource(ride.powerSource)) · 已合并 \(ride.memberCount) 个来源"
    }
}

/// 训练列表中的一次骑行（一组只显示一行）。
struct RideRow: View {
    let ride: RideResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Formatters.rideStart(ride.start)).font(.headline)
                Spacer()
                Text(CyclingText.number(Double(ride.movingSeconds) / 60, unit: " 分钟")).font(.caption).foregroundStyle(.secondary)
            }
            if CyclingText.powerInsufficient(ride) {
                Text("功率数据不足").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("NP \(CyclingText.number(ride.normalizedPower, unit: " W")) · TSS \(CyclingText.number(ride.tss)) · IF \(CyclingText.number(ride.intensityFactor, digits: 2))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(ride.sourceLabels.joined(separator: " + ")).font(.caption2).foregroundStyle(.secondary)
            if CyclingText.needsFITHint(ride) {
                Text("建议导入 FIT 文件以获得完整的心率和功率").font(.caption).foregroundStyle(VigorTokens.load)
            }
        }
    }
}

/// 骑行详情（M6 §6）：来源徽章、指标、功率区间分布与功率曲线对比。
struct RideDetailView: View {
    let model: AppModel
    /// 空字符串表示最近一次骑行；`garminOnly` 表示最近一次只有 Garmin 写入、没有 FIT 的骑行
    let rideID: String
    /// 逐秒曲线与分圈（由 `RideTimelineBuilder` 生成，进入页面时计算一次）
    @State private var timeline: RideTimeline?

    private var ride: RideResult? {
        let rides = (model.cycling?.rides ?? []).sorted { $0.start > $1.start }
        switch rideID {
        case "": return rides.first { $0.powerSource != .none } ?? rides.first
        case "garminOnly": return rides.first { CyclingText.needsFITHint($0) } ?? rides.first
        default: return rides.first { $0.id == rideID }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                if let ride {
                    header(ride)
                    metrics(ride)
                    timelineCard(ride)
                    if let timeline, !timeline.laps.isEmpty {
                        RideLapTable(laps: timeline.laps)
                    }
                    if let zones = ride.heartRateZoneSeconds { heartRateZoneChart(zones) }
                    if let zones = ride.zoneSeconds { zoneChart(zones) }
                    curveChart(ride)
                } else {
                    Text("还没有骑行记录。导入 FIT 文件或完成一次骑行训练后显示。").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("骑行详情")
        .task(id: ride?.id) {
            guard let ride else {
                timeline = nil
                return
            }
            timeline = RideTimelineBuilder.build(ride: ride, snapshot: model.snapshot ?? Self.emptySnapshot, importedRides: model.importedRides)
        }
    }

    /// 没有快照时（例如刚启动）用于让构建器返回空曲线的占位。
    private static var emptySnapshot: HealthSnapshot {
        HealthSnapshot(
            exportedAt: .distantPast, rangeStart: .distantPast, rangeEnd: .distantPast,
            profile: UserProfile(birthYear: nil, sex: .unknown), sleep: [], heartRate: [], hrvSDNN: [],
            restingHeartRate: [], respiratoryRate: [], wristTemperature: [], oxygenSaturation: [],
            heartbeatSeries: []
        )
    }

    /// 功率 / 心率双轴曲线卡片。没有逐秒数据（既没有功率也没有心率）时给出说明。
    private func timelineCard(_ ride: RideResult) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("功率与心率").font(.headline)
                if let timeline, timeline.points.contains(where: { $0.power != nil || $0.heartRate != nil }) {
                    RideTimelineChart(
                        timeline: timeline,
                        ftp: model.cycling?.ftp?.watts,
                        restingHeartRate: model.cycling?.restingHeartRate ?? 60,
                        maxHeartRate: model.cycling?.maxHeartRate ?? 190
                    )
                    Text("灰色底纹为暂停。左轴为功率（橙），心率（粉）按同一刻度映射，右轴为换算后的 bpm。点按曲线可查看具体数值。")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("这次骑行没有逐秒的功率或心率数据，无法绘制曲线。").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func heartRateZoneChart(_ zones: [Int]) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("心率区间（分钟）").font(.headline)
                Chart(Array(zones.enumerated()), id: \.offset) { index, seconds in
                    BarMark(x: .value("区间", "Z\(index + 1)"), y: .value("分钟", Double(seconds) / 60))
                        .foregroundStyle(.pink)
                }
                .frame(height: 140)
                Text("按心率储备比 HRR%：Z1 50–60%、Z2 60–70%、Z3 70–80%、Z4 80–90%、Z5 90–100%。低于 50% 不计入。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ ride: RideResult) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(Formatters.rideStartFull(ride.start)).font(.headline)
                Text(CyclingText.sourceBadge(ride)).font(.caption).foregroundStyle(.secondary)
                if CyclingText.powerInsufficient(ride) {
                    Text("功率数据不足（覆盖 \(Int(((ride.powerCoverage ?? 0) * 100).rounded()))%，低于 50%），未计算 NP、IF、TSS、功率区间与功率曲线。")
                        .font(.caption).foregroundStyle(VigorTokens.load)
                }
                if ride.compensatedMinutes > 0 {
                    Text("心率缺失 \(ride.compensatedMinutes) 分钟，已用功率估算负荷。").font(.caption).foregroundStyle(.secondary)
                }
                if ride.loadMayBeUnderestimated {
                    Text("心率缺失，负荷可能低估。").font(.caption).foregroundStyle(VigorTokens.load)
                }
                if CyclingText.needsFITHint(ride) {
                    Text("建议导入 FIT 文件以获得完整的心率和功率。").font(.caption).foregroundStyle(VigorTokens.load)
                }
            }
        }
    }

    private func metrics(_ ride: RideResult) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("指标").font(.headline)
                LabeledContent("标准化功率 NP", value: CyclingText.number(ride.normalizedPower, unit: " W"))
                LabeledContent("强度系数 IF", value: CyclingText.number(ride.intensityFactor, digits: 2))
                LabeledContent("训练压力 TSS", value: CyclingText.number(ride.tss))
                LabeledContent("机械功", value: CyclingText.number(ride.mechanicalWorkKJ, unit: " kJ"))
                LabeledContent("功体比", value: CyclingText.number(ride.wattsPerKilogram, digits: 2, unit: " W/kg"))
                LabeledContent("平均心率", value: CyclingText.number(ride.averageHeartRate, unit: " bpm"))
                LabeledContent("有氧效率 EF", value: CyclingText.number(ride.efficiencyFactor, digits: 2))
                LabeledContent("有氧解耦", value: ride.normalizedPower == nil ? "—" : (ride.aerobicDecoupling.map { String(format: "%.1f%%", $0) } ?? "不足 60 分钟"))
                if let decoupling = ride.aerobicDecoupling {
                    Text(decoupling < 5 ? "解耦低于 5%：有氧基础良好。" : "解耦 5% 以上：有氧耐力还有提升空间。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }

    private func zoneChart(_ zones: [Int]) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("功率区间（分钟）").font(.headline)
                Chart(Array(zones.enumerated()), id: \.offset) { index, seconds in
                    BarMark(x: .value("区间", "Z\(index + 1)"), y: .value("分钟", Double(seconds) / 60))
                        .foregroundStyle(VigorTokens.load)
                }
                .frame(height: 140)
            }
        }
    }

    private func curveChart(_ ride: RideResult) -> some View {
        let rows: [(name: String, duration: String, watts: Double)] = CyclingText.durationNames.flatMap { duration, label in
            var result: [(String, String, Double)] = []
            if let value = ride.powerCurve[duration] { result.append(("本次", label, value)) }
            if let best = model.cycling?.powerCurve90[duration] { result.append(("90 天最佳", label, best)) }
            return result
        }
        return SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("功率曲线").font(.headline)
                if ride.powerCurve.isEmpty {
                    // 没有本次骑行的功率曲线时，不展示 90 天最佳（否则看起来像是本次骑行有功率）
                    Text(CyclingText.powerInsufficient(ride) ? "功率数据不足，未计算功率曲线。" : "这次骑行没有功率数据，无法计算功率曲线。")
                        .font(.callout).foregroundStyle(.secondary)
                } else if rows.isEmpty {
                    Text("骑行时间不足，无法计算功率曲线。").font(.callout).foregroundStyle(.secondary)
                } else {
                    Chart(rows, id: \.duration) { row in
                        BarMark(x: .value("时长", row.duration), y: .value("瓦", row.watts))
                            .foregroundStyle(by: .value("对比", row.name))
                            .position(by: .value("对比", row.name))
                    }
                    .frame(height: 180)
                }
            }
        }
    }
}

/// 负荷页的“骑行体能”卡片（CTL / ATL / TSB，最近 90 天）。
struct CyclingLoadCard: View {
    let output: CyclingOutput

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("骑行体能").font(.headline)
                if let last = output.pmc.last {
                    Text("CTL \(Int(last.ctl.rounded())) · ATL \(Int(last.atl.rounded())) · TSB \(Int(last.tsb.rounded()))")
                        .font(.callout)
                    Text(PerformanceManagement.statusText(tsb: last.tsb)).font(.caption).foregroundStyle(.secondary)
                    PMCChart(points: Array(output.pmc.suffix(90)))
                        .frame(height: 150)
                    NavigationLink(value: Route.pmc) {
                        Label("查看体能管理", systemImage: "chart.line.uptrend.xyaxis")
                    }
                } else {
                    Text("导入或完成骑行后显示。").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// CTL、ATL、TSB 的折线图。
struct PMCChart: View {
    let points: [PMCPoint]

    private struct Series: Identifiable {
        var id: String { "\(name)-\(day.timeIntervalSince1970)" }
        var day: Date
        var name: String
        var value: Double
    }

    private var series: [Series] {
        points.flatMap { point in
            [
                Series(day: point.day, name: "CTL", value: point.ctl),
                Series(day: point.day, name: "ATL", value: point.atl),
                Series(day: point.day, name: "TSB", value: point.tsb),
            ]
        }
    }

    var body: some View {
        Chart(series) { row in
            LineMark(x: .value("日期", row.day, unit: .day), y: .value("值", row.value))
                .foregroundStyle(by: .value("指标", row.name))
        }
        .chartForegroundStyleScale(["CTL": VigorTokens.load, "ATL": .orange, "TSB": .secondary])
    }
}

/// 体能管理（PMC）详情页（M6 §6 负荷页的展开）。
struct PMCDetailView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                if let output = model.cycling, let last = output.pmc.last {
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("当前状态：\(PerformanceManagement.statusText(tsb: last.tsb))").font(.headline)
                            Text("CTL（体能）\(String(format: "%.1f", last.ctl)) · ATL（疲劳）\(String(format: "%.1f", last.atl)) · TSB（状态）\(String(format: "%.1f", last.tsb))")
                                .font(.callout)
                            Text("TSB = 前一天的 CTL − 前一天的 ATL。TSB < −20 为疲劳累积，−10 至 +5 为训练适宜，> +15 为状态新鲜。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("最近 90 天").font(.headline)
                            PMCChart(points: Array(output.pmc.suffix(90)))
                                .frame(height: 220)
                        }
                    }
                    Text("骑行的 TSS 只用于体能管理和骑行页，不进入恢复与睡眠的计算。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("导入或完成骑行后显示。").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("体能管理")
    }
}

/// FTP 与 90 天最佳功率曲线（M6 §6 浏览页与设置页的展示）。
struct FTPDetailView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FTP").font(.headline)
                        if let ftp = model.cycling?.ftp {
                            Text("\(Int(ftp.watts.rounded())) W").font(.title2.weight(.semibold))
                            Text("来源：\(CyclingText.ftpSource(ftp.source))").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("还没有 FTP。骑行数据不足以估算。").font(.callout).foregroundStyle(.secondary)
                        }
                        Text("优先级：手动设置 > 健康中的 FTP > 自动估算。手动设置在“设置 → 骑行”中修改。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("有氧效率 EF 趋势").font(.headline)
                        let efRides = (model.cycling?.rides ?? []).filter { $0.efficiencyFactor != nil }.sorted { $0.start < $1.start }
                        if efRides.isEmpty {
                            Text("需要同时有功率和心率的骑行。").font(.callout).foregroundStyle(.secondary)
                        } else {
                            Chart(efRides) { ride in
                                LineMark(x: .value("日期", ride.start, unit: .day), y: .value("EF", ride.efficiencyFactor ?? 0))
                                    .foregroundStyle(VigorTokens.load)
                                PointMark(x: .value("日期", ride.start, unit: .day), y: .value("EF", ride.efficiencyFactor ?? 0))
                                    .foregroundStyle(VigorTokens.load)
                            }
                            .frame(height: 160)
                        }
                    }
                }
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("最近 90 天最佳功率").font(.headline)
                        let curve = model.cycling?.powerCurve90 ?? [:]
                        if curve.isEmpty {
                            Text("没有足够的功率数据。").font(.callout).foregroundStyle(.secondary)
                        } else {
                            Chart(CyclingText.durationNames.compactMap { duration, label in
                                curve[duration].map { (label, $0) }
                            }, id: \.0) { label, watts in
                                BarMark(x: .value("时长", label), y: .value("瓦", watts))
                                    .foregroundStyle(VigorTokens.load)
                            }
                            .frame(height: 180)
                        }
                    }
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("FTP")
    }
}

/// 设置中的“骑行”分组：FTP 手动设置、FIT 导入入口。
struct CyclingSettingsSection: View {
    let model: AppModel
    @State private var manualFTP = AppSettings.manualFTP ?? 0
    @State private var message: String?
    @State private var showFiles = false
    @State private var showFolder = false

    private static let fitType = UTType(filenameExtension: "fit") ?? .data

    var body: some View {
        Section("骑行") {
            Stepper(value: $manualFTP, in: 0...600, step: 1) {
                LabeledContent("手动 FTP", value: manualFTP > 0 ? "\(Int(manualFTP)) W" : "未设置")
            }
            .onChange(of: manualFTP) { AppSettings.manualFTP = manualFTP > 0 ? manualFTP : nil }
            if let ftp = model.cycling?.ftp {
                LabeledContent("当前使用", value: "\(Int(ftp.watts.rounded())) W · \(CyclingText.ftpSource(ftp.source))")
            }
            LabeledContent("检测到的 Garmin 写入", value: garminSourceText)
            Button("导入 FIT 文件") { showFiles = true }
            Button("导入文件夹（如 Garmin/Activity）") { showFolder = true }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            Text("FIT 文件保存在本机，并包含在加密备份中。导入的骑行不会写回健康数据。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [Self.fitType], allowsMultipleSelection: true) { result in
            handle(result)
        }
        .fileImporter(isPresented: $showFolder, allowedContentTypes: [.folder]) { result in
            handle(result.map { [$0] })
        }
    }

    /// 健康数据中来自 Garmin 的训练来源（按 Bundle ID 统计）。优先级目前固定（D-107），这里只列出。
    private var garminSourceText: String {
        let workouts = (model.snapshot?.workouts ?? []).filter { $0.sourceBundleID?.lowercased().contains("garmin") == true }
        guard !workouts.isEmpty else { return "未检测到" }
        let bundles = Dictionary(grouping: workouts, by: { $0.sourceBundleID ?? "" }).mapValues(\.count)
        return bundles.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value) 次" }.joined(separator: "；")
    }

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                let summary = await RideImportCoordinator.importURLs(urls)
                message = summary.text
            }
        case .failure(let error):
            message = "无法打开所选文件：\(error.localizedDescription)"
        }
    }
}
