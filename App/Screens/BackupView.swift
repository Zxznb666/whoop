import SwiftUI
import UniformTypeIdentifiers
import VigorScoring
import VigorStore

/// `.vigorbackup` 文件（已加密的字节）。
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// 加密备份的导出与导入（PRD §9.4）。导入会覆盖同一天的日志与周期，然后全量重算。
struct BackupView: View {
    let model: AppModel
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var exportDocument: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImport: Data?
    @State private var importPassword = ""
    @State private var askImportPassword = false
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                SecureField("密码（至少 8 位）", text: $password)
                SecureField("再输入一次", text: $confirmPassword)
                Button("导出加密备份") { startExport() }
                    .disabled(isWorking)
            } header: {
                Text("导出")
            } footer: {
                Text("备份包含日志、评分配置、周期结果与手动修正，不包含原始健康数据（可从“健康”重新导入）。忘记密码无法恢复备份。")
            }

            Section {
                Button("导入备份…") { isImporting = true }
                    .disabled(isWorking)
            } header: {
                Text("导入")
            } footer: {
                Text("导入会覆盖同一天的日志与周期，然后全量重算。")
            }

            if let message {
                Section {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("备份与恢复")
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .data,
            defaultFilename: "vigor-\(Self.stamp()).vigorbackup"
        ) { result in
            switch result {
            case .success: message = "备份已保存。"
            case .failure(let error): message = "保存失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                readImport(url)
            case .failure(let error):
                message = "无法打开文件：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $askImportPassword) {
            importPasswordSheet
        }
    }

    private var importPasswordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("备份密码", text: $importPassword)
                } footer: {
                    Text("密码错误或文件损坏时，不会修改任何数据。")
                }
                Section {
                    Button("导入并重算") {
                        askImportPassword = false
                        Task { await runImport() }
                    }
                    .disabled(importPassword.isEmpty || isWorking)
                }
            }
            .navigationTitle("输入备份密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        askImportPassword = false
                        pendingImport = nil
                        importPassword = ""
                    }
                }
            }
        }
    }

    private func startExport() {
        guard password.count >= 8, password == confirmPassword else {
            message = "密码至少 8 位，且两次输入需要一致。"
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let payload = try await buildPayload()
                let secret = password
                let data = try await Task.detached(priority: .userInitiated) {
                    try VigorBackup.encrypt(payload, password: secret)
                }.value
                exportDocument = BackupDocument(data: data)
                password = ""
                confirmPassword = ""
                isExporting = true
            } catch {
                message = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private func readImport(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            pendingImport = try Data(contentsOf: url)
            askImportPassword = true
        } catch {
            message = "无法读取文件：\(error.localizedDescription)"
        }
    }

    private func runImport() async {
        guard let data = pendingImport else { return }
        isWorking = true
        defer {
            isWorking = false
            pendingImport = nil
            importPassword = ""
        }
        do {
            let secret = importPassword
            let payload = try await Task.detached(priority: .userInitiated) {
                try VigorBackup.decrypt(data, password: secret)
            }.value
            try await restore(payload)
            message = "已导入 \(payload.cycles.count) 个周期、\(payload.journal.count) 天日志，正在全量重算。"
            await AppBootstrap.shared.refreshNow(mode: .full)
            await model.load(source: model.source)
            message = "导入完成，已全量重算。"
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    private func buildPayload() async throws -> BackupPayload {
        guard let repository = AppBootstrap.shared.environment.repository else {
            throw JournalSaveError.storeUnavailable
        }
        let now = Date()
        return BackupPayload(
            exportedAt: now,
            journal: try await repository.journal(from: .distantPast, to: now),
            config: try await repository.currentConfig() ?? .default,
            sleepOverrides: [:],
            manualExcludedNights: [],
            cycles: try await repository.cycles(from: .distantPast, to: now)
        )
    }

    private func restore(_ payload: BackupPayload) async throws {
        guard let repository = AppBootstrap.shared.environment.repository else {
            throw JournalSaveError.storeUnavailable
        }
        for entry in payload.journal {
            try await repository.saveJournal(entry)
        }
        try await repository.saveConfig(payload.config)
        try await repository.upsert(payload.cycles, force: true)
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }
}
