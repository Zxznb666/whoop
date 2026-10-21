import Foundation
import Testing
import VigorScoring
@testable import VigorHealth

@Suite("SnapshotCoding")
struct SnapshotCodingTests {
    @Test("v3 编码再解码后结果相等（含骑行功率与导入的骑行）")
    func roundTrip() throws {
        let original = defaultSyntheticSnapshot()
        #expect(!original.importedRides.isEmpty)
        #expect(!original.cyclingPower.isEmpty)
        let data = try SnapshotCoding.encode(original)
        let decoded = try SnapshotCoding.decode(data)
        #expect(decoded == original)
        #expect(decoded.schemaVersion == 3)
    }

    @Test("v2 快照解码后，骑行字段为空数组（不报错）")
    func decodesV2WithoutCyclingFields() throws {
        var snapshot = defaultSyntheticSnapshot()
        snapshot.schemaVersion = 2
        snapshot.cyclingPower = []
        snapshot.cyclingCadence = []
        snapshot.cyclingSpeed = []
        snapshot.ftp = []
        snapshot.importedRides = []
        let data = try SnapshotCoding.encode(snapshot)
        let decoded = try SnapshotCoding.decode(data)
        #expect(decoded.schemaVersion == 2)
        #expect(decoded.importedRides.isEmpty)
        #expect(decoded.cyclingPower.isEmpty)
    }

    @Test("schemaVersion 不在 1 至 3 之间时抛出明确的错误")
    func rejectsUnknownSchemaVersion() throws {
        var snapshot = defaultSyntheticSnapshot()
        snapshot.schemaVersion = 4
        let data = try SnapshotCoding.encode(snapshot)
        #expect(throws: SnapshotCodingError.unsupportedSchemaVersion(4)) {
            try SnapshotCoding.decode(data)
        }
    }

    @Test("v1 快照解码后升级为当前版本：sourceIsWatch 映射为 productType，新增数组为空")
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

        #expect(snapshot.schemaVersion == HealthSnapshot.currentSchemaVersion)
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
