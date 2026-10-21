import Foundation
import Testing
@testable import VigorStore

@Suite("共享状态的编解码（手表与小组件）")
struct SharedStateCodingTests {
    private func sample(restingHeartRate: Double? = 52, maxHeartRate: Double? = 186) -> SharedState {
        SharedState(
            recovery: 72,
            recoveryZone: "green",
            strain: 9.4,
            strainTargetLower: 8,
            strainTargetUpper: 14,
            sleepScore: 81,
            suggestedBedtime: Date(timeIntervalSince1970: 1_800_000_000),
            stateRaw: "final",
            updatedAt: Date(timeIntervalSince1970: 1_800_003_600),
            appGroupAvailable: false,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate
        )
    }

    @Test("编码再解码后相等，包括手表训练需要的心率参数")
    func roundTrip() throws {
        let original = sample()
        let decoded = try SharedStateStore.decode(try SharedStateStore.encode(original))
        #expect(decoded == original)
    }

    @Test("旧版本的共享状态（没有心率参数）仍可解码，参数为空")
    func legacyPayloadDecodes() throws {
        let legacy = """
        {"recovery": 60, "recoveryZone": "yellow", "strain": 7, "strainTargetLower": null,
         "strainTargetUpper": null, "sleepScore": 70, "suggestedBedtime": null,
         "stateRaw": "preliminary", "updatedAt": 1800000000, "appGroupAvailable": true}
        """
        let decoded = try SharedStateStore.decode(Data(legacy.utf8))
        #expect(decoded.recovery == 60)
        #expect(decoded.restingHeartRate == nil)
        #expect(decoded.maxHeartRate == nil)
        #expect(decoded.appGroupAvailable)
    }

    @Test("约定的键与 App Group 标识固定不变，手表与手机必须一致")
    func contractConstants() {
        #expect(SharedStateStore.watchPayloadKey == "sharedState")
        #expect(VigorConstants.appGroupID == "group.com.example.vigor")
    }
}
