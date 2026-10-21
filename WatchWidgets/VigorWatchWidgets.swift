import SwiftUI
import VigorDesign
import VigorStore
import WidgetKit

/// 手表复杂功能的一条快照（PRD §6.8）。数据来自手机经 WatchConnectivity 推送并缓存的共享状态。
struct WatchGlanceEntry: TimelineEntry {
    let date: Date
    let state: SharedState?
}

struct WatchGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchGlanceEntry {
        WatchGlanceEntry(date: .now, state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchGlanceEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchGlanceEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(entries: [entry(at: now)], policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func entry(at date: Date) -> WatchGlanceEntry {
        WatchGlanceEntry(date: date, state: SharedStateStore.readLatest(groupID: VigorConstants.appGroupID))
    }
}

struct WatchOpenToUpdate: View {
    var body: some View {
        Text(GlanceFormat.openToUpdate)
            .font(.caption2)
            .multilineTextAlignment(.center)
    }
}

struct WatchRecoveryComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchGlanceEntry

    var body: some View {
        if let state = entry.state {
            switch family {
            case .accessoryInline:
                Text("恢复 \(GlanceFormat.recovery(state.recovery)) · 负荷 \(GlanceFormat.strain(state.strain))")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("恢复 \(GlanceFormat.recovery(state.recovery))")
                        .font(.headline)
                    Text("负荷 \(GlanceFormat.strain(state.strain))  睡眠 \(GlanceFormat.sleep(state.sleepScore))")
                        .font(.caption)
                }
            default:
                RecoveryRing(value: state.recovery, zoneRaw: state.recoveryZone)
            }
        } else {
            WatchOpenToUpdate()
        }
    }
}

struct WatchBedtimeComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchGlanceEntry

    var body: some View {
        if let state = entry.state {
            switch family {
            case .accessoryInline:
                Text("建议 \(GlanceFormat.bedtime(state.suggestedBedtime)) 入睡")
            case .accessoryCircular:
                Text(GlanceFormat.bedtime(state.suggestedBedtime))
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6)
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Text("建议入睡").font(.caption2).foregroundStyle(.secondary)
                    Text(GlanceFormat.bedtime(state.suggestedBedtime))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
            }
        } else {
            WatchOpenToUpdate()
        }
    }
}

struct WatchRecoveryComplication: Widget {
    let kind = "com.example.vigor.watch.recovery"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchGlanceProvider()) { entry in
            WatchRecoveryComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("恢复")
        .description("今天的恢复分数与负荷。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WatchBedtimeComplication: Widget {
    let kind = "com.example.vigor.watch.bedtime"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchGlanceProvider()) { entry in
            WatchBedtimeComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("建议入睡")
        .description("今晚建议的入睡时间。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct VigorWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchRecoveryComplication()
        WatchBedtimeComplication()
    }
}
