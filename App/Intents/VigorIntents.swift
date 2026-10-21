import AppIntents
import Foundation
import VigorStore

/// Siri 与快捷指令（PRD §6.9、施工文档 §5 阶段 8 第 5 条）。读取共享状态文件；没有数据时提示打开元气。
enum CurrentState {
    /// 先读 App Group，再读备用位置（与小组件、手表相同的顺序）。
    static func load() -> SharedState? {
        SharedStateStore.readLatest(groupID: VigorConstants.appGroupID)
    }
}

struct RecoveryIntent: AppIntent {
    static let title: LocalizedStringResource = "今天恢复怎么样"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let state = CurrentState.load(), let recovery = state.recovery else {
            return .result(dialog: "请先打开元气以更新数据。")
        }
        return .result(dialog: "今天的恢复是 \(Int(recovery.rounded()))%，\(zoneText(state.recoveryZone))。")
    }

    private func zoneText(_ zone: String?) -> String {
        switch zone {
        case "green": "状态良好"
        case "yellow": "状态一般"
        case "red": "需要恢复"
        default: "暂无分区"
        }
    }
}

struct StrainIntent: AppIntent {
    static let title: LocalizedStringResource = "今天负荷多少"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let state = CurrentState.load(), let strain = state.strain else {
            return .result(dialog: "请先打开元气以更新数据。")
        }
        var text = "今天的负荷是 \(String(format: "%.1f", strain))"
        if let lower = state.strainTargetLower, let upper = state.strainTargetUpper {
            text += "，目标 \(Int(lower))–\(Int(upper))"
        }
        return .result(dialog: "\(text)。")
    }
}

struct BedtimeIntent: AppIntent {
    static let title: LocalizedStringResource = "今晚几点睡"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let state = CurrentState.load(), let bedtime = state.suggestedBedtime else {
            return .result(dialog: "请先打开元气以更新数据。")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "H点mm分"
        return .result(dialog: "建议今晚 \(formatter.string(from: bedtime)) 入睡。")
    }
}

struct VigorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecoveryIntent(),
            phrases: ["\(.applicationName) 今天恢复怎么样", "在 \(.applicationName) 里看恢复"],
            shortTitle: "今天恢复",
            systemImageName: "heart.text.square"
        )
        AppShortcut(
            intent: StrainIntent(),
            phrases: ["\(.applicationName) 今天负荷多少"],
            shortTitle: "今天负荷",
            systemImageName: "flame"
        )
        AppShortcut(
            intent: BedtimeIntent(),
            phrases: ["\(.applicationName) 今晚几点睡"],
            shortTitle: "建议入睡",
            systemImageName: "bed.double"
        )
    }
}
