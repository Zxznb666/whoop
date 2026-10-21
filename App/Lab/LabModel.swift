import Foundation
import Observation
import VigorHealth
import VigorScoring

@MainActor
@Observable
final class LabModel {
    var source: DataSourceKind
    var isLoading = false
    var progress = 0.0
    var progressText = ""
    var reports: [NightFeatures] = []
    var summary: AvailabilitySummary?
    var snapshot: HealthSnapshot?
    var errorMessage: String?
    var exportURL: URL?

    private var importedSnapshot: HealthSnapshot?
    /// 每次加载递增，只有最新一次加载的结果会写入状态。
    private var generation = 0

    init(source: DataSourceKind) {
        self.source = source
    }

    func load(nights: Int = 30) async {
        generation += 1
        let current = generation
        isLoading = true
        errorMessage = nil
        progress = 0
        progressText = "准备中"

        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -nights, to: to) ?? to
        let kind = source
        let imported = importedSnapshot
        let calendar = Calendar.current
        let config = ScoringConfig.default
        let reportProgress: @Sendable (Double, String) -> Void = { [weak self] value, text in
            Task { @MainActor in
                self?.progress = value
                self?.progressText = text
            }
        }

        let outcome: Result<LabResult, any Error>
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let dataSource = try makeDataSource(kind: kind, imported: imported, endingAt: to, calendar: calendar)
                let snapshot = try await dataSource.snapshot(from: from, to: to, progress: reportProgress)
                let reports = NightAnalyzer.analyze(snapshot, calendar: calendar, config: config)
                return LabResult(snapshot: snapshot, reports: reports, summary: AvailabilitySummary.make(reports))
            }.value
            outcome = .success(result)
        } catch {
            outcome = .failure(error)
        }

        guard current == generation else { return }
        isLoading = false
        switch outcome {
        case .success(let result):
            snapshot = result.snapshot
            reports = result.reports
            summary = result.summary
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func switchSource(_ kind: DataSourceKind) async {
        guard kind != source else { return }
        source = kind
        exportURL = nil
        await load()
    }

    func requestAuthorization() async {
        do {
            try await LiveHealthDataSource().requestAuthorization()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await load()
    }

    func importSnapshot(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            importedSnapshot = try await Task.detached {
                try SnapshotCoding.decode(Data(contentsOf: url))
            }.value
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        source = .imported
        exportURL = nil
        await load()
    }

    func prepareExport() {
        do {
            exportURL = try exportSnapshotFile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSnapshotFile() throws -> URL {
        guard let snapshot else { throw LabError.noSnapshot }
        let data = try SnapshotCoding.encode(snapshot)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = "vigor-snapshot-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

private struct LabResult: Sendable {
    let snapshot: HealthSnapshot
    let reports: [NightFeatures]
    let summary: AvailabilitySummary
}

enum LabError: LocalizedError {
    case noImportedSnapshot
    case noSnapshot

    var errorDescription: String? {
        switch self {
        case .noImportedSnapshot:
            "尚未导入快照，请先选择一个 JSON 文件。"
        case .noSnapshot:
            "没有可导出的快照，请先加载数据。"
        }
    }
}

private func makeDataSource(
    kind: DataSourceKind,
    imported: HealthSnapshot?,
    endingAt date: Date,
    calendar: Calendar
) throws -> any HealthDataSource {
    switch kind {
    case .live:
        return LiveHealthDataSource()
    case .synthetic:
        let snapshot = SyntheticSnapshot.make(endingAt: date, calendar: calendar)
        return ReplayHealthDataSource(snapshot: snapshot, kind: .synthetic)
    case .imported:
        guard let imported else { throw LabError.noImportedSnapshot }
        return ReplayHealthDataSource(snapshot: imported, kind: .imported)
    }
}
