import Foundation
import SwiftData
import Testing
@testable import VigorScoring
@testable import VigorStore

@Suite("手动修正与排除的存取（F7）")
struct CorrectionStoreTests {
    private func makeRepository() throws -> ScoreRepository {
        let container = try VigorStoreFactory.makeContainer(inMemory: true)
        return ScoreRepository(modelContainer: container)
    }

    private let night = DateComponents(year: 2026, month: 10, day: 20)
    private let wakeDay = DateComponents(year: 2026, month: 10, day: 21)

    @Test("睡眠时段修正：保存、读回、覆盖、清除")
    func sleepOverrideRoundTrip() async throws {
        let repository = try makeRepository()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try await repository.setSleepOverride(nightKey: night, SleepOverride(start: start))
        var stored = try await repository.sleepOverrides()
        #expect(stored == [night: SleepOverride(start: start)])

        let end = start.addingTimeInterval(7 * 3600)
        try await repository.setSleepOverride(nightKey: night, SleepOverride(start: start, end: end))
        stored = try await repository.sleepOverrides()
        #expect(stored.count == 1)
        #expect(stored[night]?.end == end)

        try await repository.setSleepOverride(nightKey: night, nil)
        #expect(try await repository.sleepOverrides().isEmpty)
    }

    @Test("手动排除：加入、重复加入不增加、移除")
    func manualExclusionRoundTrip() async throws {
        let repository = try makeRepository()
        try await repository.setManualExclusion(wakeDay: wakeDay, excluded: true)
        try await repository.setManualExclusion(wakeDay: wakeDay, excluded: true)
        #expect(try await repository.manualExclusions() == [wakeDay])
        try await repository.setManualExclusion(wakeDay: wakeDay, excluded: false)
        #expect(try await repository.manualExclusions().isEmpty)
    }

    @Test("日期键与存储字符串互相转换")
    func dayKeyParsing() {
        #expect(ScoreRepository.parseDay("2026-10-21") == wakeDay)
        #expect(ScoreRepository.parseDay("2026-10") == nil)
        #expect(ScoreRepository.parseDay("不是日期") == nil)
    }
}

@Suite("备份中的修正键与存储一致")
struct CorrectionBackupKeyTests {
    @Test("日期键往返：dayString 与 parseDay 互逆")
    func dayKeysRoundTrip() {
        let day = DateComponents(year: 2026, month: 3, day: 9)
        #expect(ScoreRepository.parseDay(ScoreRepository.dayString(day)) == day)
        #expect(ScoreRepository.dayString(day) == "2026-03-09")
    }
}
