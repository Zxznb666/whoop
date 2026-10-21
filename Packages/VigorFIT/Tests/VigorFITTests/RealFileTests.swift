import Foundation
import Testing
@testable import VigorFIT

/// 可选测试：`Tests/Fixtures/real/` 中有 `.fit` 文件时才运行，否则跳过。
@Suite("真实 FIT 文件（可选）", .enabled(if: realFITFiles().isEmpty == false))
struct RealFileTests {
    @Test("真实文件解析后记录数大于 0，时间单调不减")
    func realFilesParse() throws {
        for url in realFITFiles() {
            let activity = try FITDecoder.decode(Data(contentsOf: url))
            #expect(activity.records.count > 0, "\(url.lastPathComponent)")
            let times = activity.records.map(\.timestamp)
            #expect(zip(times, times.dropFirst()).allSatisfy { $0 <= $1 }, "\(url.lastPathComponent)")
        }
    }
}

private func realFITFiles() -> [URL] {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/real")
    let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return items.filter { $0.pathExtension.lowercased() == "fit" }
}
