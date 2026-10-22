import Foundation
import Testing
import VigorFIT
@testable import VigorScoring

@Suite("骑行心率区间与旧数据解码（M6 补完 C3）")
struct CyclingZoneTests {
    let origin = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 GMT，整分钟
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()

    /// 一次只有心率的 FIT 骑行（每秒一个心率值），静息 50、最大 190。
    func zoneOutput(_ heartRate: [Int?]) throws -> RideResult {
        let ride = RideStream.simple(fileID: "zones", start: origin, heartRate: heartRate, power: [])
        let grid = MinuteGrid.build(origin: origin, end: origin.addingTimeInterval(Double(heartRate.count)), heartRate: [], activeEnergy: [], steps: [])
        let input = CyclingInput(
            importedRides: [ride],
            restingHeartRate: 50, maxHeartRate: 190, sex: .male,
            now: origin.addingTimeInterval(86_400), calendar: calendar
        )
        let output = CyclingAnalysis.run(input, grid: grid)
        return try #require(output.rides.first)
    }

    @Test("HRR 分区：120 → Z1、169 → Z4、80 → 不计入")
    func heartRateReserveZones() throws {
        let heartRate = Array(repeating: 120, count: 60) + Array(repeating: 169, count: 60) + Array(repeating: 80, count: 60)
        let result = try zoneOutput(heartRate.map { Optional($0) })
        #expect(result.heartRateZoneSeconds == [60, 0, 0, 60, 0])
    }

    @Test("没有心率的骑行，心率区间为 nil")
    func noHeartRateNoZones() throws {
        let result = try zoneOutput(Array(repeating: nil, count: 120))
        #expect(result.heartRateZoneSeconds == nil)
    }

    @Test("旧数据（没有心率区间字段）解码为 nil，新数据往返相等")
    func oldRideJSONDecodesWithoutZones() throws {
        let ride = RideResult(
            id: "old", start: origin, end: origin.addingTimeInterval(600), sourceLabels: [], memberCount: 1,
            movingSeconds: 600, heartRateOrigin: nil, powerSource: .none, powerCoverage: nil, normalizedPower: nil,
            intensityFactor: nil, tss: nil, mechanicalWorkKJ: nil, wattsPerKilogram: nil, averageHeartRate: 130,
            efficiencyFactor: nil, aerobicDecoupling: nil, zoneSeconds: nil, powerCurve: [:],
            compensatedMinutes: 0, loadMayBeUnderestimated: false, measuredTRIMP: 0
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(ride)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("heartRateZoneSeconds"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(RideResult.self, from: data)
        #expect(decoded.heartRateZoneSeconds == nil)
        #expect(decoded == ride)

        var withZones = ride
        withZones.heartRateZoneSeconds = [1, 2, 3, 4, 5]
        let roundTrip = try decoder.decode(RideResult.self, from: encoder.encode(withZones))
        #expect(roundTrip.heartRateZoneSeconds == [1, 2, 3, 4, 5])
    }
}
