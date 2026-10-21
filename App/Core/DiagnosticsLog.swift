import Foundation

/// 诊断日志：授权、后台注册与同步的错误原文都保存在这里，供诊断页显示（施工文档 §5 阶段 5 第 2 条）。
enum DiagnosticsLog {
    private static let key = "vigor.diagnostics.log"
    private static let limit = 100

    static func record(_ message: String, now: Date = Date()) {
        let formatter = ISO8601DateFormatter()
        var entries = UserDefaults.standard.stringArray(forKey: key) ?? []
        entries.append("\(formatter.string(from: now)) \(message)")
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        UserDefaults.standard.set(entries, forKey: key)
    }

    static var entries: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
