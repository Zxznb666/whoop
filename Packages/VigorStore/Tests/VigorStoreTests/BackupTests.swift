import Foundation
import Testing
import VigorScoring
@testable import VigorStore

@Suite("VigorBackup")
struct BackupTests {
    private func payload() -> BackupPayload {
        BackupPayload(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            journal: [JournalEntry(night: Date(timeIntervalSince1970: 1_799_900_000), behaviors: ["alcohol": true], energy: 3)],
            config: ScoringConfig.default,
            sleepOverrides: ["2026-10-01": SleepOverride(start: Date(timeIntervalSince1970: 1_799_990_000))],
            manualExcludedNights: ["2026-09-30"],
            cycles: []
        )
    }

    @Test("加密后再解密，内容完全相等")
    func roundTrip() throws {
        let original = payload()
        let data = try VigorBackup.encrypt(original, password: "测试密码", iterations: 1_000)
        #expect(data.prefix(5) == Data("VIGB1".utf8))
        #expect(try VigorBackup.decrypt(data, password: "测试密码", iterations: 1_000) == original)
    }

    @Test("密码错误时报错，不会返回错误的数据")
    func wrongPassword() throws {
        let data = try VigorBackup.encrypt(payload(), password: "正确", iterations: 1_000)
        #expect(throws: BackupError.wrongPasswordOrCorrupted) {
            try VigorBackup.decrypt(data, password: "错误", iterations: 1_000)
        }
    }

    @Test("文件被篡改时报错")
    func tampered() throws {
        var data = try VigorBackup.encrypt(payload(), password: "正确", iterations: 1_000)
        data[data.count - 3] ^= 0xFF
        #expect(throws: BackupError.wrongPasswordOrCorrupted) {
            try VigorBackup.decrypt(data, password: "正确", iterations: 1_000)
        }
    }

    @Test("不是备份文件时报错")
    func notABackup() {
        #expect(throws: BackupError.notABackup) {
            try VigorBackup.decrypt(Data("hello world, not a backup".utf8), password: "x", iterations: 1_000)
        }
    }

    @Test("PBKDF2-SHA256：相同的密码与盐得到相同的密钥，不同的盐得到不同的密钥")
    func deterministicKeys() throws {
        let salt = Data(repeating: 7, count: 16)
        let a = try VigorBackup.deriveKey(password: "p", salt: salt, iterations: 1_000)
        let b = try VigorBackup.deriveKey(password: "p", salt: salt, iterations: 1_000)
        let c = try VigorBackup.deriveKey(password: "p", salt: Data(repeating: 8, count: 16), iterations: 1_000)
        #expect(a.withUnsafeBytes { Data($0) } == b.withUnsafeBytes { Data($0) })
        #expect(a.withUnsafeBytes { Data($0) } != c.withUnsafeBytes { Data($0) })
    }
}
