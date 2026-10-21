import Foundation
import SwiftData
import Testing
@testable import VigorScoring
@testable import VigorStore

@Suite("日志的保存与读取")
struct JournalStoreTests {
    private func makeRepository() throws -> ScoreRepository {
        let container = try ModelContainer(
            for: CycleRecord.self, JournalRecord.self, ConfigRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ScoreRepository(modelContainer: container)
    }

    private let night = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("保存后读回：行为、数量、精力与不适开关都完整保留")
    func roundTrip() async throws {
        let repository = try makeRepository()
        let entry = JournalEntry(
            night: night,
            behaviors: ["alcohol": true, "sauna": false],
            quantities: ["water": 6],
            energy: 4,
            feltUnwell: true
        )
        try await repository.saveJournal(entry)
        let read = try await repository.journal(from: night, to: night)
        #expect(read == [entry])
    }

    @Test("同一天重复保存会覆盖旧记录，而不是新增一条")
    func sameDayOverwrites() async throws {
        let repository = try makeRepository()
        try await repository.saveJournal(JournalEntry(night: night, behaviors: ["alcohol": true], energy: 2))
        try await repository.saveJournal(JournalEntry(night: night, behaviors: ["alcohol": false], energy: 5))
        let read = try await repository.journal(from: night, to: night)
        #expect(read.count == 1)
        #expect(read.first?.behaviors["alcohol"] == false)
        #expect(read.first?.energy == 5)
    }

    @Test("按醒来日查询：不同日期的记录互不影响，并按日期升序返回")
    func rangeQuery() async throws {
        let repository = try makeRepository()
        let nextDay = night.addingTimeInterval(86_400)
        try await repository.saveJournal(JournalEntry(night: nextDay, energy: 1))
        try await repository.saveJournal(JournalEntry(night: night, energy: 3))
        let read = try await repository.journal(from: night, to: nextDay)
        #expect(read.map(\.energy) == [3, 1])
        #expect(try await repository.journal(from: nextDay.addingTimeInterval(1), to: nextDay.addingTimeInterval(86_400)).isEmpty)
    }
}
