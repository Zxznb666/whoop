import Charts
import SwiftUI
import VigorDesign
import VigorScoring

/// 骑行详情的功率 / 心率双轴曲线（M6 补完 C2）。
/// 左轴为功率；心率按 `RideChartScale` 映射到功率刻度后画在同一张图上，右轴标注换算回来的 bpm。
/// 只有一种数据时只画那一条，并隐藏另一侧的坐标轴。暂停的时段用浅灰色底纹标出。
struct RideTimelineChart: View {
    let timeline: RideTimeline
    let ftp: Double?
    let restingHeartRate: Double
    let maxHeartRate: Double

    @State private var selected: Double?

    private struct Row: Identifiable {
        var id: String
        var offset: Double
        var value: Double
        var kind: String
        var segment: Int
    }

    private struct PauseRun: Identifiable {
        var id: Double
        var start: Double
        var end: Double
    }

    private static let powerName = "功率"
    private static let heartRateName = "心率"

    private var points: [RideTimelinePoint] { timeline.points }
    private var hasPower: Bool { points.contains { $0.power != nil } }
    private var hasHeartRate: Bool { points.contains { $0.heartRate != nil } }
    private var low: Double { min(restingHeartRate, maxHeartRate - 1) }
    private var high: Double { max(maxHeartRate, low + 1) }

    /// 功率轴上限（只有功率时有意义）
    private var powerTop: Double {
        RideChartScale.powerTop(maxPower: points.compactMap(\.power).max() ?? 0, ftp: ftp)
    }

    private func plotted(heartRate bpm: Double) -> Double {
        hasPower ? RideChartScale.mappedHeartRate(bpm, low: low, high: high, top: powerTop) : bpm
    }

    /// 连续有值的一段画成一条线；缺失处断开，而不是连成直线。
    private func rows(kind: String, value: (RideTimelinePoint) -> Double?) -> [Row] {
        var result: [Row] = []
        var segment = 0
        var inRun = false
        for (index, point) in points.enumerated() {
            guard let number = value(point) else {
                if inRun { segment += 1; inRun = false }
                continue
            }
            result.append(Row(id: "\(kind)-\(index)", offset: point.offset, value: number, kind: kind, segment: segment))
            inRun = true
        }
        return result
    }

    private var powerRows: [Row] { rows(kind: Self.powerName) { $0.power } }
    private var heartRateRows: [Row] { rows(kind: Self.heartRateName) { point in point.heartRate.map { plotted(heartRate: $0) } } }

    private var pauseRuns: [PauseRun] {
        var runs: [PauseRun] = []
        var current: (start: Double, end: Double)?
        for point in points {
            if point.paused {
                if let run = current {
                    current = (run.start, point.offset)
                } else {
                    current = (point.offset, point.offset)
                }
            } else if let run = current {
                runs.append(PauseRun(id: run.start, start: run.start, end: run.end))
                current = nil
            }
        }
        if let run = current { runs.append(PauseRun(id: run.start, start: run.start, end: run.end)) }
        return runs
    }

    private var yDomain: ClosedRange<Double> {
        if hasPower { return 0...powerTop }
        return low...high
    }

    private var nearest: RideTimelinePoint? {
        guard let selected else { return nil }
        return points.min { abs($0.offset - selected) < abs($1.offset - selected) }
    }

    var body: some View {
        Chart {
            ForEach(pauseRuns) { run in
                RectangleMark(
                    xStart: .value("暂停开始", run.start),
                    xEnd: .value("暂停结束", run.end),
                    yStart: .value("下", yDomain.lowerBound),
                    yEnd: .value("上", yDomain.upperBound)
                )
                .foregroundStyle(Color.gray.opacity(0.15))
            }
            if hasPower {
                ForEach(powerRows) { row in
                    LineMark(x: .value("时间", row.offset), y: .value(row.kind, row.value), series: .value("段", "\(row.kind)\(row.segment)"))
                        .foregroundStyle(by: .value("指标", row.kind))
                        .interpolationMethod(.linear)
                }
            }
            if hasHeartRate {
                ForEach(heartRateRows) { row in
                    LineMark(x: .value("时间", row.offset), y: .value(row.kind, row.value), series: .value("段", "\(row.kind)\(row.segment)"))
                        .foregroundStyle(by: .value("指标", row.kind))
                        .interpolationMethod(.linear)
                }
            }
            if let nearest {
                RuleMark(x: .value("选中", nearest.offset))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                        selectionLabel(nearest)
                    }
            }
        }
        .chartForegroundStyleScale([Self.powerName: Color.orange, Self.heartRateName: Color.pink])
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(Self.minutesLabel(seconds))
                    }
                }
            }
        }
        .chartYAxis {
            if hasPower {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let watts = value.as(Double.self) {
                            Text("\(Int(watts.rounded())) W")
                        }
                    }
                }
            } else if hasHeartRate {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bpm = value.as(Double.self) {
                            Text("\(Int(bpm.rounded())) bpm")
                        }
                    }
                }
            }
            if hasPower && hasHeartRate {
                AxisMarks(position: .trailing, values: rightTickPositions) { value in
                    AxisValueLabel {
                        if let mapped = value.as(Double.self) {
                            let bpm = RideChartScale.heartRate(mapped: mapped, low: low, high: high, top: powerTop)
                            Text("\(Int(bpm.rounded()))").foregroundStyle(.pink)
                        }
                    }
                }
            }
        }
        .frame(height: 230)
        .accessibilityLabel("功率与心率曲线")
    }

    private var rightTickPositions: [Double] {
        RideChartScale.heartRateTicks(low: low, high: high).map {
            RideChartScale.mappedHeartRate($0, low: low, high: high, top: powerTop)
        }
    }

    private func selectionLabel(_ point: RideTimelinePoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.clockLabel(point.offset)).font(.caption2.weight(.semibold))
            if let watts = point.power {
                Text("功率 \(Int(watts.rounded())) W").font(.caption2).foregroundStyle(.orange)
            }
            if let bpm = point.heartRate {
                Text("心率 \(Int(bpm.rounded())) bpm").font(.caption2).foregroundStyle(.pink)
            }
            if point.paused {
                Text("暂停").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    /// 横轴刻度：分钟数。
    static func minutesLabel(_ seconds: Double) -> String {
        "\(Int(seconds / 60)) 分"
    }

    /// 时间点：m:ss，超过 1 小时为 h:mm:ss。
    static func clockLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// 分圈表（M6 补完 C2）。只有导入的 FIT 才有分圈。
struct RideLapTable: View {
    let laps: [RideLapSummary]

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("分圈").font(.headline)
                Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("圈").gridColumnAlignment(.leading)
                        Text("时长")
                        Text("距离")
                        Text("功率")
                        Text("NP")
                        Text("心率")
                        Text("最大")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    ForEach(laps, id: \.index) { lap in
                        GridRow {
                            Text("\(lap.index)").gridColumnAlignment(.leading)
                            Text(Self.duration(lap.durationSeconds))
                            Text(lap.distanceMeters.map { String(format: "%.2f km", $0 / 1000) } ?? "—")
                            Text(CyclingText.number(lap.averagePower, unit: " W"))
                            Text(CyclingText.number(lap.normalizedPower, unit: " W"))
                            Text(CyclingText.number(lap.averageHeartRate))
                            Text(CyclingText.number(lap.maxHeartRate))
                        }
                    }
                }
                .font(.caption.monospacedDigit())
            }
        }
    }

    static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
