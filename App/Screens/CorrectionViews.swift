import SwiftUI
import VigorDesign
import VigorScoring
import VigorStore

/// 修正睡眠时段（PRD §5.2 第 8 条）：只改分析用的起止时间，不改 HealthKit 原始数据。保存后全量窗口重算。
struct SleepCorrectionSheet: View {
    let model: AppModel
    let cycle: CycleResult
    @State private var start: Date
    @State private var end: Date
    @State private var hasOverride = false
    @State private var message: String?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, cycle: CycleResult) {
        self.model = model
        self.cycle = cycle
        _start = State(initialValue: cycle.features.session.start)
        _end = State(initialValue: cycle.features.session.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("自动识别", value: "\(Formatters.clock(cycle.features.session.start)) – \(Formatters.clock(cycle.features.session.end))")
                    DatePicker("入睡", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("醒来", selection: $end, displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("睡眠时段")
                } footer: {
                    Text("修正后，分期会按新的起止时间裁剪；原始数据不变。入睡必须早于醒来。")
                }

                Section {
                    Button("保存修正", action: save)
                        .disabled(isSaving || end <= start)
                    if hasOverride {
                        Button("恢复自动识别", role: .destructive, action: clear)
                            .disabled(isSaving)
                    }
                }

                if let message {
                    Section {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("修正睡眠时段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                let stored = try? await AppBootstrap.shared.environment.repository?.sleepOverrides()
                hasOverride = stored?[cycle.features.session.nightKey] != nil
            }
        }
    }

    private func save() {
        apply(SleepOverride(start: start, end: end), label: "已保存修正，正在重算。")
    }

    private func clear() {
        apply(nil, label: "已恢复自动识别，正在重算。")
    }

    private func apply(_ override: SleepOverride?, label: String) {
        guard let repository = AppBootstrap.shared.environment.repository else {
            message = "存储未就绪，请稍后再试。"
            return
        }
        isSaving = true
        Task {
            do {
                try await repository.setSleepOverride(nightKey: cycle.features.session.nightKey, override)
                hasOverride = override != nil
                message = label
                await AppBootstrap.shared.refreshNow(mode: .window(days: 30))
                await model.load(source: model.source)
                dismiss()
            } catch {
                message = "保存失败：\(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}

/// 设置中的“排除指定夜晚”（PRD §5.2）：被排除的醒来日不进入基线，结果会标注为手动排除。
struct ExclusionsView: View {
    let model: AppModel
    @State private var excluded: [DateComponents] = []
    @State private var pickedDay = Date()
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(excluded, id: \.self) { day in
                    Text(Formatters.wakeDay(Calendar.current.date(from: day) ?? Date()))
                }
                .onDelete(perform: remove)
                if excluded.isEmpty {
                    Text("没有排除的夜晚。").foregroundStyle(.secondary)
                }
            } header: {
                Text("已排除")
            } footer: {
                Text("左滑可以取消排除。被排除的夜晚仍会计算结果，但不进入基线，也不推送。")
            }

            Section {
                DatePicker("醒来日", selection: $pickedDay, in: ...Date(), displayedComponents: .date)
                Button("排除这一晚") { add() }
            } header: {
                Text("添加")
            }

            if let message {
                Section {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("排除指定夜晚")
        .task { await reload() }
    }

    private func reload() async {
        excluded = Array((try? await AppBootstrap.shared.environment.repository?.manualExclusions()) ?? [])
            .sorted { ($0.year ?? 0, $0.month ?? 0, $0.day ?? 0) < ($1.year ?? 0, $1.month ?? 0, $1.day ?? 0) }
    }

    private func add() {
        setExcluded(Calendar.current.dateComponents([.year, .month, .day], from: pickedDay), true)
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets {
            setExcluded(excluded[index], false)
        }
    }

    private func setExcluded(_ day: DateComponents, _ value: Bool) {
        guard let repository = AppBootstrap.shared.environment.repository else { return }
        Task {
            do {
                try await repository.setManualExclusion(wakeDay: day, excluded: value)
                message = value ? "已排除，正在重算。" : "已取消排除，正在重算。"
                await reload()
                await AppBootstrap.shared.refreshNow(mode: .window(days: 30))
                await model.load(source: model.source)
            } catch {
                message = "保存失败：\(error.localizedDescription)"
            }
        }
    }
}
