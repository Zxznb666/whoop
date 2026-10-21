import SwiftUI
import Charts
import VigorScoring

/// 圆环仪表（PRD §7.3）：分区色、可选的目标区间刻度；“初步”状态在下方标注。
public struct ScoreRing: View {
    public var value: Double
    public var maximum: Double
    public var color: Color
    public var title: String
    public var valueText: String
    public var subtitle: String?
    public var targetRange: ClosedRange<Double>?

    public init(
        value: Double,
        maximum: Double = 100,
        color: Color,
        title: String,
        valueText: String,
        subtitle: String? = nil,
        targetRange: ClosedRange<Double>? = nil
    ) {
        self.value = value
        self.maximum = maximum
        self.color = color
        self.title = title
        self.valueText = valueText
        self.subtitle = subtitle
        self.targetRange = targetRange
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(max(value / maximum, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: value)
                if let targetRange {
                    ForEach([targetRange.lowerBound, targetRange.upperBound], id: \.self) { mark in
                        Capsule()
                            .fill(Color.primary.opacity(0.5))
                            .frame(width: 3, height: 10)
                            .offset(y: -66)
                            .rotationEffect(.degrees(360 * mark / maximum))
                    }
                }
                Text(valueText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            }
            .frame(width: 96, height: 96)
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Apple Health 式指标卡片：类别头、数值、迷你趋势、相对基线的箭头（PRD §6.1）。
public struct MetricCard: View {
    public enum Trend: Sendable { case up, down, flat }

    public var title: String
    public var systemImage: String
    public var color: Color
    public var value: String
    public var unit: String?
    public var detail: String?
    public var sparkline: [Double]
    public var baselineTrend: Trend?

    public init(
        title: String,
        systemImage: String,
        color: Color,
        value: String,
        unit: String? = nil,
        detail: String? = nil,
        sparkline: [Double] = [],
        baselineTrend: Trend? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.value = value
        self.unit = unit
        self.detail = detail
        self.sparkline = sparkline
        self.baselineTrend = baselineTrend
    }

    public var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if let unit {
                        Text(unit).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let baselineTrend {
                        Image(systemName: arrow(baselineTrend))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(arrowLabel(baselineTrend))
                    }
                }
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                if sparkline.count > 1 {
                    Chart(Array(sparkline.enumerated()), id: \.offset) { index, point in
                        LineMark(x: .value("日", index), y: .value("值", point))
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 36)
                }
            }
        }
    }

    private func arrow(_ trend: Trend) -> String {
        switch trend {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    private func arrowLabel(_ trend: Trend) -> String {
        switch trend {
        case .up: "高于基线"
        case .down: "低于基线"
        case .flat: "接近基线"
        }
    }
}

/// 白色（系统分组）卡片容器。
public struct SectionCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(VigorTokens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: VigorTokens.cardCornerRadius, style: .continuous))
    }

    private var cardBackground: some ShapeStyle {
        #if os(watchOS)
        Color.gray.opacity(0.25)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }
}

/// 数据质量标识：小圆点加文字，点开原因（PRD §3.3）。
public struct QualityBadge: View {
    public var level: DataQuality
    public var reasons: [String]

    public init(level: DataQuality, reasons: [String] = []) {
        self.level = level
        self.reasons = reasons
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(text).font(.caption.weight(.semibold))
            }
            ForEach(reasons, id: \.self) { reason in
                Text(reason).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var text: String {
        switch level {
        case .high: "数据质量：高"
        case .medium: "数据质量：中"
        case .low: "数据质量：低"
        case .none: "数据不足"
        }
    }

    private var color: Color {
        switch level {
        case .high: .green
        case .medium: .yellow
        case .low: .orange
        case .none: .gray
        }
    }
}

/// 状态横幅：未佩戴、校准中、质量低、生病预警（PRD §6.1）。
public struct StateBanner: View {
    public enum Kind: Sendable, Hashable {
        case unworn
        case calibrating
        case lowQuality
        case illness
    }

    public var kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    public var body: some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.medium))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(tint)
    }

    private var icon: String {
        switch kind {
        case .unworn: "applewatch.slash"
        case .calibrating: "hourglass"
        case .lowQuality: "exclamationmark.triangle"
        case .illness: "thermometer.medium"
        }
    }

    private var tint: Color {
        switch kind {
        case .unworn: .gray
        case .calibrating: .blue
        case .lowQuality: .orange
        case .illness: .red
        }
    }
}

/// 恢复分数的贡献瀑布图（PRD §6.2）：从基线出发，逐项加减。
public struct ContributionWaterfall: View {
    public var contributions: [RecoveryContribution]
    public var baseline: Double
    public var score: Double

    public init(contributions: [RecoveryContribution], baseline: Double = RecoveryScorer.baseline, score: Double) {
        self.contributions = contributions
        self.baseline = baseline
        self.score = score
    }

    private struct Step: Identifiable {
        var id: String
        var label: String
        var start: Double
        var end: Double
        var color: Color
    }

    private var steps: [Step] {
        var running = baseline
        var result: [Step] = [Step(id: "base", label: "基线", start: 0, end: baseline, color: .gray)]
        for item in contributions {
            let start = running
            running += item.points
            result.append(Step(
                id: item.component,
                label: item.component,
                start: min(start, running),
                end: max(start, running),
                color: item.points >= 0 ? .green : .red
            ))
        }
        result.append(Step(id: "score", label: "今日", start: 0, end: score, color: .primary.opacity(0.7)))
        return result
    }

    public var body: some View {
        Chart(steps) { step in
            RectangleMark(
                x: .value("项目", step.label),
                yStart: .value("起点", step.start),
                yEnd: .value("终点", step.end),
                width: .ratio(0.6)
            )
            .foregroundStyle(step.color)
        }
        .chartYScale(domain: 0...100)
        .frame(height: 220)
        .accessibilityLabel("贡献瀑布图，今日 \(Int(score.rounded())) 分")
    }
}

/// 睡眠分期图（hypnogram），分期按颜色着色，并可叠加心率（PRD §6.3）。
public struct Hypnogram: View {
    public var segments: [SleepStageSample]

    public init(segments: [SleepStageSample]) {
        self.segments = segments
    }

    public var body: some View {
        Chart(segments.indices, id: \.self) { index in
            let segment = segments[index]
            RectangleMark(
                xStart: .value("开始", segment.start),
                xEnd: .value("结束", segment.end),
                yStart: .value("层", rank(segment.stage)),
                yEnd: .value("层", rank(segment.stage) + 1)
            )
            .foregroundStyle(VigorTokens.color(for: segment.stage))
        }
        .chartYAxis {
            AxisMarks(values: [0.5, 1.5, 2.5, 3.5]) { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(label(forRank: number))
                    }
                }
            }
        }
        .frame(height: 160)
        .accessibilityLabel("睡眠分期图")
    }

    private func rank(_ stage: SleepStage) -> Double {
        switch stage {
        case .awake, .inBed: 3
        case .rem: 2
        case .core, .asleepUnspecified: 1
        case .deep: 0
        }
    }

    private func label(forRank rank: Double) -> String {
        switch Int(rank) {
        case 3: "清醒"
        case 2: "REM"
        case 1: "核心"
        default: "深睡"
        }
    }
}

/// 分钟级心率时间线，叠加心率区间的色带（PRD §6.4）。
public struct HRTimeline: View {
    public struct Point: Identifiable, Sendable {
        public var id: Date { date }
        public var date: Date
        public var bpm: Double

        public init(date: Date, bpm: Double) {
            self.date = date
            self.bpm = bpm
        }
    }

    public var points: [Point]
    public var restingHeartRate: Double
    public var maxHeartRate: Double

    public init(points: [Point], restingHeartRate: Double, maxHeartRate: Double) {
        self.points = points
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
    }

    public var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("时间", point.date), y: .value("心率", point.bpm))
                    .foregroundStyle(VigorTokens.heart)
            }
        }
        .chartYScale(domain: 40...max(maxHeartRate, 100))
        .frame(height: 140)
        .accessibilityLabel("心率时间线")
    }
}

/// 带基线范围带的趋势图（PRD §7.3 RangeChart，简化版：范围带与数值点）。
public struct RangeChart: View {
    public struct Point: Identifiable, Sendable {
        public var id: Date { date }
        public var date: Date
        public var value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    public var points: [Point]
    public var bandLower: Double?
    public var bandUpper: Double?
    public var color: Color

    public init(points: [Point], bandLower: Double? = nil, bandUpper: Double? = nil, color: Color) {
        self.points = points
        self.bandLower = bandLower
        self.bandUpper = bandUpper
        self.color = color
    }

    public var body: some View {
        Chart {
            if let bandLower, let bandUpper {
                RectangleMark(
                    yStart: .value("下沿", bandLower),
                    yEnd: .value("上沿", bandUpper)
                )
                .foregroundStyle(color.opacity(0.12))
            }
            ForEach(points) { point in
                PointMark(x: .value("日期", point.date), y: .value("数值", point.value))
                    .foregroundStyle(color)
                    .symbolSize(18)
            }
        }
        .frame(height: 180)
    }
}

#Preview("分数环") {
    HStack(spacing: 24) {
        ScoreRing(value: 72, color: VigorTokens.recoveryGreen, title: "恢复", valueText: "72")
        ScoreRing(value: 12, maximum: 21, color: VigorTokens.load, title: "负荷", valueText: "12.4", targetRange: 14...18)
        ScoreRing(value: 58, color: VigorTokens.sleep, title: "睡眠", valueText: "58", subtitle: "初步")
    }
    .padding()
}

#Preview("指标卡片") {
    MetricCard(
        title: "HRV", systemImage: "waveform.path.ecg", color: VigorTokens.heart,
        value: "41", unit: "ms", detail: "夜间 3 段", sparkline: [30, 35, 41, 38, 44], baselineTrend: .up
    )
    .padding()
}

#Preview("状态横幅") {
    VStack {
        StateBanner(kind: .unworn, text: "昨夜未佩戴，不出恢复分数")
        StateBanner(kind: .calibrating, text: "基线建立中（已有 3 晚）")
        StateBanner(kind: .lowQuality, text: "昨晚只有 1 段有效 HRV")
        StateBanner(kind: .illness, text: "连续两晚偏离基线，注意休息")
    }
    .padding()
}
