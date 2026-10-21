import SwiftUI
import VigorCoach
import VigorDesign
import VigorHealth
import VigorStore
import VigorScoring

struct SettingsView: View {
    @State private var baseNeed = AppSettings.baseSleepNeedHours
    @State private var useMaxHeartRate = AppSettings.maxHeartRateOverride != nil
    @State private var maxHeartRate = AppSettings.maxHeartRateOverride ?? 190
    @State private var targetWake = Self.date(fromMinutes: AppSettings.targetWakeMinutes)

    var body: some View {
        Form {
            Section("睡眠") {
                Stepper(value: $baseNeed, in: 6.5...9.5, step: 0.25) {
                    LabeledContent("基础睡眠需求", value: String(format: "%.2f 小时", baseNeed))
                }
                .onChange(of: baseNeed) { AppSettings.baseSleepNeedHours = baseNeed }
                DatePicker("目标起床时间", selection: $targetWake, displayedComponents: .hourAndMinute)
                    .onChange(of: targetWake) {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: targetWake)
                        AppSettings.targetWakeMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 30)
                    }
            }
            Section("心率") {
                Toggle("手动设置最大心率", isOn: $useMaxHeartRate)
                    .onChange(of: useMaxHeartRate) {
                        AppSettings.maxHeartRateOverride = useMaxHeartRate ? maxHeartRate : nil
                    }
                if useMaxHeartRate {
                    Stepper(value: $maxHeartRate, in: 150...220, step: 1) {
                        LabeledContent("最大心率", value: "\(Int(maxHeartRate)) bpm")
                    }
                    .onChange(of: maxHeartRate) { AppSettings.maxHeartRateOverride = maxHeartRate }
                }
            }
            Section("日志") {
                NavigationLink("日志题目", value: Route.journalQuestions)
            }
            Section("说明") {
                Text("设置保存在本机。修改后，下一次刷新时生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("数据") {
                NavigationLink("诊断", value: Route.diagnostics)
                NavigationLink("欢迎与授权", value: Route.onboarding)
            }
        }
        .navigationTitle("设置")
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
}

struct DiagnosticsView: View {
    @State private var entries = DiagnosticsLog.entries

    var body: some View {
        List {
            Section("应用") {
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("HealthKit", value: HealthAvailability.text)
                LabeledContent("App Group 容器", value: SharedStateStore.appGroupFileURL(groupID: "group.com.example.vigor") != nil ? "可用" : "不可用")
            }
            Section("错误与事件（原文）") {
                if entries.isEmpty {
                    Text("没有记录").foregroundStyle(.secondary)
                }
                ForEach(entries, id: \.self) { entry in
                    Text(entry).font(.caption.monospaced())
                }
            }
            Section {
                Button("清空日志", role: .destructive) {
                    DiagnosticsLog.clear()
                    entries = []
                }
            }
        }
        .navigationTitle("诊断")
    }
}

enum HealthAvailability {
    static var text: String {
        #if os(iOS)
        return "已在本机检测"
        #else
        return "不适用"
        #endif
    }
}

struct OnboardingView: View {
    @State private var status: String?

    var body: some View {
        List {
            Section("准备清单") {
                Label("HealthKit 读取权限（睡眠、心率、心跳序列等）", systemImage: "checkmark.circle")
                Label("手表开启睡眠追踪与睡眠专注模式", systemImage: "checkmark.circle")
                Label("手表开启手腕检测、血氧与后台心率", systemImage: "checkmark.circle")
                Label("确认生日与性别（优先读取健康数据）", systemImage: "checkmark.circle")
                Label("导入历史数据（默认 180 天）", systemImage: "checkmark.circle")
            }
            Section {
                Button("请求健康数据授权") {
                    Task { await requestAuthorization() }
                }
                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("欢迎")
    }

    private func requestAuthorization() async {
        #if targetEnvironment(simulator)
        status = "模拟器中跳过授权，使用合成数据。"
        #else
        do {
            try await LiveHealthDataSource().requestAuthorization()
            _ = await NotificationScheduler.requestAuthorization()
            status = "已授权，正在导入历史数据……"
            // 授权前的刷新读不到数据，这里必须全量导入，否则缓存里只有空数据
            await AppBootstrap.shared.refreshNow(mode: .full)
            status = "导入完成。"
        } catch {
            status = "授权失败：\(error.localizedDescription)"
            DiagnosticsLog.record("授权失败：\(error)")
        }
        #endif
    }
}

struct ReportView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                if let report = model.weeklyReport {
                    SectionCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("本周（周一至周日）").font(.headline)
                            row("周期数", "\(report.cycleCount)")
                            row("平均恢复", report.meanRecovery.map { String(format: "%.0f", $0) } ?? "—")
                            row("平均负荷", report.meanStrain.map { String(format: "%.1f", $0) } ?? "—")
                            row("平均睡眠分", report.meanSleepScore.map { String(format: "%.0f", $0) } ?? "—")
                            row("训练次数", "\(report.workoutCount)")
                            row("睡眠负债变化", report.debtChangeHours.map { String(format: "%+.1f 小时", $0) } ?? "—")
                        }
                    }
                    SectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("亮点").font(.headline)
                            if report.topInsights.isEmpty {
                                Text("还没有足够的记录生成洞察。").font(.callout).foregroundStyle(.secondary)
                            }
                            ForEach(report.topInsights) { insight in
                                Text(insight.sentence).font(.callout)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("暂无报告", systemImage: "doc.text", description: Text("还没有本周的数据。"))
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("周报")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Text(value).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

struct CoachView: View {
    let model: AppModel
    @State private var line: String?
    @State private var providerName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("今日一句").font(.headline)
                        Text(line ?? "正在生成…").font(.body)
                        Text("来源：\(providerName)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("隐私").font(.headline)
                        Text("教练只使用脱敏的每日汇总（分数、z-score、日志项），不包含原始心率或心跳序列。端侧模型不会把数据发出设备；云端模型需要单独开启，并在发送前预览内容。本版本尚未接入云端模型。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("教练")
        .task { await generate() }
    }

    private func generate() async {
        guard let today = model.today else {
            line = "还没有数据。"
            providerName = "—"
            return
        }
        let summary = SummaryBuilder.daily(from: today, journal: model.journal.last, calendar: .current)
        let kind = CoachRouter.choose(onDeviceAvailable: onDeviceAvailable(), claudeKey: nil)
        do {
            switch kind {
            case .onDevice:
                if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
                    #if canImport(FoundationModels)
                    line = try await OnDeviceCoach().dailyLine(for: summary)
                    providerName = OnDeviceCoach().name
                    return
                    #endif
                }
                fallthrough
            case .claude, .template:
                line = try await TemplateCoach().dailyLine(for: summary)
                providerName = TemplateCoach().name
            }
        } catch {
            line = "生成失败：\(error.localizedDescription)"
            providerName = "—"
        }
    }

    private func onDeviceAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
            return OnDeviceCoach.isAvailable
        }
        #endif
        return false
    }
}
