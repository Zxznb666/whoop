import Foundation
import VigorScoring

/// 日志题目的配置（PRD §6.5）：保存在 UserDefaults 中。解码失败或没有题目时回到默认题目。
enum JournalQuestionStore {
    private static let key = "vigor.journal.questions"

    static var questions: [JournalQuestion] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return JournalQuestion.defaults }
            do {
                let questions = try JournalQuestion.decode(data)
                return questions.isEmpty ? JournalQuestion.defaults : questions
            } catch {
                DiagnosticsLog.record("日志题目读取失败，已使用默认题目：\(error)")
                return JournalQuestion.defaults
            }
        }
        set {
            do {
                UserDefaults.standard.set(try JournalQuestion.encode(newValue), forKey: key)
            } catch {
                DiagnosticsLog.record("日志题目保存失败：\(error)")
            }
        }
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
