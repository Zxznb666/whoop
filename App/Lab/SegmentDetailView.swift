import Charts
import SwiftUI
import VigorScoring

struct SegmentDetailView: View {
    let segment: SegmentResult

    var body: some View {
        List {
            Section("RR 心动周期") {
                Chart(tachogramPoints) { point in
                    LineMark(
                        x: .value("时间（秒）", point.time),
                        y: .value("RR（ms）", point.rr)
                    )
                }
                .frame(height: 200)
                .padding(.vertical, 8)
            }

            Section("Poincaré 散点图") {
                Chart(poincarePoints) { point in
                    PointMark(
                        x: .value("RRₙ（ms）", point.x),
                        y: .value("RRₙ₊₁（ms）", point.y)
                    )
                    .symbolSize(12)
                }
                .chartXScale(domain: rrDomain)
                .chartYScale(domain: rrDomain)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("统计") {
                LabeledContent("RMSSD", value: Formatters.rmssd(segment.rmssd))
                LabeledContent("平均 RR", value: Formatters.number(meanRR, digits: 0, unit: " ms"))
                LabeledContent("平均心率", value: Formatters.bpm(meanHeartRate))
                LabeledContent("候选 / 接受 / 拒绝", value: "\(segment.candidateRR) / \(segment.acceptedRR) / \(segment.rejectedRR)")
                LabeledContent("结果", value: segment.isValid ? "有效" : (segment.invalidReason ?? "无效"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Formatters.clockRange(segment.start, segment.end))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tachogramPoints: [RRPoint] {
        zip(segment.acceptedRRTimes, segment.acceptedRRms).enumerated().map { index, pair in
            RRPoint(id: index, time: pair.0, rr: pair.1)
        }
    }

    /// 只连接时间上相邻的两个被接受的 RR：两拍之间的时间差等于后一个 RR，说明中间没有被剔除或打断的拍。
    private var poincarePoints: [PoincarePoint] {
        let rr = segment.acceptedRRms
        let times = segment.acceptedRRTimes
        return rr.indices.dropFirst().compactMap { index in
            guard index < times.count, abs((times[index] - times[index - 1]) - rr[index] / 1000) < 1e-6 else {
                return nil
            }
            return PoincarePoint(id: index, x: rr[index - 1], y: rr[index])
        }
    }

    private var rrDomain: ClosedRange<Double> {
        guard let low = segment.acceptedRRms.min(), let high = segment.acceptedRRms.max() else {
            return 0...1
        }
        return (low - 20)...(high + 20)
    }

    private var meanRR: Double? {
        let values = segment.acceptedRRms
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private var meanHeartRate: Double? {
        meanRR.map { 60_000 / $0 }
    }
}

private struct RRPoint: Identifiable {
    let id: Int
    let time: Double
    let rr: Double
}

private struct PoincarePoint: Identifiable {
    let id: Int
    let x: Double
    let y: Double
}
