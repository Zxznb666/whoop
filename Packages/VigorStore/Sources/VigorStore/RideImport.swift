import Foundation
import VigorFIT

/// 导入一个 FIT 文件的结果（M6 §4.2）。
public enum RideImportOutcome: Sendable, Equatable {
    case imported(fileID: String)
    /// 同一个文件已经导入过（去重键相同）
    case duplicate(fileID: String)
    /// 无法解析（头、CRC 或结构错误）或没有采样点
    case rejected(String)
}

public enum RideImport {
    /// 解析、去重、保存。去重按 `fileID`（序列号 + 创建时间）；重复导入直接跳过，不覆盖原始文件。
    public static func ingest(
        data: Data,
        fileName: String,
        repository: ScoreRepository,
        files: RideFileStore,
        now: Date = Date()
    ) async throws -> RideImportOutcome {
        let activity: FITActivity
        do {
            activity = try FITDecoder.decode(data)
        } catch {
            return .rejected(describe(error))
        }
        guard let stream = RideStream.make(from: activity) else {
            return .rejected("文件中没有采样点")
        }
        if try await repository.hasImportedRide(fileID: stream.fileID) {
            return .duplicate(fileID: stream.fileID)
        }
        try files.write(data, fileID: stream.fileID)
        try await repository.saveImportedRide(stream, rawFileName: fileName, now: now)
        return .imported(fileID: stream.fileID)
    }

    static func describe(_ error: Error) -> String {
        switch error as? FITError {
        case .truncated?: "文件不完整"
        case .invalidHeader?: "不是 FIT 文件"
        case .headerCRCMismatch?, .crcMismatch?: "文件校验失败（CRC），文件可能已损坏"
        case .corrupt(let reason)?: "文件结构有误：\(reason)"
        case nil: error.localizedDescription
        }
    }
}
