import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("SnapshotCoding")
struct SnapshotCodingTests {
    @Test("v2 编码再解码后结果相等")
    func roundTrip() throws {
        let original = defaultSyntheticSnapshot()
        let data = try SnapshotCoding.encode(original)
        let decoded = try SnapshotCoding.decode(data)
        #expect(decoded == original)
        #expect(decoded.schemaVersion == 2)
    }

    @Test("schemaVersion 既不是 1 也不是 2 时抛出明确的错误")
    func rejectsUnknownSchemaVersion() throws {
        var snapshot = defaultSyntheticSnapshot()
        snapshot.schemaVersion = 3
        let data = try SnapshotCoding.encode(snapshot)
        #expect(throws: SnapshotCodingError.unsupportedSchemaVersion(3)) {
            try SnapshotCoding.decode(data)
        }
    }

    @Test("v1 快照解码后升级为 v2：sourceIsWatch 映射为 productType，v2 新增数组为空")
    func decodesLegacyV1() throws {
        let json = """
        {
          "schemaVersion": 1,
          "exportedAt": 1800000000,
          "rangeStart": 1799900000,
          "rangeEnd": 1800000000,
          "profile": { "birthYear": 1990, "sex": "male" },
          "sleep": [
            { "start": 1799990000, "end": 1799993600, "stage": "core", "sourceIsWatch": true },
            { "start": 1799993600, "end": 1799995000, "stage": "awake", "sourceIsWatch": false }
          ],
          "heartRate": [],
          "hrvSDNN": [],
          "restingHeartRate": [],
          "respiratoryRate": [],
          "wristTemperature": [],
          "oxygenSaturation": [],
          "heartbeatSeries": []
        }
        """
        let snapshot = try SnapshotCoding.decode(Data(json.utf8))

        #expect(snapshot.schemaVersion == 2)
        #expect(snapshot.profile.birthYear == 1990)
        #expect(snapshot.profile.heightMeters == nil)
        #expect(snapshot.sleep.count == 2)
        #expect(snapshot.sleep[0].sourceIsWatch)
        #expect(snapshot.sleep[0].productType == "Watch7,1")
        #expect(!snapshot.sleep[1].sourceIsWatch)
        #expect(snapshot.sleep[1].productType == "iPhone15,2")
        #expect(snapshot.inBed.isEmpty)
        #expect(snapshot.workouts.isEmpty)
        #expect(snapshot.mindfulSessions.isEmpty)
        #expect(snapshot.stateOfMind.isEmpty)
    }
}
