import CommonCrypto
import CryptoKit
import Foundation
import VigorScoring

/// 备份内容（PRD §9.4）：日志、配置、覆盖项与派生数据。原始健康数据不在备份中（可从 HealthKit 重建）。
public struct BackupPayload: Codable, Sendable, Equatable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var journal: [JournalEntry]
    public var config: ScoringConfig
    /// 键为醒来日，格式 yyyy-MM-dd
    public var sleepOverrides: [String: SleepOverride]
    public var manualExcludedNights: [String]
    public var cycles: [CycleResult]

    public init(
        formatVersion: Int = 1,
        exportedAt: Date,
        journal: [JournalEntry],
        config: ScoringConfig,
        sleepOverrides: [String: SleepOverride],
        manualExcludedNights: [String],
        cycles: [CycleResult]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.journal = journal
        self.config = config
        self.sleepOverrides = sleepOverrides
        self.manualExcludedNights = manualExcludedNights
        self.cycles = cycles
    }
}

public enum BackupError: LocalizedError, Equatable {
    case notABackup
    case wrongPasswordOrCorrupted
    case keyDerivationFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .notABackup: "这不是元气的备份文件。"
        case .wrongPasswordOrCorrupted: "密码错误，或备份文件已损坏。"
        case .keyDerivationFailed(let status): "密钥派生失败（\(status)）。"
        }
    }
}

/// 加密备份（PRD §9.4）：`.vigorbackup` = 魔数 | 16 字节随机盐 | AES-GCM 合并数据（nonce ‖ 密文 ‖ 标签）。
/// 密钥由用户密码经 PBKDF2-SHA256 派生，迭代 200,000 次。
public enum VigorBackup {
    static let magic = Data("VIGB1".utf8)
    public static let iterations = 200_000
    static let saltLength = 16
    static let keyLength = 32

    public static func encrypt(_ payload: BackupPayload, password: String, iterations: Int = VigorBackup.iterations) throws -> Data {
        let salt = Data((0..<saltLength).map { _ in UInt8.random(in: 0...255) })
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let plaintext = try encoder().encode(payload)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw BackupError.notABackup }
        return magic + salt + combined
    }

    public static func decrypt(_ data: Data, password: String, iterations: Int = VigorBackup.iterations) throws -> BackupPayload {
        guard data.count > magic.count + saltLength, data.prefix(magic.count) == magic else {
            throw BackupError.notABackup
        }
        let salt = data.subdata(in: magic.count..<(magic.count + saltLength))
        let combined = data.suffix(from: magic.count + saltLength)
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(box, using: key)
            return try decoder().decode(BackupPayload.self, from: plaintext)
        } catch is CryptoKitError {
            throw BackupError.wrongPasswordOrCorrupted
        }
    }

    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: keyLength)
        let passwordBytes = Array(password.utf8)
        let status = salt.withUnsafeBytes { saltBuffer -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes, passwordBytes.count,
                saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, keyLength
            )
        }
        guard status == kCCSuccess else { throw BackupError.keyDerivationFailed(status) }
        return SymmetricKey(data: Data(derived))
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
}
