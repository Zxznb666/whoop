import Foundation
import VigorStore

extension Notification.Name {
    /// 导入或刷新完成后发出，界面据此重新读取数据。
    static let vigorDataChanged = Notification.Name("vigor.dataChanged")
}

/// FIT 导入的入口（M6 §4.2）：文件 App 多选、分享面板“用元气打开”、文件夹递归导入。
/// 原始文件保存在 `Application Support/FIT/`，不写回 HealthKit（§4.3）。
@MainActor
enum RideImportCoordinator {
    struct Summary: Equatable {
        var imported = 0
        var duplicates = 0
        var rejected: [String] = []

        var text: String {
            var parts = ["已导入 \(imported) 个"]
            if duplicates > 0 { parts.append("已导入过，跳过 \(duplicates) 个") }
            if !rejected.isEmpty {
                parts.append("无法读取 \(rejected.count) 个：" + rejected.prefix(2).joined(separator: "；"))
            }
            return parts.joined(separator: "，")
        }
    }

    static var rideDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "FIT")
    }

    /// 导入所选的文件或文件夹（文件夹会递归导入其中的 `.fit` 文件）。
    static func importURLs(_ urls: [URL]) async -> Summary {
        var summary = Summary()
        guard let repository = AppBootstrap.shared.environment.repository else {
            summary.rejected.append("存储未就绪")
            return summary
        }
        let files = RideFileStore(directory: rideDirectory)
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            for file in fitFiles(in: url) {
                await ingest(file, repository: repository, files: files, into: &summary)
            }
        }
        if summary.imported > 0 {
            await AppBootstrap.shared.refreshNow()
            NotificationCenter.default.post(name: .vigorDataChanged, object: nil)
        }
        return summary
    }

    private static func fitFiles(in url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "fit" }
    }

    private static func ingest(_ file: URL, repository: ScoreRepository, files: RideFileStore, into summary: inout Summary) async {
        do {
            let data = try Data(contentsOf: file)
            let outcome = try await RideImport.ingest(data: data, fileName: file.lastPathComponent, repository: repository, files: files)
            switch outcome {
            case .imported: summary.imported += 1
            case .duplicate: summary.duplicates += 1
            case .rejected(let reason): summary.rejected.append("\(file.lastPathComponent)（\(reason)）")
            }
        } catch {
            summary.rejected.append("\(file.lastPathComponent)（\(error.localizedDescription)）")
        }
    }
}
