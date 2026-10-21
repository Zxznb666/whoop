import HealthKit
import SwiftUI
import VigorDesign
import VigorStore
import VigorScoring

@main
struct VigorWatchApp: App {
    init() {
        WatchStore.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchTodayView()
            }
            .environment(WatchStore.shared)
        }
    }
}

/// 今日页：三个分数、建议入睡时间与累积负荷（PRD §6.8）。没有数据时显示提示，不会崩溃。
struct WatchTodayView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            if let state = store.state {
                VStack(spacing: 10) {
                    RecoveryRing(value: state.recovery, zoneRaw: state.recoveryZone)
                        .frame(width: 84, height: 84)
                    HStack(spacing: 12) {
                        metric("睡眠", GlanceFormat.sleep(state.sleepScore))
                        metric("负荷", GlanceFormat.strain(state.strain))
                    }
                    if let target = GlanceFormat.strainTarget(lower: state.strainTargetLower, upper: state.strainTargetUpper) {
                        Text(target).font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text("建议入睡").font(.caption2).foregroundStyle(.secondary)
                        Text(GlanceFormat.bedtime(state.suggestedBedtime))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    Text("同步于 \(state.updatedAt.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    NavigationLink("训练模式") {
                        WorkoutView(state: state)
                    }
                    .padding(.top, 4)
                }
            } else {
                VStack(spacing: 8) {
                    Text(GlanceFormat.openToUpdate)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Text("手机同步后，这里会显示今天的分数。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    NavigationLink("训练模式") {
                        WorkoutView(state: nil)
                    }
                }
            }
        }
        .navigationTitle("元气")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// 训练模式：选择类型 → 实时心率、区间、本次与全天累积负荷 → 结束并保存。
struct WorkoutView: View {
    let state: SharedState?
    @State private var controller = WorkoutController()

    var body: some View {
        Group {
            if controller.isRunning {
                runningView
            } else {
                List {
                    Section("选择训练") {
                        ForEach(WorkoutController.activities, id: \.title) { activity in
                            Button(activity.title) {
                                Task { await controller.start(activity.type, state: state) }
                            }
                        }
                    }
                    if let error = controller.errorText {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("训练")
    }

    private var runningView: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(controller.heartRate.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(.secondary)
                if let zone = controller.zoneIndex {
                    Text("区间 \(zone + 1)").font(.footnote.weight(.semibold))
                }
                HStack(spacing: 14) {
                    VStack {
                        Text(GlanceFormat.strain(controller.sessionStrain)).font(.headline).monospacedDigit()
                        Text("本次负荷").font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack {
                        Text(GlanceFormat.strain(controller.dayStrain)).font(.headline).monospacedDigit()
                        Text("全天（估算）").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("结束并保存", role: .destructive) {
                    Task { await controller.end() }
                }
                .padding(.top, 6)
            }
        }
    }
}
