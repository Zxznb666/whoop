import Foundation
import VigorScoring

public enum SnapshotCodingError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "快照版本 \(version) 不受支持，当前只支持版本 1。"
        }
    }
}

public enum SnapshotCoding {
    private static let supportedSchemaVersion = 1

    public static func encode(_ snapshot: HealthSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> HealthSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        // 先只读版本号，避免新版本的字段结构导致一个含糊的解码错误。
        let header = try decoder.decode(Header.self, from: data)
        guard header.schemaVersion == supportedSchemaVersion else {
            throw SnapshotCodingError.unsupportedSchemaVersion(header.schemaVersion)
        }
        return try decoder.decode(HealthSnapshot.self, from: data)
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }
}
