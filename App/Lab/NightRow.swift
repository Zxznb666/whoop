import SwiftUI
import VigorScoring

struct NightRow: View {
    let report: NightFeatures

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatters.wakeDay(report.session.end))
                    .font(.headline)
                Text(sleepLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(Formatters.rmssd(report.hrv.displayRMSSD))
                    .font(.headline)
                    .monospacedDigit()
                Text("\(report.hrv.nightValidCount)/\(report.hrv.nightTotalCount) 段")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private var sleepLine: String {
        "\(Formatters.duration(report.session.asleepDuration)) · 静息 \(Formatters.bpm(report.restingHeartRate.value))"
    }
}
