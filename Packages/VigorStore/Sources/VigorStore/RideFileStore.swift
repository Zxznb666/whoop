import Foundation

/// 原始 FIT 文件的保存位置：`Application Support/FIT/<fileID>.fit`（M6 §4.3）。
/// FIT 数据无法从 HealthKit 重建，因此备份必须包含这些文件。
public struct RideFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 文件名中的标识符只保留字母、数字与 `-`，避免路径问题。
    public static func fileName(for fileID: String) -> String {
        let safe = fileID.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return safe + ".fit"
    }

    public func write(_ data: Data, fileID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: Self.fileName(for: fileID)), options: .atomic)
    }

    public func read(fileID: String) -> Data? {
        try? Data(contentsOf: directory.appending(path: Self.fileName(for: fileID)))
    }

    public func delete(fileID: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: Self.fileName(for: fileID)))
    }
}
