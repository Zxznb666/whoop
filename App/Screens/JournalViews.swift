import SwiftUI
import VigorDesign
import VigorScoring

/// 日志标签页：今天的日志卡片、补填入口、影响洞察与最近记录（PRD §6.5）。
struct JournalView: View {
    let model: AppModel
    @State private var backfillDate = Date()

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.journalEdit(todayNight)) {
                    TodayJournalRow(entry: model.journalEntry(on: todayNight))
                }
            } header: {
                Text("今天的日志")
            } footer: {
                Text("问题针对的是昨天。醒来后的提醒也是为了这张卡片。")
            }

            Section {
                DatePicker("日期", selection: $backfillDate, in: earliestBackfill...todayNight, displayedComponents: .date)
                NavigationLink("填写或修改这一天", value: Route.journalEdit(model.calendar.startOfDay(for: backfillDate)))
            } header: {
                Text("补填或修改")
            }

            Section("影响洞察（按效应量排序）") {
                if model.insights.isEmpty {
                    Text("每组至少需要 5 个样本才会显示。").foregroundStyle(.secondary)
                }
                ForEach(model.insights.prefix(8)) { insight in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.sentence).font(.callout)
                        Text(String(format: "p = %.3f · 做了 %d 次 / 没做 %d 次", insight.pValue, insight.treatedCount, insight.controlCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("最近记录") {
                if model.journal.isEmpty {
                    Text("还没有记录").foregroundStyle(.secondary)
                }
                ForEach(model.journal.suffix(14).reversed(), id: \.night) { entry in
                    NavigationLink(value: Route.journalEdit(entry.night)) {
                        JournalSummaryRow(entry: entry, questions: JournalQuestionStore.questions)
                    }
                }
            }
        }
        .navigationTitle("日志")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.journalQuestions) {
                    Label("题目设置", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    /// 今天的醒来日（本地零点）：问的是昨天，存放在醒来日下。
    private var todayNight: Date {
        model.calendar.startOfDay(for: Date())
    }

    private var earliestBackfill: Date {
        model.calendar.date(byAdding: .day, value: -180, to: todayNight) ?? todayNight
    }
}

private struct TodayJournalRow: View {
    let entry: JournalEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(entry == nil ? "填写今天的日志" : "今天的日志已填写", systemImage: entry == nil ? "square.and.pencil" : "checkmark.circle")
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        guard let entry else { return "约 30 秒，记录昨天的行为与状态。" }
        let energy = entry.energy.map { "精力 \($0)/5" } ?? "未填精力"
        let yes = entry.behaviors.filter(\.value).count
        return "\(energy) · 勾选 \(yes) 项 · 点按修改"
    }
}

private struct JournalSummaryRow: View {
    let entry: JournalEntry
    let questions: [JournalQuestion]

    var body: some View {
        HStack {
            Text(entry.night, format: .dateTime.month().day())
            Spacer()
            Text(summary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.callout)
    }

    private var summary: String {
        var parts = questions.compactMap { question -> String? in
            switch question.kind {
            case .yesNo:
                entry.behaviors[question.id] == true ? question.title : nil
            case let .quantity(unit):
                entry.quantities[question.id].map { "\(question.title) \(Int($0))\(unit)" }
            }
        }
        if let energy = entry.energy { parts.append("精力 \(energy)") }
        if entry.feltUnwell { parts.append("不适") }
        return parts.isEmpty ? "无记录" : parts.joined(separator: "、")
    }
}

/// 某一天的日志编辑页（PRD §6.5）。顶部为 HealthKit 自动填充的只读值，下面是问卷。
struct JournalEditView: View {
    let model: AppModel
    /// 醒来日（本地零点）
    let night: Date

    @State private var draft: JournalEntry
    @State private var questions = JournalQuestionStore.questions
    @State private var saveError: String?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, night: Date) {
        self.model = model
        self.night = night
        _draft = State(initialValue: model.journalEntry(on: night) ?? JournalEntry(night: night))
    }

    var body: some View {
        Form {
            Section {
                Text("问的是 \(dayTitle)。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                autoFillRows
            } header: {
                Text("自动填充（来自健康，只读）")
            } footer: {
                Text("这些值由 HealthKit 记录，不会写入日志。没有记录时显示“无记录”。")
            }

            Section("行为") {
                if questions.isEmpty {
                    Text("没有题目。可以在日志页右上角的“题目设置”中添加。")
                        .foregroundStyle(.secondary)
                }
                ForEach(questions) { question in
                    questionRow(question)
                }
            }

            Section {
                Picker("主观精力", selection: $draft.energy) {
                    Text("未填").tag(Int?.none)
                    ForEach(1...5, id: \.self) { value in
                        Text("\(value) 分").tag(Int?.some(value))
                    }
                }
                Toggle("感觉不适", isOn: $draft.feltUnwell)
            } header: {
                Text("状态")
            } footer: {
                Text("确认不适后，这一晚不计入基线，并参与生病预警（PRD §5.12.1）。饮酒或桑拿当晚只提示，不排除。")
            }

            if let saveError {
                Section {
                    Text(saveError).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(Formatters.wakeDay(night))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(isSaving)
            }
        }
    }

    private var dayTitle: String {
        let yesterday = model.calendar.date(byAdding: .day, value: -1, to: night) ?? night
        return "\(Formatters.wakeDay(yesterday))的情况"
    }

    @ViewBuilder
    private var autoFillRows: some View {
        let fill = model.autoFill(for: night)
        LabeledContent("咖啡因", value: fill.caffeineMilligrams.map { "\(Int($0.rounded())) mg" } ?? "无记录")
        LabeledContent("含酒精饮品", value: fill.alcoholicDrinks.map { "\(Int($0.rounded())) 杯" } ?? "无记录")
        LabeledContent("正念", value: fill.mindfulMinutes.map { "\(Int($0.rounded())) 分钟" } ?? "无记录")
        LabeledContent("日照", value: fill.daylightMinutes.map { "\(Int($0.rounded())) 分钟" } ?? "无记录")
        LabeledContent("情绪", value: fill.meanMoodValence.map { String(format: "%+.2f（%d 条）", $0, fill.moodCount) } ?? "无记录")
    }

    @ViewBuilder
    private func questionRow(_ question: JournalQuestion) -> some View {
        switch question.kind {
        case .yesNo:
            Toggle(question.title, isOn: Binding(
                get: { draft.behaviors[question.id] ?? false },
                set: { draft.behaviors[question.id] = $0 }
            ))
        case let .quantity(unit):
            Stepper(value: Binding(
                get: { draft.quantities[question.id] ?? 0 },
                set: { draft.quantities[question.id] = $0 }
            ), in: 0...50, step: 1) {
                LabeledContent(question.title, value: "\(Int(draft.quantities[question.id] ?? 0)) \(unit)")
            }
        }
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            do {
                try await model.saveJournal(draft)
                dismiss()
            } catch {
                saveError = "保存失败：\(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}

/// 日志题目的增删与排序（PRD §6.5：题目可自定义，题型支持“是/否”和“数量”）。
struct JournalQuestionsView: View {
    @State private var questions = JournalQuestionStore.questions
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                ForEach(questions) { question in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(question.title)
                        Text(kindText(question.kind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onMove { questions.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { questions.remove(atOffsets: $0) }
            } footer: {
                Text("删除题目不会删除以前的记录。标识固定不变，修改标题只影响显示。")
            }

            Section {
                Button("添加题目") { isAdding = true }
                Button("恢复默认题目", role: .destructive) {
                    JournalQuestionStore.resetToDefaults()
                    questions = JournalQuestionStore.questions
                }
            }
        }
        .navigationTitle("日志题目")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onChange(of: questions) {
            JournalQuestionStore.questions = questions
        }
        .sheet(isPresented: $isAdding) {
            AddJournalQuestionSheet { question in
                questions.append(question)
            }
        }
    }

    private func kindText(_ kind: JournalQuestion.Kind) -> String {
        switch kind {
        case .yesNo: "是 / 否"
        case let .quantity(unit): "数量（单位：\(unit)）"
        }
    }
}

private struct AddJournalQuestionSheet: View {
    let onAdd: (JournalQuestion) -> Void
    @State private var title = ""
    @State private var isQuantity = false
    @State private var unit = "次"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("题目，例如：喝了水", text: $title)
                Picker("题型", selection: $isQuantity) {
                    Text("是 / 否").tag(false)
                    Text("数量").tag(true)
                }
                if isQuantity {
                    TextField("单位，例如：杯", text: $unit)
                }
            }
            .navigationTitle("添加题目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let kind: JournalQuestion.Kind = isQuantity
                            ? .quantity(unit: unit.trimmingCharacters(in: .whitespaces).isEmpty ? "次" : unit)
                            : .yesNo
                        // 新题目的标识由时间戳生成，不与默认题目冲突
                        onAdd(JournalQuestion(id: "custom-\(Int(Date().timeIntervalSince1970 * 1000))", title: trimmed, kind: kind))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
