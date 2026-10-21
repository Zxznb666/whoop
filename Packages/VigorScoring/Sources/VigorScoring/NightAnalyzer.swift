import Foundation

/// 每个主睡眠对应的夜间特征（PRD §8.3 的 `NightFeatures`，不含基线与质量，阶段 3 补充）。
public struct NightFeatures: Sendable, Hashable, Codable, Identifiable {
    public var id: Date { session.end }
    public var session: SleepSession
    public var hrv: NightHRV
    /// 夜间窗口与晨测窗口的全部段，含上下文、权重与是否采用
    public var windows: [HRVWindow]
    public var restingHeartRate: RestingHeartRate
    /// 睡眠时段内心率点的平均值
    public var meanHeartRate: Double?
    public var heartRateCount: Int
    /// 主睡眠内是否有超过 60 分钟没有心率点的时段（部分未佩戴，§5.2 第 6 条）
    public var partialWear: Bool
    public var longestHeartRateGapMinutes: Double?
    public var awakenings: Int
    /// 呼吸率的夜间中位数（次/分）
    public var respiratoryRate: Double?
    /// 手腕温度（°C，原始值；偏差在阶段 3 计算）
    public var wristTemperature: Double?
    /// 血氧夜间中位数（%）
    public var spo2MedianPercent: Double?
    /// 血氧低于 90% 的样本占比（0–1）
    public var spo2BelowFraction: Double?
    /// 呼吸紊乱的原始值与单位字符串（待校准，§4.7）
    public var breathingDisturbance: Double?
    public var breathingDisturbanceUnit: String?
    /// Apple 的静息心率（当天）
    public var appleRestingHeartRate: Double?

    public init(
        session: SleepSession,
        hrv: NightHRV,
        windows: [HRVWindow],
        restingHeartRate: RestingHeartRate,
        meanHeartRate: Double?,
        heartRateCount: Int,
        partialWear: Bool,
        longestHeartRateGapMinutes: Double?,
        awakenings: Int,
        respiratoryRate: Double?,
        wristTemperature: Double?,
        spo2MedianPercent: Double?,
        spo2BelowFraction: Double?,
        breathingDisturbance: Double?,
        breathingDisturbanceUnit: String?,
        appleRestingHeartRate: Double?
    ) {
        self.session = session
        self.hrv = hrv
        self.windows = windows
        self.restingHeartRate = restingHeartRate
        self.meanHeartRate = meanHeartRate
        self.heartRateCount = heartRateCount
        self.partialWear = partialWear
        self.longestHeartRateGapMinutes = longestHeartRateGapMinutes
        self.awakenings = awakenings
        self.respiratoryRate = respiratoryRate
        self.wristTemperature = wristTemperature
        self.spo2MedianPercent = spo2MedianPercent
        self.spo2BelowFraction = spo2BelowFraction
        self.breathingDisturbance = breathingDisturbance
        self.breathingDisturbanceUnit = breathingDisturbanceUnit
        self.appleRestingHeartRate = appleRestingHeartRate
    }
}

public enum NightAnalyzer {
    /// 对快照中的每个主睡眠计算夜间特征，按醒来时间倒序返回。
    public static func analyze(
        _ snapshot: HealthSnapshot,
        calendar: Calendar,
        config: ScoringConfig = .default,
        overrides: [DateComponents: SleepOverride] = [:]
    ) -> [NightFeatures] {
        let sessions = SleepSessionBuilder.sessions(
            stages: snapshot.sleep,
            inBed: snapshot.inBed,
            calendar: calendar,
            config: config,
            overrides: overrides
        )
        let analyzed = snapshot.heartbeatSeries.map { RRProcessor.analyze($0, config: config) }

        return sessions
            .filter(\.isMain)
            .map { makeFeatures(session: $0, snapshot: snapshot, analyzed: analyzed, calendar: calendar, config: config) }
            .sorted { $0.session.end > $1.session.end }
    }

    private static func makeFeatures(
        session: SleepSession,
        snapshot: HealthSnapshot,
        analyzed: [HRVWindow],
        calendar: Calendar,
        config: ScoringConfig
    ) -> NightFeatures {
        var (overnight, morning) = NightHRVAggregator.classify(
            session: session,
            analyzed: analyzed,
            mindfulSessions: snapshot.mindfulSessions,
            config: config
        )

        // 顺序：有效序列的平均心率 → 静息心率 → 扰动检测 → 合成（§5.4、§5.3.3 的依赖关系）
        let validSeriesMeans = overnight.filter(\.isValid).compactMap(\.meanHeartRate)
        let appleRHR = appleRestingHeartRate(snapshot, session: session, calendar: calendar)
        let restingHR = NightRestingHR.compute(
            heartRate: snapshot.heartRate,
            session: session,
            seriesMeanHeartRates: validSeriesMeans,
            appleRestingHeartRate: appleRHR,
            config: config
        )
        for index in overnight.indices {
            RRProcessor.applyDisturbance(&overnight[index], restingHeartRate: restingHR.value, config: config)
        }

        let hrv = NightHRVAggregator.aggregate(
            session: session,
            overnight: &overnight,
            morning: &morning,
            sdnn: snapshot.hrvSDNN,
            config: config
        )

        let heartRates = snapshot.heartRate.filter { $0.date >= session.start && $0.date <= session.end }
        let gapMinutes = longestHeartRateGapMinutes(heartRates, session: session)
        let breathing = snapshot.breathingDisturbances.first { day(of: $0.end, calendar: calendar) == session.wakeDay }

        return NightFeatures(
            session: session,
            hrv: hrv,
            windows: (overnight + morning).sorted { $0.start < $1.start },
            restingHeartRate: restingHR,
            meanHeartRate: Statistics.mean(heartRates.map(\.bpm)),
            heartRateCount: heartRates.count,
            // 没有任何心率点同样算作超过阈值的空白（§5.2 第 6 条）
            partialWear: (gapMinutes ?? .infinity) > config.wearGapMinutes,
            longestHeartRateGapMinutes: gapMinutes,
            awakenings: SleepEvents.awakeningCount(in: session, config: config),
            respiratoryRate: median(snapshot.respiratoryRate, in: session, minimum: config.respiratoryMinSamples),
            wristTemperature: snapshot.wristTemperature.first { day(of: $0.end, calendar: calendar) == session.wakeDay }?.value,
            spo2MedianPercent: median(snapshot.oxygenSaturation, in: session, minimum: config.oxygenMinSamples, scale: 100),
            spo2BelowFraction: belowFraction(snapshot.oxygenSaturation, in: session, threshold: config.oxygenLowThresholdPercent, minimum: config.oxygenMinSamples),
            breathingDisturbance: breathing?.value,
            breathingDisturbanceUnit: breathing?.unit,
            appleRestingHeartRate: appleRHR
        )
    }

    /// 心率点之间的最长空白（分钟），包括从入睡到第一个点、以及从最后一个点到醒来。没有心率点时为 nil。
    static func longestHeartRateGapMinutes(_ points: [HeartRateSample], session: SleepSession) -> Double? {
        guard !points.isEmpty else { return nil }
        let dates = [session.start] + points.map(\.date).sorted() + [session.end]
        let gap = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0
        return gap / 60
    }

    private static func appleRestingHeartRate(_ snapshot: HealthSnapshot, session: SleepSession, calendar: Calendar) -> Double? {
        snapshot.restingHeartRate.first { day(of: $0.start, calendar: calendar) == session.wakeDay }?.value
    }

    private static func median(
        _ samples: [ValueSample],
        in session: SleepSession,
        minimum: Int,
        scale: Double = 1
    ) -> Double? {
        let values = samples.filter { $0.start >= session.start && $0.start <= session.end }.map { $0.value * scale }
        guard values.count >= minimum else { return nil }
        return Statistics.median(values)
    }

    private static func belowFraction(
        _ samples: [ValueSample],
        in session: SleepSession,
        threshold: Double,
        minimum: Int
    ) -> Double? {
        let values = samples.filter { $0.start >= session.start && $0.start <= session.end }.map { $0.value * 100 }
        guard values.count >= minimum else { return nil }
        return Double(values.filter { $0 < threshold }.count) / Double(values.count)
    }

    private static func day(of date: Date, calendar: Calendar) -> DateComponents {
        SleepSessionBuilder.dayComponents(date, calendar: calendar)
    }
}

public struct AvailabilitySummary: Sendable, Hashable {
    public var nights: Int
    public var nightsWithRMSSD: Int
    /// 平均每晚的有效夜间片段数
    public var meanValidSegmentsPerNight: Double
    /// ms
    public var medianRMSSD: Double?

    public init(nights: Int, nightsWithRMSSD: Int, meanValidSegmentsPerNight: Double, medianRMSSD: Double?) {
        self.nights = nights
        self.nightsWithRMSSD = nightsWithRMSSD
        self.meanValidSegmentsPerNight = meanValidSegmentsPerNight
        self.medianRMSSD = medianRMSSD
    }

    public static func make(_ nights: [NightFeatures]) -> AvailabilitySummary {
        let rmssds = nights.compactMap(\.hrv.nightRMSSD)
        let validTotal = nights.reduce(0) { $0 + $1.hrv.nightValidCount }
        return AvailabilitySummary(
            nights: nights.count,
            nightsWithRMSSD: rmssds.count,
            meanValidSegmentsPerNight: nights.isEmpty ? 0 : Double(validTotal) / Double(nights.count),
            medianRMSSD: Statistics.median(rmssds)
        )
    }
}
