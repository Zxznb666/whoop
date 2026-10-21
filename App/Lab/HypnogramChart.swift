import Charts
import SwiftUI
import VigorScoring

/// 睡眠分期图：纵轴依次为清醒、REM、核心、深睡；竖线标出片段位置（有效为蓝，无效为灰）。
struct HypnogramChart: View {
    let session: SleepSession
    let segments: [HRVWindow]

    var body: some View {
        Chart {
            ForEach(Array(session.stages.enumerated()), id: \.offset) { _, sample in
                RectangleMark(
                    xStart: .value("开始", sample.start),
                    xEnd: .value("结束", sample.end),
                    yStart: .value("层级", Self.level(of: sample.stage) - 0.4),
                    yEnd: .value("层级", Self.level(of: sample.stage) + 0.4)
                )
                .foregroundStyle(Self.color(of: sample.stage))
            }

            ForEach(segments, id: \.seriesID) { segment in
                RuleMark(x: .value("片段", Self.midpoint(of: segment)))
                    .foregroundStyle(segment.isValid ? Color.blue : Color.gray)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYScale(domain: -0.5...3.5)
        .chartYAxis {
            AxisMarks(values: [0.0, 1.0, 2.0, 3.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let level = value.as(Double.self) {
                        Text(Self.name(of: level))
                    }
                }
            }
        }
    }

    private static func level(of stage: SleepStage) -> Double {
        switch stage {
        case .awake, .inBed: 3
        case .rem: 2
        case .core, .asleepUnspecified: 1
        case .deep: 0
        }
    }

    private static func name(of level: Double) -> String {
        switch Int(level.rounded()) {
        case 3: "清醒"
        case 2: "REM"
        case 1: "核心"
        default: "深睡"
        }
    }

    private static func color(of stage: SleepStage) -> Color {
        switch stage {
        case .awake, .inBed: .orange
        case .rem: .pink
        case .core, .asleepUnspecified: .cyan
        case .deep: .indigo
        }
    }

    private static func midpoint(of segment: HRVWindow) -> Date {
        segment.start.addingTimeInterval(segment.end.timeIntervalSince(segment.start) / 2)
    }
}
