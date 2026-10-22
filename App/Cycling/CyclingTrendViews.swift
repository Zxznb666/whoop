import Charts
import SwiftUI
import VigorDesign
import VigorScoring

/// 浏览页的骑行趋势：FTP 历史与有氧效率 EF（M6 补完 C4）。
/// 与 CardioFitnessView 共用的文案与计算都在 VigorScoring 中（`FTPHistory`、`CyclingTrends`）。
@MainActor
enum CyclingTrendText {
    static func monthlyChange(_ slopePerDay: Double) -> String {
        let monthly = slopePerDay * 30
        let direction = monthly >= 0 ? "提高" : "下降"
        return "近 90 天每月\(direction) \(String(format: "%.2f", abs(monthly)))"
    }

    static func ftpWindowNote(_ model: AppModel) -> String {
        let days = model.snapshot.map { max(0, Int(($0.rangeEnd.timeIntervalSince($0.rangeStart) / 86_400).rounded())) } ?? 0
        return "历史只覆盖快照窗口（约 \(days) 天）。更早的周没有骑行或 FTP 数据，显示为空。"
    }
}

/// FTP 历史（每周一个点，最近 365 天）。
struct FTPHistoryView: View {
    let model: AppModel

    private var points: [FTPPoint] {
        FTPHistory.make(
            rides: model.cycling?.rides ?? [],
            healthKitFTP: model.snapshot?.ftp ?? [],
            manual: AppSettings.manualFTPHistory,
            now: model.lastUpdated ?? Date(),
            calendar: model.calendar
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FTP 历史（近 365 天，每周）").font(.headline)
                        if points.contains(where: { $0.watts != nil }) {
                            chart
                        } else {
                            Text("还没有可用的 FTP 历史。").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("取值来源").font(.headline)
                        Text("每个时间点按优先级取值：当时生效的手动设置 > 当时最新的健康中的 FTP > 截至当时最近 90 天最佳 20 分钟功率 × 0.95。")
                            .font(.callout)
                        Text("手动设置的历史从本版本开始记录；之前修改的值没有时间记录，不会出现在这里。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(CyclingTrendText.ftpWindowNote(model))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("FTP 历史")
    }

    private var chart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                if let watts = point.watts {
                    LineMark(x: .value("日期", point.date, unit: .day), y: .value("FTP", watts), series: .value("段", "\(runIndex(upTo: index))"))
                        .foregroundStyle(VigorTokens.load)
                    PointMark(x: .value("日期", point.date, unit: .day), y: .value("FTP", watts))
                        .foregroundStyle(by: .value("来源", sourceName(point.source)))
                        .symbolSize(24)
                }
            }
        }
        .chartForegroundStyleScale(["手动设置": Color.blue, "健康中的 FTP": Color.green, "自动估算": Color.orange])
        .chartYAxisLabel("瓦")
        .frame(height: 200)
    }

    /// 连续有值的周为一段线，缺失处断开。
    private func runIndex(upTo index: Int) -> Int {
        points.prefix(index + 1).reduce(0) { run, point in point.watts == nil ? run + 1 : run }
    }

    private func sourceName(_ source: FTPSource?) -> String {
        switch source {
        case .manual?: "手动设置"
        case .healthKit?: "健康中的 FTP"
        case .estimated?: "自动估算"
        case nil: "无"
        }
    }
}

/// 有氧效率 EF 的散点与 90 天趋势线（M6 补完 C4）。
struct EFTrendView: View {
    let model: AppModel

    private var windowStart: Date {
        let end = model.lastUpdated ?? Date()
        return model.calendar.date(byAdding: .day, value: -90, to: end) ?? end
    }

    private var points: [(date: Date, ef: Double)] {
        (model.cycling?.rides ?? [])
            .compactMap { ride -> (date: Date, ef: Double)? in ride.efficiencyFactor.map { (ride.start, $0) } }
            .sorted { $0.date < $1.date }
    }

    /// 趋势线的两端：过近 90 天点的均值，斜率取自 `CyclingOutput.efficiencySlopePerDay`。
    private var trend: (start: (Date, Double), end: (Date, Double))? {
        guard let slope = model.cycling?.efficiencySlopePerDay else { return nil }
        let recent = points.filter { $0.date >= windowStart }
        guard !recent.isEmpty, let first = recent.first?.date, let last = recent.last?.date else { return nil }
        let meanX = recent.map { $0.date.timeIntervalSince(first) / 86_400 }.reduce(0, +) / Double(recent.count)
        let meanY = recent.map(\.ef).reduce(0, +) / Double(recent.count)
        func value(at date: Date) -> Double {
            meanY + slope * (date.timeIntervalSince(first) / 86_400 - meanX)
        }
        return ((first, value(at: first)), (last, value(at: last)))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: VigorTokens.cardSpacing) {
                SectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("有氧效率 EF").font(.headline)
                        if points.isEmpty {
                            Text("需要同时有功率和心率的骑行。").font(.callout).foregroundStyle(.secondary)
                        } else {
                            chart
                            if let slope = model.cycling?.efficiencySlopePerDay {
                                Text(CyclingTrendText.monthlyChange(slope)).font(.callout)
                            } else {
                                Text("近 90 天的 EF 数据不足（至少需要 3 次骑行）。").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                SectionCard {
                    Text("EF = 标准化功率 ÷ 平均心率。同样的功率下心率越低，EF 越高，通常意味着有氧效率更好。趋势只描述变化方向，不做医学判断。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, VigorTokens.pageMargin)
            .padding(.bottom, 24)
        }
        .navigationTitle("有氧效率 EF")
    }

    private var chart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("日期", point.date, unit: .day), y: .value("EF", point.ef))
                    .foregroundStyle(VigorTokens.load)
                    .symbolSize(28)
            }
            if let trend {
                LineMark(x: .value("日期", trend.start.0), y: .value("趋势", trend.start.1), series: .value("段", "趋势"))
                    .foregroundStyle(.orange)
                LineMark(x: .value("日期", trend.end.0), y: .value("趋势", trend.end.1), series: .value("段", "趋势"))
                    .foregroundStyle(.orange)
            }
        }
        .frame(height: 200)
    }
}
