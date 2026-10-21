import SwiftUI
import VigorScoring

/// 小组件、手表与复杂功能共用的文案与颜色（PRD §6.9）。
public enum GlanceFormat {
    /// 共享状态读不到时的提示：App Group 不可用（例如重签名后）或从未同步。
    public static let openToUpdate = "打开元气以更新"

    public static func recovery(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    public static func sleep(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "—"
    }

    public static func strain(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }

    public static func bedtime(_ date: Date?) -> String {
        date.map { $0.formatted(.dateTime.hour().minute()) } ?? "—"
    }

    /// 恢复分区的颜色；分区缺失时使用中性色。
    public static func tint(zoneRaw: String?) -> Color {
        guard let zoneRaw, let zone = RecoveryZone(rawValue: zoneRaw) else { return .secondary }
        return VigorTokens.color(for: zone)
    }

    /// 负荷的目标区间文字，例如 “目标 8–14”；没有目标时为空。
    public static func strainTarget(lower: Double?, upper: Double?) -> String? {
        guard let lower, let upper else { return nil }
        return "目标 \(Int(lower.rounded()))–\(Int(upper.rounded()))"
    }
}

/// 小尺寸与锁屏圆形仪表共用的恢复环（0–100）。
public struct RecoveryRing: View {
    public var value: Double?
    public var zoneRaw: String?

    public init(value: Double?, zoneRaw: String?) {
        self.value = value
        self.zoneRaw = zoneRaw
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(GlanceFormat.tint(zoneRaw: zoneRaw).opacity(0.22), lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(max((value ?? 0) / 100, 0), 1))
                .stroke(GlanceFormat.tint(zoneRaw: zoneRaw), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(GlanceFormat.recovery(value))
                .font(.system(.body, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
        }
        .padding(4)
    }
}
