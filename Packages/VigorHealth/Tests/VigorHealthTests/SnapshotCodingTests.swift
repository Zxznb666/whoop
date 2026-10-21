import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("SnapshotCoding")
struct SnapshotCodingTests {
    @Test("编码再解码后结果相等")
    func roundTrip() throws {
        let original = defaultSyntheticSnapshot()
        let data = try SnapshotCoding.encode(original)
        let decoded = try SnapshotCoding.decode(data)
        #expect(decoded == original)
    }

    @Test("schemaVersion 不为 1 时抛出明确的错误")
    func rejectsUnknownSchemaVersion() throws {
        var snapshot = defaultSyntheticSnapshot()
        snapshot.schemaVersion = 2
        let data = try SnapshotCoding.encode(snapshot)
        #expect(throws: SnapshotCodingError.unsupportedSchemaVersion(2)) {
            try SnapshotCoding.decode(data)
        }
    }
}
