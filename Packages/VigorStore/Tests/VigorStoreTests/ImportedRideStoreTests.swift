import Foundation
import SwiftData
import Testing
import VigorFIT
import VigorScoring
@testable import VigorStore

@Suite("导入的骑行：存储与去重")
struct ImportedRideStoreTests {
    private func makeRepository() throws -> ScoreRepository {
        ScoreRepository(modelContainer: try VigorStoreFactory.makeContainer(inMemory: true))
    }

    private func ride(_ id: String, minute: Int) -> RideStream {
        RideStream.simple(
            fileID: id,
            start: Date(timeIntervalSince1970: 1_767_000_000 + Double(minute) * 60),
            heartRate: [Int?](repeating: 140, count: 600),
            power: [Int?](repeating: 200, count: 600)
        )
    }

    @Test("同一去重键只保存一次；再次保存返回 false 且不覆盖")
    func duplicateIsSkipped() async throws {
        let repository = try makeRepository()
        let first = ride("a-1", minute: 0)
        #expect(try await repository.saveImportedRide(first, rawFileName: "a.fit") == true)
        #expect(try await repository.saveImportedRide(ride("a-1", minute: 500), rawFileName: "b.fit") == false)
        let stored = try await repository.importedRides()
        #expect(stored == [first])
        #expect(try await repository.hasImportedRide(fileID: "a-1"))
        #expect(try await repository.hasImportedRide(fileID: "other") == false)
    }

    @Test("读取按开始时间升序；删除只影响对应的记录")
    func orderAndDelete() async throws {
        let repository = try makeRepository()
        _ = try await repository.saveImportedRide(ride("late", minute: 300), rawFileName: "late.fit")
        _ = try await repository.saveImportedRide(ride("early", minute: 10), rawFileName: "early.fit")
        #expect(try await repository.importedRides().map(\.fileID) == ["early", "late"])
        try await repository.deleteImportedRide(fileID: "early")
        #expect(try await repository.importedRides().map(\.fileID) == ["late"])
    }

    @Test("原始文件按去重键保存与读取，文件名只含安全字符")
    func rawFileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vigor-fit-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = RideFileStore(directory: directory)
        let bytes = Data([1, 2, 3, 4])
        try files.write(bytes, fileID: "3456789-1767000000")
        #expect(files.read(fileID: "3456789-1767000000") == bytes)
        #expect(RideFileStore.fileName(for: "3456789-1767000000") == "3456789-1767000000.fit")
        #expect(RideFileStore.fileName(for: "a/b:c") == "a_b_c.fit")
        files.delete(fileID: "3456789-1767000000")
        #expect(files.read(fileID: "3456789-1767000000") == nil)
    }

    @Test("无法解析的数据被拒绝，不写入任何记录")
    func garbageIsRejected() async throws {
        let repository = try makeRepository()
        let directory = FileManager.default.temporaryDirectory.appending(path: "vigor-fit-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outcome = try await RideImport.ingest(
            data: Data("not a fit file at all, just text".utf8),
            fileName: "bad.fit",
            repository: repository,
            files: RideFileStore(directory: directory)
        )
        guard case .rejected = outcome else {
            Issue.record("应当被拒绝，实际为 \(outcome)")
            return
        }
        #expect(try await repository.importedRides().isEmpty)
    }

    @Test("骑行汇总保存后可以读回，再次保存覆盖旧值")
    func cyclingSummaryRoundTrip() async throws {
        let repository = try makeRepository()
        #expect(try await repository.cyclingOutput() == nil)
        let first = CyclingOutput(
            rides: [], ftp: FTPEstimate(watts: 250, source: .manual), powerModel: nil,
            trimpPerTSS: 1.5, compensation: [10: 0.2], pmc: [], powerCurve90: [60: 300]
        )
        try await repository.saveCycling(first)
        #expect(try await repository.cyclingOutput() == first)
        var second = first
        second.ftp = FTPEstimate(watts: 260, source: .estimated)
        try await repository.saveCycling(second)
        #expect(try await repository.cyclingOutput() == second)
    }
}
