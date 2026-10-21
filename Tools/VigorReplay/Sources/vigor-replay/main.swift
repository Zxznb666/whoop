import Foundation
import VigorHealth
import VigorReplayCore
import VigorScoring

func run() throws {
    let options = try ReplayOptions.parse(Array(CommandLine.arguments.dropFirst()))
    let calendar = GoldenScenario.calendar()

    let output: PipelineOutput
    if options.synthetic {
        output = GoldenScenario.run()
        if options.updateGolden {
            try ReplayExport.golden(output, calendar: calendar)
                .write(toFile: options.goldenPath, atomically: true, encoding: .utf8)
            print("已更新黄金快照：\(options.goldenPath)")
        }
    } else {
        let data = try Data(contentsOf: URL(fileURLWithPath: options.snapshotPath!))
        let snapshot = try SnapshotCoding.decode(data)
        var config = ScoringConfig.default
        if let path = options.configPath {
            config = try JSONDecoder().decode(ScoringConfig.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        }
        output = ScoringPipeline.run(PipelineInput(
            snapshot: snapshot,
            config: config,
            now: options.now ?? snapshot.rangeEnd,
            calendar: calendar
        ))
    }

    let directory = URL(fileURLWithPath: options.outputDirectory, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try ReplayExport.nights(output).write(to: directory.appendingPathComponent("nights.csv"), atomically: true, encoding: .utf8)
    try ReplayExport.cycles(output).write(to: directory.appendingPathComponent("cycles.csv"), atomically: true, encoding: .utf8)
    try ReplayExport.baselines(output).write(to: directory.appendingPathComponent("baselines.csv"), atomically: true, encoding: .utf8)
    print("周期 \(output.cycles.count) 个，已写入 \(directory.path)")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("vigor-replay: \(error.localizedDescription)\n".utf8))
    exit(1)
}
