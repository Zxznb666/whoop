import Foundation
import Testing
@testable import VigorReplayCore
import VigorScoring

@Suite("GoldenSnapshot")
struct GoldenSnapshotTests {
    @Test("黄金快照：关键列逐行与文件一致；不一致时给出哪些天变了、变了多少")
    func matchesGoldenFile() throws {
        let url = try #require(Bundle.module.url(forResource: "golden-synthetic-seed42", withExtension: "csv"))
        let expected = try String(contentsOf: url, encoding: .utf8)
        let actual = ReplayExport.golden(GoldenScenario.run(), calendar: GoldenScenario.calendar())
        let report = ReplayExport.goldenDiff(expected: expected, actual: actual)
        #expect(report.isEmpty, Comment(rawValue: "黄金快照变化：\n" + report.joined(separator: "\n")))
    }

    @Test("黄金差异报告：只列出变化的行与列，并给出新旧值")
    func diffReportListsChanges() {
        let expected = "date,recovery,strain\n2026-01-01,50.000000,9.000000\n2026-01-02,60.000000,10.000000\n"
        let actual = "date,recovery,strain\n2026-01-01,50.000000,9.000000\n2026-01-02,62.500000,10.000000\n"
        let report = ReplayExport.goldenDiff(expected: expected, actual: actual)
        #expect(report.count == 1)
        #expect(report.first?.contains("recovery") == true)
        #expect(ReplayExport.goldenDiff(expected: expected, actual: expected).isEmpty)
    }

    @Test("CSV 行数：每个周期一行，加上表头")
    func rowCounts() {
        let output = GoldenScenario.run()
        #expect(ReplayExport.nights(output).split(separator: "\n").count == output.cycles.count + 1)
        #expect(ReplayExport.cycles(output).split(separator: "\n").count == output.cycles.count + 1)
        #expect(ReplayExport.golden(output, calendar: GoldenScenario.calendar()).split(separator: "\n").count == output.cycles.count + 1)
    }

    @Test("命令行参数：快照路径、输出目录与 --synthetic")
    func parsesArguments() throws {
        let options = try ReplayOptions.parse(["snap.json", "--out", "x", "--now", "2026-10-01T00:00:00+08:00"])
        #expect(options.snapshotPath == "snap.json")
        #expect(options.outputDirectory == "x")
        #expect(options.now != nil)
        #expect(try ReplayOptions.parse(["--synthetic", "--update-golden"]).updateGolden)
        #expect(throws: ReplayError.self) { try ReplayOptions.parse([]) }
    }
}
