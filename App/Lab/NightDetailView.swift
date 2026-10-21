import SwiftUI
import VigorHealth
import VigorScoring

struct NightDetailView: View {
    let report: NightReport

    var body: some View {
        List {
            Section("摘要") {
                LabeledContent("入睡", value: Formatters.clock(report.session.start))
                LabeledContent("醒来", value: Formatters.clock(report.session.end))
                LabeledContent("睡眠时长", value: Formatters.duration(report.session.asleepDuration))
                LabeledContent("RMSSD", value: "\(Formatters.rmssd(report.hrv.rmssd))（\(Formatters.method(report.hrv.method))）")
                LabeledContent("质量") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Formatters.qualityColor(report.hrv.quality))
                            .frame(width: 10, height: 10)
                        Text(Formatters.quality(report.hrv.quality))
                    }
                }
                if let sdnnMean = report.hrv.sdnnMean {
                    LabeledContent("SDNN 均值", value: Formatters.rmssd(sdnnMean))
                }
                LabeledContent("夜间静息心率", value: Formatters.bpm(report.nightRHR))
                LabeledContent("Apple 静息心率", value: Formatters.bpm(report.appleRHR))
                LabeledContent("呼吸率", value: Formatters.number(report.respiratoryRate, digits: 1, unit: " 次/分"))
                LabeledContent("手腕温度", value: Formatters.number(report.wristTemperature, digits: 1, unit: " °C"))
                LabeledContent("血氧", value: report.spo2Mean.map { Formatters.percent($0) } ?? "—")
                LabeledContent("心率样本数", value: "\(report.heartRateCount)")
            }

            Section("睡眠分期") {
                HypnogramChart(session: report.session, segments: report.hrv.overnightSegments + report.hrv.morningSegments)
                    .frame(height: 200)
                    .padding(.vertical, 8)
            }

            segmentSection("夜间片段", segments: report.hrv.overnightSegments)
            if !report.hrv.morningSegments.isEmpty {
                segmentSection("晨测片段", segments: report.hrv.morningSegments)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Formatters.wakeDay(report.session.end))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func segmentSection(_ title: String, segments: [SegmentResult]) -> some View {
        Section(title) {
            ForEach(segments, id: \.seriesID) { segment in
                NavigationLink {
                    SegmentDetailView(segment: segment)
                } label: {
                    SegmentRow(segment: segment)
                }
            }
        }
    }
}

private struct SegmentRow: View {
    let segment: SegmentResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Formatters.clockRange(segment.start, segment.end))
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Text(Formatters.rmssd(segment.rmssd))
                    .font(.headline)
                    .monospacedDigit()
            }
            HStack {
                Text("候选 \(segment.candidateRR) · 接受 \(segment.acceptedRR) · 拒绝 \(segment.rejectedRR)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(segment.isValid ? "有效" : (segment.invalidReason ?? "无效"))
                    .font(.caption)
                    .foregroundStyle(segment.isValid ? Color.blue : Color.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
