import Charts
import SwiftUI
import VigorDesign
import VigorScoring

/// 心肺适能详情（PRD §5.12.2）：VO2max 的 90 天趋势与 1 分钟心率恢复的变化。
struct CardioFitnessView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                vo2Card
                recoveryCard
                SectionCard {
                    Text("心肺适能的趋势只描述变化方向，不做医学判断。同配速心率的比较尚未实现（见 DECISIONS D-090）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("心肺适能")
    }

    private var windowStart: Date {
        let end = model.lastUpdated ?? Date()
        return model.calendar.date(byAdding: .day, value: -90, to: end) ?? end
    }

    private var vo2Points: [ValueSample] {
        (model.snapshot?.vo2Max ?? [])
            .filter { $0.start >= windowStart }
            .sorted { $0.start < $1.start }
    }

    private var recoveryValues: [Double] {
        (model.snapshot?.heartRateRecovery ?? [])
            .filter { $0.start >= windowStart }
            .sorted { $0.start < $1.start }
            .map(\.value)
    }

    @ViewBuilder
    private var vo2Card: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("VO₂max（近 90 天）").font(.headline)
                if let latest = vo2Points.last {
                    Text(String(format: "%.1f ml/kg/min", latest.value))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    if let slope = CardioFitness.slopePerDay(vo2Points.map { (date: $0.start, value: $0.value) }) {
                        Text("90 天趋势约 \(Formatters.signed(slope * 90, digits: 1, unit: " ml/kg/min"))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Chart(vo2Points, id: \.start) { point in
                        LineMark(x: .value("日期", point.start), y: .value("VO₂max", point.value))
                            .foregroundStyle(VigorTokens.heart)
                        PointMark(x: .value("日期", point.start), y: .value("VO₂max", point.value))
                            .foregroundStyle(VigorTokens.heart)
                            .symbolSize(10)
                    }
                    .frame(height: 160)
                } else {
                    Text("没有 VO₂max 记录。佩戴 Apple Watch 并保持有氧运动后，这里会出现数值。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var recoveryCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("1 分钟心率恢复（近 90 天）").font(.headline)
                if let change = CardioFitness.recoveryChange(recoveryValues) {
                    Text("后半段比前半段的中位数 \(Formatters.signed(change, digits: 0, unit: " bpm"))")
                        .font(.callout)
                    Text("\(recoveryValues.count) 次测量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("测量次数不足，至少需要 4 次。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
