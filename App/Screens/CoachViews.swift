import SwiftUI
import VigorCoach
import VigorDesign
import VigorScoring

/// 教练页（PRD §6.10）：今日一句（端侧或模板）；云端 Claude 需要先预览，确认后才发送。
struct CoachView: View {
    let model: AppModel
    @State private var line: String?
    @State private var providerName = ""
    @State private var claudeText: String?
    @State private var claudeError: String?
    @State private var showPreview = false
    @State private var isSending = false

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
                claudeCard
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("隐私").font(.headline)
                        Text("“今日一句”在本机生成：端侧模型不会把数据发出设备，没有端侧模型时使用模板。Claude 是可选的云端模型：需要你在“设置 → 教练设置”中填写 key，并且每次发送前都能看到将要发送的完整内容。发送的只有脱敏的每日汇总，不包括原始心率或心跳序列。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("教练")
        .task { await generate() }
        .sheet(isPresented: $showPreview) {
            PreviewSheet(title: "发送前预览", note: "以下内容将发送到 Anthropic 的 Claude API。确认前请检查。", text: previewText, isSending: isSending) {
                Task { await sendToClaude() }
            }
        }
    }

    @ViewBuilder
    private var claudeCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude 的建议").font(.headline)
                if CoachSettings.apiKey == nil {
                    Text("未填写 key。在“设置 → 教练设置”中填写后，这里可以请求 Claude 的建议。")
                        .font(.callout).foregroundStyle(.secondary)
                } else if let claudeText {
                    Text(claudeText).font(.body)
                    Text("来源：Claude · \(CoachSettings.model)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("预览并发送给 Claude") { showPreview = true }
                        .disabled(summary == nil)
                }
                if let claudeError {
                    Text(claudeError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var summary: DailySummary? {
        guard let today = model.today else { return nil }
        return SummaryBuilder.daily(from: today, journal: model.journal.last, calendar: model.calendar)
    }

    private var previewText: String {
        guard let summary else { return "没有可发送的内容。" }
        return (try? CoachPreview.text(for: summary)) ?? "无法生成预览。"
    }

    private func generate() async {
        guard let summary else {
            line = "还没有数据。"
            providerName = "—"
            return
        }
        if CoachSettings.onDeviceAvailable {
            do {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
                    line = try await OnDeviceCoach().dailyLine(for: summary)
                    providerName = "端侧模型"
                    return
                }
                #endif
            } catch {
                // 端侧失败时使用模板
            }
        }
        line = (try? await TemplateCoach().dailyLine(for: summary)) ?? "暂时无法生成。"
        providerName = "模板"
    }

    private func sendToClaude() async {
        guard let summary, let key = CoachSettings.apiKey else { return }
        isSending = true
        defer { isSending = false }
        do {
            let client = ClaudeCoach(apiKey: key, model: CoachSettings.model, confirmed: true, transport: ClaudeTransport.send)
            claudeText = try await client.dailyLine(for: summary)
            claudeError = nil
            showPreview = false
        } catch {
            claudeError = "发送失败：\(error.localizedDescription)"
        }
    }
}

/// 发送前的预览：显示将要发送的确切 JSON，用户点击后才发出（PRD §9.3）。
struct PreviewSheet: View {
    let title: String
    let note: String
    let text: String
    let isSending: Bool
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(note).font(.callout)
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                    Button(action: onConfirm) {
                        Label(isSending ? "正在发送…" : "确认发送", systemImage: "paperplane")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending)
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

/// 周报 / 月报的文字卡片：默认显示模板版；生成 AI 总结前先预览（PRD §6.7、§9.3）。
struct ReportNarrativeCard: View {
    let report: PeriodReport
    @State private var result: (text: String, source: NarrativeSource)?
    @State private var showPreview = false
    @State private var isWorking = false

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(report.kind == .week ? "周报总结" : "月报总结").font(.headline)
                Text(result?.text ?? PeriodNarrator.template(for: report)).font(.callout)
                Text("来源：\((result?.source ?? .template).label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(isWorking ? "生成中…" : "生成 AI 总结") {
                    if CoachSettings.onDeviceAvailable || CoachSettings.apiKey == nil {
                        Task { await generate(claudeAllowed: false) }
                    } else {
                        showPreview = true
                    }
                }
                .disabled(isWorking)
            }
        }
        .sheet(isPresented: $showPreview) {
            PreviewSheet(
                title: "发送前预览",
                note: "周报数据将发送到 Anthropic 的 Claude API，确认前请检查。",
                text: (try? CoachPreview.reportText(for: report)) ?? "无法生成预览。",
                isSending: isWorking
            ) {
                Task {
                    await generate(claudeAllowed: true)
                    showPreview = false
                }
            }
        }
    }

    private func generate(claudeAllowed: Bool) async {
        isWorking = true
        defer { isWorking = false }
        result = await CoachText.report(report, claudeAllowed: claudeAllowed)
    }
}

/// 教练设置：key（存钥匙串）、模型、测试连接（同样需要确认）。
struct CoachSettingsView: View {
    @State private var keyInput = ""
    @State private var hasKey = CoachSettings.apiKey != nil
    @State private var model = CoachSettings.model
    @State private var message: String?
    @State private var confirmTest = false

    var body: some View {
        Form {
            Section {
                if hasKey {
                    LabeledContent("Key", value: "已保存在钥匙串")
                    Button("删除 key", role: .destructive) {
                        KeychainStore.delete(account: CoachSettings.apiKeyAccount)
                        hasKey = false
                        message = "已删除。"
                    }
                } else {
                    SecureField("粘贴 Claude API key", text: $keyInput)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    Button("保存到钥匙串") {
                        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let status = KeychainStore.write(trimmed, account: CoachSettings.apiKeyAccount)
                        hasKey = status == errSecSuccess
                        keyInput = ""
                        message = hasKey ? "已保存。" : "保存失败（错误码 \(status)）。"
                    }
                }
            } header: {
                Text("Claude API key")
            } footer: {
                Text("key 只保存在本机钥匙串中，不会写入备份文件，也不会出现在日志里。")
            }

            Section("模型") {
                Picker("模型", selection: $model) {
                    ForEach(CoachSettings.models, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: model) { CoachSettings.model = model }
            }

            Section {
                Button("测试连接") { confirmTest = true }
                    .disabled(!hasKey)
            } footer: {
                Text("测试只发送一句不含健康数据的文字：“请只回复：连接成功”。")
            }

            if let message {
                Section {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("教练设置")
        .alert("发送测试请求？", isPresented: $confirmTest) {
            Button("发送") { Task { await testConnection() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将发送：请只回复：连接成功（不含健康数据）。")
        }
    }

    private func testConnection() async {
        guard let key = CoachSettings.apiKey else { return }
        do {
            let request = try ClaudeText.request(system: "只用中文简短回答。", user: "请只回复：连接成功", apiKey: key, model: CoachSettings.model)
            let reply = try ClaudeText.parse(try await ClaudeTransport.send(request))
            message = "连接成功：\(reply)"
        } catch {
            message = "连接失败：\(error.localizedDescription)"
        }
    }
}
