import SwiftUI
import UniformTypeIdentifiers
import VigorHealth

struct LabRootView: View {
    @Bindable var model: LabModel
    /// 应用的数据（流水线结果）：基线、明细、参数版本、校准与导出都以它为准
    let app: AppModel
    @State private var isImporting = false

    var body: some View {
        List {
            Section("数据源") {
                Picker("数据源", selection: sourceBinding) {
                    Text("实时").tag(DataSourceKind.live)
                    Text("合成").tag(DataSourceKind.synthetic)
                    Text("导入").tag(DataSourceKind.imported)
                }
                .pickerStyle(.segmented)

                if model.source == .live {
                    Button("授权健康数据") {
                        Task { await model.requestAuthorization() }
                    }
                }
                Button("导入快照") {
                    isImporting = true
                }
                Button("导出快照") {
                    model.prepareExport()
                }
                if let exportURL = model.exportURL {
                    ShareLink(item: exportURL) {
                        Label("分享快照文件", systemImage: "square.and.arrow.up")
                    }
                }
            }

            PipelineLabSections(app: app)

            OverviewSection(summary: model.summary)

            Section("最近 30 晚") {
                if model.isLoading {
                    ProgressView(value: model.progress, total: 1) {
                        Text(model.progressText)
                    }
                } else if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                    Button("重试") {
                        Task { await model.load() }
                    }
                } else if model.reports.isEmpty {
                    Text("暂无夜晚数据")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.reports) { report in
                        NavigationLink {
                            NightDetailView(report: report)
                        } label: {
                            NightRow(report: report)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("实验室")
        .task {
            await model.load()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task { await model.importSnapshot(from: url) }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private var sourceBinding: Binding<DataSourceKind> {
        Binding(
            get: { model.source },
            set: { kind in
                Task { await model.switchSource(kind) }
            }
        )
    }
}
