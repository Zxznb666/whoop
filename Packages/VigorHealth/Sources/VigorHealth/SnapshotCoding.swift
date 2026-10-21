import Foundation
import VigorScoring

public enum SnapshotCodingError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "快照版本 \(version) 不受支持，当前支持版本 1 至 3。"
        }
    }
}

public enum SnapshotCoding {
    public static func encode(_ snapshot: HealthSnapshot) throws -> Data {
        try encoder().encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> HealthSnapshot {
        let decoder = decoder()
        // 先只读版本号，避免新版本的字段结构导致一个含糊的解码错误。
        let header = try decoder.decode(Header.self, from: data)
        switch header.schemaVersion {
        case 1:
            return try decoder.decode(LegacySnapshotV1.self, from: data).upgraded()
        // v2 缺少的骑行字段与导入骑行在解码时按空数组处理（见 HealthSnapshot.init(from:)）
        case 2, HealthSnapshot.currentSchemaVersion:
            return try decoder.decode(HealthSnapshot.self, from: data)
        default:
            throw SnapshotCodingError.unsupportedSchemaVersion(header.schemaVersion)
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }
}

/// schema v1 的结构（M0 导出的快照）。升级时 `sourceIsWatch` 映射为 `productType`，v2 新增数组填空。
struct LegacySnapshotV1: Decodable {
    struct Sleep: Decodable {
        var start: Date
        var end: Date
        var stage: SleepStage
        var sourceIsWatch: Bool
    }

    struct Profile: Decodable {
        var birthYear: Int?
        var sex: BiologicalSex
    }

    var schemaVersion: Int
    var exportedAt: Date
    var rangeStart: Date
    var rangeEnd: Date
    var profile: Profile
    var sleep: [Sleep]
    var heartRate: [HeartRateSample]
    var hrvSDNN: [ValueSample]
    var restingHeartRate: [ValueSample]
    var respiratoryRate: [ValueSample]
    var wristTemperature: [ValueSample]
    var oxygenSaturation: [ValueSample]
    var heartbeatSeries: [HeartbeatSeries]

    func upgraded() -> HealthSnapshot {
        HealthSnapshot(
            schemaVersion: HealthSnapshot.currentSchemaVersion,
            exportedAt: exportedAt,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            profile: UserProfile(birthYear: profile.birthYear, sex: profile.sex),
            sleep: sleep.map {
                SleepStageSample(start: $0.start, end: $0.end, stage: $0.stage, sourceIsWatch: $0.sourceIsWatch)
            },
            heartRate: heartRate,
            hrvSDNN: hrvSDNN,
            restingHeartRate: restingHeartRate,
            respiratoryRate: respiratoryRate,
            wristTemperature: wristTemperature,
            oxygenSaturation: oxygenSaturation,
            heartbeatSeries: heartbeatSeries
        )
    }
}
