import SwiftUI
import VigorDesign
import VigorScoring

enum MetricKind: Hashable {
    case hrv
    case restingHeartRate
    case respiratoryRate
    case wristTemperature
    case oxygen
}

struct SummaryView: View {
    let model: AppModel
    @State private var destination: Route?

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                if let today = model.today {
                    header(today)
                    if let banner = banner(today) {
                        banner
                    }
                    rings(today)
                    coachLine(today)
                    metricGrid(today)
                    activity(today)
                    highlights
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("摘要")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("实验室") { destination = .lab }
                    Button("设置") { destination = .settings }
                    Button("诊断") { destination = .diagnostics }
                    Button("欢迎与授权") { destination = .onboarding }
                } label: {
                    Image(systemName: "person.crop.circle")
                        .accessibilityLabel("账户与工具")
                }
            }
        }
        .navigationDestination(item: $destination) { route in
            RouteDestination(route: route, model: model)
        }
    }

    private func header(_ today: CycleResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateText(today.wakeTime))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let updated = model.lastUpdated {
                Text("更新于 \(timeText(updated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func banner(_ today: CycleResult) -> StateBanner? {
        if today.features.partialWear {
            return StateBanner(kind: .unworn, text: "昨夜有超过 60 分钟未佩戴")
        }
        if today.illness == .possiblyUnwell {
            return StateBanner(kind: .illness, text: "连续两晚偏离基线，今天注意休息")
        }
        if today.quality.level == .low || today.quality.level == .none {
            return StateBanner(kind: .lowQuality, text: today.quality.reasons.first ?? "数据质量较低")
        }
        if today.baselines[.lnRMSSDNight]?.isCalibrating == true {
            return StateBanner(kind: .calibrating, text: "基线建立中")
        }
        return nil
    }

    private func rings(_ today: CycleResult) -> some View {
        SectionCard {
            HStack(alignment: .top) {
                NavigationLink(value: Route.recovery) {
                    ScoreRing(
                        value: today.recovery?.score ?? 0,
                        color: today.recovery.map { VigorTokens.color(for: $0.zone) } ?? .gray,
                        title: "恢复",
                        valueText: today.recovery.map { "\(Int($0.score.rounded()))" } ?? "—",
                        subtitle: today.recoveryState == .preliminary ? "初步" : nil
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                NavigationLink(value: Route.strain) {
                    ScoreRing(
                        value: today.load.strain,
                        maximum: 21,
                        color: VigorTokens.load,
                        title: "负荷",
                        valueText: String(format: "%.1f", today.load.strain),
                        targetRange: today.loadTarget.map { $0.lower...$0.upper }
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                NavigationLink(value: Route.sleep) {
                    ScoreRing(
                        value: today.sleepScore.score,
                        color: VigorTokens.sleep,
                        title: "睡眠",
                        valueText: "\(Int(today.sleepScore.score.rounded()))"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func coachLine(_ today: CycleResult) -> some View {
        SectionCard {
            Text(coachSentence(today))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricGrid(_ today: CycleResult) -> some View {
        let hrvSeries = model.cycles.suffix(14).compactMap { $0.features.hrv.displayRMSSD }
        let rhrSeries = model.cycles.suffix(14).compactMap { $0.features.restingHeartRate.value }
        return VStack(spacing: VigorTokens.cardSpacing) {
            HStack(spacing: VigorTokens.cardSpacing) {
                NavigationLink(value: Route.metric(.hrv)) {
                    MetricCard(
                        title: "HRV",
                        systemImage: "waveform.path.ecg",
                        color: VigorTokens.heart,
                        value: today.features.hrv.displayRMSSD.map { "\(Int($0.rounded()))" } ?? "—",
                        unit: "ms",
                        detail: hrvDetail(today),
                        sparkline: hrvSeries,
                        baselineTrend: trend(today.zHRV)
                    )
                }
                .buttonStyle(.plain)
                NavigationLink(value: Route.metric(.restingHeartRate)) {
                    MetricCard(
                        title: "夜间静息心率",
                        systemImage: "heart",
                        color: VigorTokens.heart,
                        value: today.features.restingHeartRate.value.map { "\(Int($0.rounded()))" } ?? "—",
                        unit: "bpm",
                        sparkline: rhrSeries,
                        baselineTrend: trend(today.zRHR.map { -$0 })
                    )
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: VigorTokens.cardSpacing) {
                MetricCard(
                    title: "呼吸率",
                    systemImage: "lungs",
                    color: VigorTokens.breathing,
                    value: today.features.respiratoryRate.map { String(format: "%.1f", $0) } ?? "—",
                    unit: "次/分",
                    baselineTrend: trend(today.zResp)
                )
                MetricCard(
                    title: "手腕温度偏差",
                    systemImage: "thermometer.medium",
                    color: VigorTokens.temperature,
                    value: today.temperatureDelta.map { String(format: "%+.1f", $0) } ?? "—",
                    unit: "°C"
                )
            }
            MetricCard(
                title: "血氧",
                systemImage: "drop",
                color: VigorTokens.breathing,
                value: today.features.spo2MedianPercent.map { String(format: "%.0f", $0) } ?? "—",
                unit: "%"
            )
        }
    }

    private func activity(_ today: CycleResult) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日活动")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VigorTokens.activity)
                if today.load.workouts.isEmpty {
                    Text("今天还没有训练记录").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(today.load.workouts) { workout in
                        HStack {
                            Text(WorkoutName.text(workout.activityType))
                            Spacer()
                            Text(String(format: "负荷 %.1f", workout.strain)).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    /// 亮点：固定规则生成，最多显示 4 条（D-067）。
    private var highlights: some View {
        Group {
            if !model.highlights.isEmpty {
                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("亮点").font(.headline)
                        ForEach(model.highlights.prefix(4)) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(item.title, systemImage: symbol(item.tone))
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(color(item.tone))
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func symbol(_ tone: Highlight.Tone) -> String {
        switch tone {
        case .positive: "checkmark.seal"
        case .neutral: "info.circle"
        case .caution: "exclamationmark.triangle"
        }
    }

    private func color(_ tone: Highlight.Tone) -> Color {
        switch tone {
        case .positive: .green
        case .neutral: .secondary
        case .caution: .orange
        }
    }

    private var emptyState: some View {
        SectionCard {
            VStack(spacing: 8) {
                Image(systemName: "applewatch").font(.largeTitle).foregroundStyle(.secondary)
                Text(model.message ?? "还没有数据").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 文案

    private func coachSentence(_ today: CycleResult) -> String {
        guard let recovery = today.recovery else {
            return "今天还没有恢复分数，先完成昨晚的数据同步。"
        }
        let target = today.loadTarget.map { "目标负荷 \(Int($0.lower))–\(Int($0.upper))" } ?? "按感觉安排训练"
        switch recovery.zone {
        case .green: return "状态良好，适合安排高强度训练，\(target)。"
        case .yellow: return "状态一般，中等强度为宜，\(target)。"
        case .red: return "身体需要恢复，今天以轻松活动为主，\(target)。"
        }
    }

    private func hrvDetail(_ today: CycleResult) -> String {
        let nights = today.features.hrv.nightValidCount
        let morning = today.features.hrv.morningValidCount > 0 ? "，有晨测" : ""
        return "夜间 \(nights) 段\(morning)"
    }

    private func trend(_ z: Double?) -> MetricCard.Trend? {
        guard let z else { return nil }
        if z > 0.5 { return .up }
        if z < -0.5 { return .down }
        return .flat
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

enum WorkoutName {
    static func text(_ type: String) -> String {
        switch type {
        case "running": "跑步"
        case "cycling": "骑行"
        case "walking": "步行"
        case "hiking": "徒步"
        case "traditionalStrengthTraining", "functionalStrengthTraining": "力量训练"
        case "highIntensityIntervalTraining": "高强度间歇"
        default: "训练"
        }
    }
}
