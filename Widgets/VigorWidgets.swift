import SwiftUI
import VigorDesign
import VigorStore
import WidgetKit

/// 小组件的一条快照。数据来自 App Group 中的共享状态文件；读不到时 `state` 为空。
struct VigorEntry: TimelineEntry {
    let date: Date
    let state: SharedState?
}

struct VigorProvider: TimelineProvider {
    func placeholder(in context: Context) -> VigorEntry {
        VigorEntry(date: .now, state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (VigorEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VigorEntry>) -> Void) {
        let now = Date.now
        // 数据只在主 App 同步后变化；每 30 分钟重新读取一次即可
        completion(Timeline(entries: [entry(at: now)], policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func entry(at date: Date) -> VigorEntry {
        VigorEntry(date: date, state: SharedStateStore.readLatest(groupID: VigorConstants.appGroupID))
    }
}

/// 无数据时的占位：“打开元气以更新”。
struct OpenToUpdateText: View {
    var body: some View {
        Text(GlanceFormat.openToUpdate)
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
}

struct RecoveryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VigorEntry

    var body: some View {
        if let state = entry.state {
            switch family {
            case .accessoryCircular:
                RecoveryRing(value: state.recovery, zoneRaw: state.recoveryZone)
            default:
                VStack(spacing: 6) {
                    Text("恢复").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    RecoveryRing(value: state.recovery, zoneRaw: state.recoveryZone)
                        .frame(width: 90, height: 90)
                }
            }
        } else {
            OpenToUpdateText()
        }
    }
}

struct ThreeScoresWidgetView: View {
    let entry: VigorEntry

    var body: some View {
        if let state = entry.state {
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    RecoveryRing(value: state.recovery, zoneRaw: state.recoveryZone)
                        .frame(width: 76, height: 76)
                    Text("恢复").font(.caption2).foregroundStyle(.secondary)
                }
                scoreColumn(title: "睡眠", value: GlanceFormat.sleep(state.sleepScore))
                scoreColumn(title: "负荷", value: GlanceFormat.strain(state.strain), detail: GlanceFormat.strainTarget(lower: state.strainTargetLower, upper: state.strainTargetUpper))
            }
        } else {
            OpenToUpdateText()
        }
    }

    private func scoreColumn(title: String, value: String, detail: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct BedtimeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VigorEntry

    var body: some View {
        if let state = entry.state {
            switch family {
            case .accessoryInline:
                Text("建议 \(GlanceFormat.bedtime(state.suggestedBedtime)) 入睡")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("建议入睡").font(.caption2).foregroundStyle(.secondary)
                    Text(GlanceFormat.bedtime(state.suggestedBedtime))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
            default:
                VStack(spacing: 6) {
                    Text("建议入睡").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(GlanceFormat.bedtime(state.suggestedBedtime))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                }
            }
        } else {
            OpenToUpdateText()
        }
    }
}

struct RecoveryWidget: Widget {
    let kind = "com.example.vigor.widget.recovery"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VigorProvider()) { entry in
            RecoveryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("恢复")
        .description("今天的恢复分数。")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ThreeScoresWidget: Widget {
    let kind = "com.example.vigor.widget.scores"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VigorProvider()) { entry in
            ThreeScoresWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日三项")
        .description("恢复、睡眠与负荷。")
        .supportedFamilies([.systemMedium])
    }
}

struct BedtimeWidget: Widget {
    let kind = "com.example.vigor.widget.bedtime"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VigorProvider()) { entry in
            BedtimeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("建议入睡")
        .description("今晚建议的入睡时间。")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct VigorWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecoveryWidget()
        ThreeScoresWidget()
        BedtimeWidget()
    }
}
