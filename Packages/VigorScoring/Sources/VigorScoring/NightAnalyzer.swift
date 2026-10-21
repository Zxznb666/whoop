import Foundation

public struct NightReport: Sendable, Hashable, Codable, Identifiable {
    public var id: Date { session.end }
    public var session: SleepSession
    public var hrv: NightHRV
    public var nightRHR: Double?
    /// wakeDay 当天的 Apple 静息心率
    public var appleRHR: Double?
    /// 时段内均值
    public var respiratoryRate: Double?
    /// 结束时间落在 wakeDay 内的样本
    public var wristTemperature: Double?
    /// 时段内均值
    public var spo2Mean: Double?
    public var heartRateCount: Int

    public init(
        session: SleepSession,
        hrv: NightHRV,
        nightRHR: Double?,
        appleRHR: Double?,
        respiratoryRate: Double?,
        wristTemperature: Double?,
        spo2Mean: Double?,
        heartRateCount: Int
    ) {
        self.session = session
        self.hrv = hrv
        self.nightRHR = nightRHR
        self.appleRHR = appleRHR
        self.respiratoryRate = respiratoryRate
        self.wristTemperature = wristTemperature
        self.spo2Mean = spo2Mean
        self.heartRateCount = heartRateCount
    }
}

public enum NightAnalyzer {
    public static func analyze(
        _ snapshot: HealthSnapshot,
        calendar: Calendar,
        config: HRVConfig = .default
    ) -> [NightReport] {
        let mainSessions = SleepSessionBuilder
            .sessions(from: snapshot.sleep, calendar: calendar, config: config)
            .filter(\.isMain)
        let segments = snapshot.heartbeatSeries.map { RRProcessor.analyze($0, config: config) }

        return mainSessions
            .map { session in
                makeReport(
                    session: session,
                    snapshot: snapshot,
                    segments: segments,
                    calendar: calendar,
                    config: config
                )
            }
            .sorted { $0.session.end > $1.session.end }
    }

    private static func makeReport(
        session: SleepSession,
        snapshot: HealthSnapshot,
        segments: [SegmentResult],
        calendar: Calendar,
        config: HRVConfig
    ) -> NightReport {
        let hrv = NightHRVAggregator.aggregate(
            session: session,
            segments: segments,
            sdnn: snapshot.hrvSDNN,
            config: config
        )
        let heartRates = snapshot.heartRate.filter { contains($0.date, in: session) }
        let appleRHR = snapshot.restingHeartRate.first {
            day(of: $0.start, calendar: calendar) == session.wakeDay
        }?.value
        let wristTemperature = snapshot.wristTemperature.first {
            day(of: $0.end, calendar: calendar) == session.wakeDay
        }?.value

        return NightReport(
            session: session,
            hrv: hrv,
            nightRHR: NightRestingHR.compute(heartRate: snapshot.heartRate, session: session),
            appleRHR: appleRHR,
            respiratoryRate: mean(snapshot.respiratoryRate.filter { contains($0.start, in: session) }.map(\.value)),
            wristTemperature: wristTemperature,
            spo2Mean: mean(snapshot.oxygenSaturation.filter { contains($0.start, in: session) }.map(\.value)),
            heartRateCount: heartRates.count
        )
    }

    private static func contains(_ date: Date, in session: SleepSession) -> Bool {
        date >= session.start && date <= session.end
    }

    private static func day(of date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

public struct AvailabilitySummary: Sendable, Hashable {
    public var nights: Int
    public var nightsWithRMSSD: Int
    /// 平均每晚的有效夜间片段数
    public var meanValidSegmentsPerNight: Double
    /// ms
    public var medianRMSSD: Double?
    public var qualityCounts: [DataQuality: Int]

    public init(
        nights: Int,
        nightsWithRMSSD: Int,
        meanValidSegmentsPerNight: Double,
        medianRMSSD: Double?,
        qualityCounts: [DataQuality: Int]
    ) {
        self.nights = nights
        self.nightsWithRMSSD = nightsWithRMSSD
        self.meanValidSegmentsPerNight = meanValidSegmentsPerNight
        self.medianRMSSD = medianRMSSD
        self.qualityCounts = qualityCounts
    }

    public static func make(_ reports: [NightReport]) -> AvailabilitySummary {
        let rmssds = reports.compactMap(\.hrv.rmssd)
        var qualityCounts: [DataQuality: Int] = [.high: 0, .medium: 0, .low: 0, .none: 0]
        for report in reports {
            qualityCounts[report.hrv.quality, default: 0] += 1
        }
        let validTotal = reports.reduce(0) { $0 + $1.hrv.validOvernightCount }
        return AvailabilitySummary(
            nights: reports.count,
            nightsWithRMSSD: rmssds.count,
            meanValidSegmentsPerNight: reports.isEmpty ? 0 : Double(validTotal) / Double(reports.count),
            medianRMSSD: rmssds.median,
            qualityCounts: qualityCounts
        )
    }
}
