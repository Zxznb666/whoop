import Foundation
import Testing
@testable import VigorScoring

@Suite("SleepSessionBuilder")
struct SleepSessionBuilderTests {
    private func sample(_ start: Date, _ end: Date, _ stage: SleepStage, watch: Bool = true) -> SleepStageSample {
        SleepStageSample(
            start: start,
            end: end,
            stage: stage,
            sourceBundleID: watch ? "com.apple.health.watch" : "com.example.other",
            sourceName: watch ? "Apple Watch" : "Other",
            productType: watch ? "Watch7,1" : nil
        )
    }

    private func build(_ samples: [SleepStageSample], inBed: [SleepStageSample] = []) -> [SleepSession] {
        SleepSessionBuilder.sessions(stages: samples, inBed: inBed, calendar: shanghaiCalendar())
    }

    @Test("来源优先级：同一时段手表和其他 App 都有分期时，只采用手表的")
    func sourcePriority() throws {
        let watchCore = sample(shanghaiDate(2026, 10, 21, 23), shanghaiDate(2026, 10, 22, 7), .core)
        let otherCore = sample(shanghaiDate(2026, 10, 22, 1), shanghaiDate(2026, 10, 22, 2), .core, watch: false)
        let sessions = build([watchCore, otherCore])
        let session = try #require(sessions.first)
        #expect(sessions.count == 1)
        #expect(session.stages.allSatisfy { $0.sourceIsWatch })
        #expect(session.asleepDuration == 8 * 3600)
    }

    @Test("合并：间隔 40 分钟 → 合并")
    func mergeFortyMinutes() {
        let a = sample(shanghaiDate(2026, 10, 21, 23), shanghaiDate(2026, 10, 22, 1), .core)
        let b = sample(shanghaiDate(2026, 10, 22, 1, 40), shanghaiDate(2026, 10, 22, 4), .core)
        let sessions = build([a, b])
        #expect(sessions.count == 1)
        #expect(sessions[0].longAwakeGaps.isEmpty)
    }

    @Test("合并：凌晨 02:00 间隔 90 分钟 → 合并并标记长清醒")
    func mergeNinetyMinutesAtNight() {
        let a = sample(shanghaiDate(2026, 10, 22, 0), shanghaiDate(2026, 10, 22, 2), .core)
        let b = sample(shanghaiDate(2026, 10, 22, 3, 30), shanghaiDate(2026, 10, 22, 6), .core)
        let sessions = build([a, b])
        #expect(sessions.count == 1)
        #expect(sessions[0].longAwakeGaps.count == 1)
        #expect(sessions[0].longAwakeGaps[0].duration == 90 * 60)
    }

    @Test("合并：14:00 间隔 90 分钟 → 拆分")
    func splitNinetyMinutesInDaytime() {
        let a = sample(shanghaiDate(2026, 10, 22, 12), shanghaiDate(2026, 10, 22, 14), .core)
        let b = sample(shanghaiDate(2026, 10, 22, 15, 30), shanghaiDate(2026, 10, 22, 17, 30), .core)
        #expect(build([a, b]).count == 2)
    }

    @Test("主睡眠：中点在 16:00 的 4 小时会话不能成为主睡眠")
    func afternoonSessionIsNotMain() throws {
        let afternoon = sample(shanghaiDate(2026, 10, 21, 14), shanghaiDate(2026, 10, 21, 18), .core)
        let session = try #require(build([afternoon]).first)
        #expect(session.asleepDuration == 4 * 3600)
        #expect(!session.isMain)
    }

    @Test("主睡眠：夜班场景（只有一个白天 5 小时的会话）→ 它成为主睡眠")
    func nightShiftSessionIsMain() throws {
        let shift = sample(shanghaiDate(2026, 10, 21, 8), shanghaiDate(2026, 10, 21, 13), .core)
        let session = try #require(build([shift]).first)
        #expect(session.isMain)
    }

    @Test("主睡眠：夜间主睡眠与下午小睡同时存在时，只有夜间那段为主睡眠")
    func mainAndNap() throws {
        let night = sample(shanghaiDate(2026, 10, 21, 23), shanghaiDate(2026, 10, 22, 7), .core)
        let nap = sample(shanghaiDate(2026, 10, 22, 14), shanghaiDate(2026, 10, 22, 14, 25), .core)
        let sessions = build([night, nap])
        #expect(sessions.filter(\.isMain).count == 1)
        #expect(sessions.first { $0.start == shanghaiDate(2026, 10, 22, 14) }?.kind == .nap)
    }

    @Test("短于 15 分钟的会话被忽略")
    func shortSessionIgnored() {
        let blip = sample(shanghaiDate(2026, 10, 22, 14), shanghaiDate(2026, 10, 22, 14, 10), .core)
        #expect(build([blip]).isEmpty)
    }

    @Test("在床样本：上床时刻取与会话重叠的 inBed 中最早的开始时间")
    func bedtimeFromInBed() throws {
        let core = sample(shanghaiDate(2026, 10, 21, 23, 20), shanghaiDate(2026, 10, 22, 7), .core)
        let inBed = SleepStageSample(
            start: shanghaiDate(2026, 10, 21, 22, 55),
            end: shanghaiDate(2026, 10, 22, 7, 5),
            stage: .inBed,
            productType: "iPhone15,2"
        )
        let session = try #require(build([core], inBed: [inBed]).first)
        #expect(session.bedtime == shanghaiDate(2026, 10, 21, 22, 55))
    }

    @Test("觉醒次数：清醒段 [1 分钟, 3 分钟, 2 分钟] → 2 次")
    func awakeningsCountAtLeastTwoMinutes() throws {
        let samples = [
            sample(shanghaiDate(2026, 10, 21, 23), shanghaiDate(2026, 10, 21, 23, 30), .core),
            sample(shanghaiDate(2026, 10, 21, 23, 30), shanghaiDate(2026, 10, 21, 23, 31), .awake),
            sample(shanghaiDate(2026, 10, 21, 23, 31), shanghaiDate(2026, 10, 21, 23, 40), .core),
            sample(shanghaiDate(2026, 10, 21, 23, 40), shanghaiDate(2026, 10, 21, 23, 43), .awake),
            sample(shanghaiDate(2026, 10, 21, 23, 43), shanghaiDate(2026, 10, 21, 23, 50), .core),
            sample(shanghaiDate(2026, 10, 21, 23, 50), shanghaiDate(2026, 10, 21, 23, 52), .awake),
            sample(shanghaiDate(2026, 10, 21, 23, 52), shanghaiDate(2026, 10, 22, 0, 30), .core),
        ]
        let session = try #require(build(samples).first)
        #expect(SleepEvents.awakeningCount(in: session) == 2)
    }

    @Test("睡眠图显示：不足 1 分钟的分期并入相邻较长的片段，且不改变总时长")
    func hypnogramDisplayMerge() {
        let start = shanghaiDate(2026, 10, 21, 23)
        let samples = [
            sample(start, start.addingTimeInterval(1800), .core),
            sample(start.addingTimeInterval(1800), start.addingTimeInterval(1830), .deep),
            sample(start.addingTimeInterval(1830), start.addingTimeInterval(3600), .rem),
        ]
        let display = SleepEvents.hypnogram(samples)
        #expect(display.count == 2)
        #expect(display.allSatisfy { $0.end.timeIntervalSince($0.start) >= 60 })
        let total = display.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        #expect(total == 3600)
    }

    @Test("修正覆盖层：只替换主睡眠的起止，原始分期不变")
    func overrideAdjustsMainSession() throws {
        let night = sample(shanghaiDate(2026, 10, 21, 23), shanghaiDate(2026, 10, 22, 7), .core)
        let key = DateComponents(year: 2026, month: 10, day: 21)
        let sessions = SleepSessionBuilder.sessions(
            stages: [night],
            calendar: shanghaiCalendar(),
            overrides: [key: SleepOverride(start: shanghaiDate(2026, 10, 21, 23, 30))]
        )
        let session = try #require(sessions.first)
        #expect(session.start == shanghaiDate(2026, 10, 21, 23, 30))
        #expect(session.asleepDuration == 7.5 * 3600)
        #expect(session.stages.count == 1)
    }
}
