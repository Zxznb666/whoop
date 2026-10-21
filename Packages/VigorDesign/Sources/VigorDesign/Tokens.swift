import SwiftUI
import VigorScoring

/// 设计令牌（PRD §7.2）。颜色使用系统语义色，浅色与深色模式自动适配。
public enum VigorTokens {
    public static let pageMargin: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let cardSpacing: CGFloat = 12
    public static let cardCornerRadius: CGFloat = 20

    public static let recoveryGreen = Color.green
    public static let recoveryYellow = Color.yellow
    public static let recoveryRed = Color.red
    public static let load = Color.blue
    public static let sleep = Color.indigo
    public static let heart = Color.pink
    public static let breathing = Color.cyan
    public static let temperature = Color.purple
    public static let activity = Color.orange

    public static func color(for zone: RecoveryZone) -> Color {
        switch zone {
        case .green: recoveryGreen
        case .yellow: recoveryYellow
        case .red: recoveryRed
        }
    }

    public static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake, .inBed: .orange
        case .rem: Color.cyan.opacity(0.8)
        case .core, .asleepUnspecified: .blue
        case .deep: .indigo
        }
    }

    /// 分区不只靠颜色区分：同时返回文字（色弱友好，PRD §7.2）。
    public static func label(for zone: RecoveryZone) -> String {
        switch zone {
        case .green: "绿"
        case .yellow: "黄"
        case .red: "红"
        }
    }

    public static func label(for stage: SleepStage) -> String {
        switch stage {
        case .awake: "清醒"
        case .inBed: "在床"
        case .core: "核心"
        case .deep: "深睡"
        case .rem: "REM"
        case .asleepUnspecified: "睡着"
        }
    }
}
