import Foundation
import VigorHealth
import VigorScoring

/// 命令行参数（施工文档 §5 阶段 5 第 3 条）：
/// `vigor-replay <snapshot.json> [--out dir] [--config config.json] [--now ISO8601]`
/// `vigor-replay --synthetic [--out dir] [--update-golden] [--golden path]`
public struct ReplayOptions: Sendable, Equatable {
    public var snapshotPath: String?
    public var outputDirectory: String
    public var configPath: String?
    public var now: Date?
    public var synthetic: Bool
    public var updateGolden: Bool
    public var goldenPath: String

    public static func parse(_ arguments: [String]) throws -> ReplayOptions {
        var options = ReplayOptions(
            snapshotPath: nil,
            outputDirectory: "replay-out",
            configPath: nil,
            now: nil,
            synthetic: false,
            updateGolden: false,
            goldenPath: "Resources/golden-synthetic-seed42.csv"
        )
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--out":
                options.outputDirectory = try value(after: argument, &iterator)
            case "--config":
                options.configPath = try value(after: argument, &iterator)
            case "--now":
                let text = try value(after: argument, &iterator)
                guard let date = ISO8601DateFormatter().date(from: text) else {
                    throw ReplayError.badArgument("--now 需要 ISO8601 格式的时间：\(text)")
                }
                options.now = date
            case "--synthetic":
                options.synthetic = true
            case "--update-golden":
                options.updateGolden = true
            case "--golden":
                options.goldenPath = try value(after: argument, &iterator)
            default:
                if argument.hasPrefix("--") {
                    throw ReplayError.badArgument("未知参数：\(argument)")
                }
                options.snapshotPath = argument
            }
        }
        if !options.synthetic, options.snapshotPath == nil {
            throw ReplayError.badArgument("需要一个快照文件，或使用 --synthetic")
        }
        return options
    }

    private static func value(after flag: String, _ iterator: inout IndexingIterator<[String]>) throws -> String {
        guard let value = iterator.next() else {
            throw ReplayError.badArgument("\(flag) 需要一个值")
        }
        return value
    }
}

public enum ReplayError: LocalizedError {
    case badArgument(String)

    public var errorDescription: String? {
        switch self {
        case .badArgument(let message): message
        }
    }
}

/// 合成场景的固定参数（黄金快照：seed = 42，endingAt = 2026-10-01T00:00+08:00，now = endingAt）。
public enum GoldenScenario {
    public static let seed: UInt64 = 42
    public static let nights = 120

    public static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    public static func endingAt() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        components.hour = 0
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return calendar().date(from: components)!
    }

    public static func run() -> PipelineOutput {
        let scenario = SyntheticScenario.make(nights: nights, seed: seed, endingAt: endingAt(), calendar: calendar())
        return ScoringPipeline.run(PipelineInput(
            snapshot: scenario.snapshot,
            journal: scenario.journal,
            now: endingAt(),
            calendar: calendar()
        ))
    }
}
