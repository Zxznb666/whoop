import SwiftUI
import VigorScoring

struct NightRow: View {
    let report: NightReport

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Formatters.qualityColor(report.hrv.quality))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(Formatters.wakeDay(report.session.end))
                    .font(.headline)
                Text(sleepLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(Formatters.rmssd(report.hrv.rmssd))
                    .font(.headline)
                    .monospacedDigit()
                Text("\(report.hrv.validOvernightCount)/\(report.hrv.overnightSegments.count) 段")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private var sleepLine: String {
        "\(Formatters.duration(report.session.asleepDuration)) · 静息 \(Formatters.bpm(report.nightRHR))"
    }
}
