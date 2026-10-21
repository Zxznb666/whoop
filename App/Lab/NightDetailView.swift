import SwiftUI
import VigorHealth
import VigorScoring

struct NightDetailView: View {
    let report: NightFeatures

    var body: some View {
        List {
            Section("摘要") {
                LabeledContent("入睡", value: Formatters.clock(report.session.start))
                LabeledContent("醒来", value: Formatters.clock(report.session.end))
                LabeledContent("睡眠时长", value: Formatters.duration(report.session.asleepDuration))
                LabeledContent("RMSSD", value: "\(Formatters.rmssd(report.hrv.displayRMSSD))（\(Formatters.method(report.hrv.method))）")
                if let sdnnMean = report.hrv.sdnnMean {
                    LabeledContent("SDNN 均值", value: Formatters.rmssd(sdnnMean))
                }
                LabeledContent("夜间静息心率", value: Formatters.bpm(report.restingHeartRate.value))
                LabeledContent("Apple 静息心率", value: Formatters.bpm(report.appleRestingHeartRate))
                LabeledContent("呼吸率", value: Formatters.number(report.respiratoryRate, digits: 1, unit: " 次/分"))
                LabeledContent("手腕温度", value: Formatters.number(report.wristTemperature, digits: 1, unit: " °C"))
                LabeledContent("血氧", value: report.spo2MedianPercent.map { Formatters.percent($0 / 100) } ?? "—")
                LabeledContent("心率样本数", value: "\(report.heartRateCount)")
            }

            Section("睡眠分期") {
                HypnogramChart(session: report.session, segments: report.windows)
                    .frame(height: 200)
                    .padding(.vertical, 8)
            }

            segmentSection("夜间片段", segments: report.windows.filter { !$0.isMorning })
            if report.windows.contains(where: \.isMorning) {
                segmentSection("晨测片段", segments: report.windows.filter(\.isMorning))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Formatters.wakeDay(report.session.end))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func segmentSection(_ title: String, segments: [HRVWindow]) -> some View {
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
    let segment: HRVWindow

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
                Text("候选 \(segment.candidateCount) · 接受 \(segment.acceptedCount) · 拒绝 \(segment.rejectedCount)")
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
