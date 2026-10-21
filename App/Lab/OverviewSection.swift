import SwiftUI
import VigorScoring

/// M0 的核心指标：判断方案是否可行。字号要大，信息要清楚。
struct OverviewSection: View {
    let summary: AvailabilitySummary?

    var body: some View {
        Section {
            if let summary {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                    GridRow {
                        metric("夜数", value: "\(summary.nights)")
                        metric(
                            "可算 RMSSD",
                            value: "\(summary.nightsWithRMSSD)",
                            detail: summary.nights > 0
                                ? "占 \(Formatters.percent(Double(summary.nightsWithRMSSD) / Double(summary.nights)))"
                                : nil
                        )
                    }
                    GridRow {
                        metric(
                            "平均每晚有效片段",
                            value: Formatters.number(summary.meanValidSegmentsPerNight, digits: 1)
                        )
                        metric("RMSSD 中位数", value: Formatters.rmssd(summary.medianRMSSD))
                    }
                }
                .padding(.vertical, 4)

            } else {
                Text("暂无数据")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("可用性总览")
        }
    }

    private func metric(_ title: String, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
