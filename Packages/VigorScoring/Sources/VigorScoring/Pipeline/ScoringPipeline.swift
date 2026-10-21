import Foundation

/// 基线排除的原因（PRD §5.6 第 5 条、§5.12.1）。
public enum ExclusionReason: String, Sendable, Hashable, Codable {
    /// 连续两晚“可能不适”，自动排除
    case illness
    /// 日志中确认“不适”
    case userConfirmedIllness
    /// 跨越 3 个及以上时区后的头 2 晚
    case travel
    /// 设置里手动指定的日期
    case manual
}

/// 分数的状态机（PRD §5.13）：等待 → 初步 → 最终 → 锁定。
public enum ScoreState: String, Sendable, Hashable, Codable {
    case waiting
    case preliminary
    case final
    case locked
}

public struct PipelineInput: Sendable {
    public var snapshot: HealthSnapshot
    public var journal: [JournalEntry]
    /// 手动修正的主睡眠起止，键为夜晚键（中点 − 15 小时）
    public var sleepOverrides: [DateComponents: SleepOverride]
    /// 手动排除的醒来日（年月日）
    public var manualExcludedNights: Set<DateComponents>
    /// 基础睡眠需求（小时），可由个性化或手动覆盖
    public var baseSleepNeedHours: Double
    /// 每个日历日（年月日）的负荷，用于负荷追加；阶段 4 之前为空
    public var strainByDay: [DateComponents: Double]
    /// 目标起床时间（一天中的分钟数）；为 nil 时不给出作息建议
    public var targetWakeMinutes: Int?
    public var config: ScoringConfig
    public var now: Date
    public var calendar: Calendar

    public init(
        snapshot: HealthSnapshot,
        journal: [JournalEntry] = [],
        sleepOverrides: [DateComponents: SleepOverride] = [:],
        manualExcludedNights: Set<DateComponents> = [],
        baseSleepNeedHours: Double = 7.5,
        strainByDay: [DateComponents: Double] = [:],
        targetWakeMinutes: Int? = nil,
        config: ScoringConfig = .default,
        now: Date,
        calendar: Calendar
    ) {
        self.snapshot = snapshot
        self.journal = journal
        self.sleepOverrides = sleepOverrides
        self.manualExcludedNights = manualExcludedNights
        self.baseSleepNeedHours = baseSleepNeedHours
        self.strainByDay = strainByDay
        self.targetWakeMinutes = targetWakeMinutes
        self.config = config
        self.now = now
        self.calendar = calendar
    }
}

/// 每个周期（一次醒来）的全部结果。
public struct CycleResult: Sendable, Hashable, Codable, Identifiable {
    public var id: Date { wakeTime }
    /// 醒来日（年月日）
    public var wakeDay: DateComponents
    public var wakeTime: Date
    public var features: NightFeatures
    public var quality: QualityReport
    public var baselines: [BaselineMetric: BaselineStatistic]
    public var zHRV: Double?
    public var zRHR: Double?
    public var zResp: Double?
    /// Δt（°C），没有样本时为 nil
    public var temperatureDelta: Double?
    public var sleepMetrics: SleepMetrics
    public var sri: Double?
    public var need: SleepNeedComponents
    public var sleepScore: SleepScore
    /// 当晚结束后的睡眠负债 D_t（小时）
    public var debtAfterNight: Double
    public var illnessSignals: IllnessSignals
    public var illness: IllnessLevel
    /// 饮酒或桑拿：只做提示，不推送，不自动排除（§5.12.1）
    public var illnessConfounded: Bool
    public var exclusion: ExclusionReason?
    public var recovery: RecoveryResult?
    public var recoveryState: ScoreState
    public var trend: TrendSummary?
    public var bedtimeAdvice: BedtimeAdvice?
    public var algorithmVersion: Int
    public var configVersion: Int
    /// 输入哈希（FNV-1a）：特征、算法版本与配置版本相同时哈希不变
    public var inputHash: UInt64
}

public struct PipelineOutput: Sendable {
    /// 按醒来时间升序
    public var cycles: [CycleResult]
    /// 基础睡眠需求的个性化建议（积累 60 晚以后）
    public var personalizedNeed: PersonalizedNeed?
}

/// 评分流水线：对全部历史的纯函数（施工文档 §4.2）。同样的输入得到同样的输出。
public enum ScoringPipeline {
    public static let algorithmVersion = 1

    public static func run(_ input: PipelineInput) -> PipelineOutput {
        let calendar = input.calendar
        let config = input.config
        let snapshot = input.snapshot
        let profile = snapshot.profile

        let overrides = input.sleepOverrides
        let allSessions = SleepSessionBuilder.sessions(
            stages: snapshot.sleep,
            inBed: snapshot.inBed,
            calendar: calendar,
            config: config,
            overrides: overrides
        )
        let naps = allSessions.filter { $0.kind == .nap }
        let features = NightAnalyzer
            .analyze(snapshot, calendar: calendar, config: config, overrides: overrides)
            .sorted { $0.session.end < $1.session.end }

        let journalByDay = Dictionary(
            input.journal.map { (SleepSessionBuilder.dayComponents($0.night, calendar: calendar), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var exclusions: [Int: ExclusionReason] = [:]
        for (index, night) in features.enumerated() {
            let day = SleepSessionBuilder.dayComponents(night.session.end, calendar: calendar)
            if input.manualExcludedNights.contains(day) {
                exclusions[index] = .manual
            }
        }
        // 跨 3 个及以上时区（UTC 偏移相差 ≥ 3 小时）后的头 2 晚
        for index in features.indices.dropFirst() {
            let shift = abs(features[index].session.timeZoneOffset - features[index - 1].session.timeZoneOffset)
            if shift >= 3 * 3600 {
                for affected in [index, index + 1] where affected < features.count && exclusions[affected] == nil {
                    exclusions[affected] = .travel
                }
            }
        }

        var observations: [BaselineObservation] = []
        var previousDebt = 0.0
        var previousAttention = false
        var cycles: [CycleResult] = []
        var validLnRMSSD: [Double] = []
        var validBedtimes: [Date] = []

        for index in features.indices {
            let night = features[index]
            let wake = night.session.end
            let wakeDay = SleepSessionBuilder.dayComponents(wake, calendar: calendar)
            let year = calendar.component(.year, from: wake)
            let quality = DataQualityScorer.score(night, config: config)

            var stats: [BaselineMetric: BaselineStatistic] = [:]
            for metric in BaselineMetric.allCases {
                stats[metric] = BaselineHistory.statistic(
                    for: metric,
                    before: index,
                    in: observations,
                    profile: profile,
                    year: year
                )
            }

            let metrics = SleepMetricsCalculator.make(session: night.session, bedtime: night.session.bedtime, config: config)
            let sri = SleepRegularity.sri(stages: snapshot.sleep, endingAt: wake, calendar: calendar)

            // 睡眠需求与睡眠分（§5.9）
            let previousWake = index > 0 ? features[index - 1].session.end : Date.distantPast
            let napHours = naps
                .filter { $0.start >= previousWake && $0.start < night.session.start }
                .reduce(0) { $0 + $1.asleepDuration } / 3600
            let yesterday = calendar.date(byAdding: .day, value: -1, to: wake)
                .map { SleepSessionBuilder.dayComponents($0, calendar: calendar) }
            let previousStrain = yesterday.flatMap { input.strainByDay[$0] }
            let need = SleepNeed.components(
                base: input.baseSleepNeedHours,
                loadAddition: SleepNeed.loadAdditionHours(previousStrain: previousStrain),
                napCredit: SleepNeed.napCreditHours(napAsleepHours: napHours),
                previousDebt: previousDebt
            )
            let zRestorative = zScore(metrics.restorativeHours, stats[.restorativeHours])
            let sleepScore = SleepScoring.score(
                totalSleepHours: metrics.totalSleepHours,
                napCreditHours: SleepNeed.napCreditHours(napAsleepHours: napHours),
                needHours: need.total,
                efficiency: metrics.efficiency,
                sri: sri,
                zRestorative: zRestorative
            )

            // 三种 HRV 模式合成 z_hrv（§5.3.5）
            let zNight = night.hrv.nightRMSSD.flatMap { zScore(log($0), stats[.lnRMSSDNight]) }
            let morningUsable = (stats[.lnRMSSDMorning]?.count ?? 0) >= 7
            let zMorning = morningUsable ? night.hrv.morningRMSSD.flatMap { zScore(log($0), stats[.lnRMSSDMorning]) } : nil
            let zSDNN = night.hrv.sdnnMean.flatMap { zScore(log($0), stats[.lnSDNN]) }
            let zHRV: Double?
            if let zNight, let zMorning {
                var nightOnly = night.hrv
                nightOnly.morningValidCount = 0
                let qualityNight = DataQualityScorer.hrvComponent(nightOnly, config: config)
                let qualityMorning = 1.0
                zHRV = (qualityNight * zNight + 1.5 * qualityMorning * zMorning) / (qualityNight + 1.5 * qualityMorning)
            } else {
                zHRV = zNight ?? zMorning ?? zSDNN
            }

            let zRHR = zScore(night.restingHeartRate.value, stats[.restingHeartRate]).map { -$0 }
            let zResp = zScore(night.respiratoryRate, stats[.respiratoryRate])
            let temperatureDelta = night.wristTemperature.map { value -> Double in
                guard let mu = stats[.wristTemperature]?.mu else { return 0 }
                return value - mu
            }

            // 生病预警（§5.12.1）
            let signals = IllnessWarning.signals(
                temperatureDelta: temperatureDelta,
                zResp: zResp,
                zHRV: zHRV,
                restingHeartRate: night.restingHeartRate.value,
                restingBaseline: stats[.restingHeartRate] ?? BaselineStatistic(mu: nil, sigma: 1, count: 0)
            )
            let attention = IllnessWarning.meetsAttentionCondition(signals)
            let level: IllnessLevel = attention ? (previousAttention ? .possiblyUnwell : .attention) : .none
            let day = wakeDay
            let journal = journalByDay[day]
            let confounded = journal?.behaviors["alcohol"] == true || journal?.behaviors["sauna"] == true
            if journal?.feltUnwell == true, exclusions[index] == nil {
                exclusions[index] = .userConfirmedIllness
            }
            if level == .possiblyUnwell, !confounded {
                if index > 0, exclusions[index - 1] == nil {
                    exclusions[index - 1] = .illness
                }
                if exclusions[index] == nil {
                    exclusions[index] = .illness
                }
            }
            previousAttention = attention

            // 恢复分数（§5.8）
            let penalties = RecoveryPenalties.make(
                zResp: zResp,
                temperatureDelta: temperatureDelta,
                oxygenMedianPercent: night.spo2MedianPercent,
                breathingElevated: (night.breathingDisturbance ?? 0) >= config.breathingDisturbanceElevated
            )
            let recovery = RecoveryScorer.score(RecoveryInputs(
                zHRV: zHRV,
                zRHR: zRHR,
                zSleep: sleepScore.zSleep,
                penalties: penalties,
                illnessPossible: level == .possiblyUnwell
            ))

            // 睡眠负债递推（§5.9.3）
            let debtAfter = SleepNeed.nextDebt(
                previousDebt: previousDebt,
                baseNeed: need.baseNeed,
                totalSleep: metrics.totalSleepHours
            )

            // 基线观测：只有这一晚被确认有效，它才会进入之后的基线
            var values: [BaselineMetric: Double] = [:]
            if let r = night.hrv.nightRMSSD { values[.lnRMSSDNight] = log(r) }
            if let m = night.hrv.morningRMSSD { values[.lnRMSSDMorning] = log(m) }
            if let s = night.hrv.sdnnMean, s > 0 { values[.lnSDNN] = log(s) }
            if let h = night.restingHeartRate.value { values[.restingHeartRate] = h }
            if let r = night.respiratoryRate { values[.respiratoryRate] = r }
            if let t = night.wristTemperature { values[.wristTemperature] = t }
            if let o = night.spo2MedianPercent { values[.oxygenSaturation] = o }
            values[.totalSleepHours] = metrics.totalSleepHours
            values[.restorativeHours] = metrics.restorativeHours
            if let l = metrics.sleepLatencyMinutes { values[.sleepLatencyMinutes] = l }
            let qualityOK = quality.level == .high || quality.level == .medium
            observations.append(BaselineObservation(values: values, isValid: false))
            // 之前的夜晚可能因为刚刚的判断被排除：同步更新它们的有效性
            for earlier in observations.indices {
                let ok = earlier == index
                    ? qualityOK && exclusions[index] == nil
                    : observations[earlier].isValid && exclusions[earlier] == nil
                observations[earlier].isValid = ok
            }
            if qualityOK, exclusions[index] == nil, let l = values[.lnRMSSDNight] {
                validLnRMSSD.append(l)
            }
            if exclusions[index] == nil, qualityOK {
                validBedtimes.append(night.session.start)
            }

            let trend = TrendAnalysis.summarize(lnRMSSD: validLnRMSSD)
            let advice = input.targetWakeMinutes.flatMap { minutes in
                bedtimeAdvice(
                    wake: wake,
                    targetMinutes: minutes,
                    debtAfter: debtAfter,
                    baseNeed: input.baseSleepNeedHours,
                    recentBedtimes: Array(validBedtimes.suffix(7)),
                    previousBedtime: validBedtimes.last,
                    calendar: calendar
                )
            }

            cycles.append(CycleResult(
                wakeDay: wakeDay,
                wakeTime: wake,
                features: night,
                quality: quality,
                baselines: stats,
                zHRV: zHRV,
                zRHR: zRHR,
                zResp: zResp,
                temperatureDelta: temperatureDelta,
                sleepMetrics: metrics,
                sri: sri,
                need: need,
                sleepScore: sleepScore,
                debtAfterNight: debtAfter,
                illnessSignals: signals,
                illness: level,
                illnessConfounded: confounded,
                exclusion: exclusions[index],
                recovery: recovery,
                recoveryState: state(recovery: recovery, wake: wake, vitalsComplete: night.vitalsComplete, now: input.now),
                trend: trend,
                bedtimeAdvice: advice,
                algorithmVersion: algorithmVersion,
                configVersion: config.configVersion,
                inputHash: inputHash(night, configVersion: config.configVersion)
            ))
            previousDebt = debtAfter
        }

        // 排除可能在之后的夜晚才被判定（连续两晚的回溯排除），因此最终状态回写到每个周期
        for index in cycles.indices {
            cycles[index].exclusion = exclusions[index]
        }
        var personalized: PersonalizedNeed?
        if cycles.count >= 60 {
            personalized = personalizedNeed(cycles: cycles, base: input.baseSleepNeedHours, calendar: calendar)
        }
        return PipelineOutput(cycles: cycles, personalizedNeed: personalized)
    }

    // MARK: 工具

    static func zScore(_ value: Double?, _ statistic: BaselineStatistic?) -> Double? {
        guard let value, let statistic, let mu = statistic.mu else { return nil }
        return (value - mu) / statistic.sigma
    }

    /// 等待 → 初步 → 最终 → 锁定（§5.13）。`vitalsComplete` 作为“数据到齐”的近似。
    static func state(recovery: RecoveryResult?, wake: Date, vitalsComplete: Bool, now: Date) -> ScoreState {
        guard recovery != nil, now >= wake else { return .waiting }
        if now >= wake.addingTimeInterval(48 * 3600) { return .locked }
        if vitalsComplete || now >= wake.addingTimeInterval(3 * 3600) { return .final }
        return .preliminary
    }

    /// FNV-1a 64 位哈希，结果在不同进程间稳定（`Hasher` 不满足这一点）。
    /// 覆盖分数所用的全部标量特征、算法版本与配置版本；RR 数组等大字段由它们的汇总值代表。
    static func inputHash(_ night: NightFeatures, configVersion: Int) -> UInt64 {
        let hrv = night.hrv
        let rhr = night.restingHeartRate
        let fields: [String] = [
            "\(algorithmVersion)", "\(configVersion)",
            "\(night.session.start.timeIntervalSince1970)", "\(night.session.end.timeIntervalSince1970)",
            "\(night.session.asleepDuration)", "\(night.session.bedtime?.timeIntervalSince1970 ?? -1)",
            "\(hrv.nightRMSSD ?? -1)", "\(hrv.morningRMSSD ?? -1)", "\(hrv.sdnnMean ?? -1)",
            "\(hrv.dispersion ?? -1)", "\(hrv.nightValidCount)", "\(hrv.morningValidCount)",
            "\(rhr.value ?? -1)", "\(rhr.sampleCount)", "\(night.meanHeartRate ?? -1)",
            "\(night.heartRateCount)", "\(night.heartRateCoverage)", "\(night.awakenings)",
            "\(night.respiratoryRate ?? -1)", "\(night.wristTemperature ?? -1)",
            "\(night.spo2MedianPercent ?? -1)", "\(night.spo2BelowFraction ?? -1)",
            "\(night.breathingDisturbance ?? -1)", "\(night.appleRestingHeartRate ?? -1)",
            "\(night.windows.map { "\($0.rmssd ?? -1)|\($0.acceptedCount)|\($0.invalidReason ?? "")" }.joined(separator: ";"))",
        ]
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in fields.joined(separator: "\u{1f}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// 作息建议：目标起床时间为醒来日的次日；渐进调整依赖最近 7 晚的环形均值。
    static func bedtimeAdvice(
        wake: Date,
        targetMinutes: Int,
        debtAfter: Double,
        baseNeed: Double,
        recentBedtimes: [Date],
        previousBedtime: Date?,
        calendar: Calendar
    ) -> BedtimeAdvice? {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: wake)),
              let target = calendar.date(byAdding: .minute, value: targetMinutes, to: nextDay)
        else { return nil }
        let need = SleepNeed.components(base: baseNeed, loadAddition: 0, napCredit: 0, previousDebt: debtAfter).total
        let average = recentBedtimes.isEmpty ? nil : circularBedtime(recentBedtimes, calendar: calendar)
        return BedtimeAdvisor.advise(
            wakeTime: target,
            needHours: need,
            latencyMinutes: 15,
            averageBedtime: average,
            previousBedtime: previousBedtime
        )
    }

    /// 最近入睡时刻的环形均值，还原到最后一次入睡附近的日期。
    static func circularBedtime(_ bedtimes: [Date], calendar: Calendar) -> Date? {
        let minutes = bedtimes.map { date -> Double in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
        guard let summary = CircularStatistics.summarize(minutesOfDay: minutes),
              let last = bedtimes.last
        else { return nil }
        let day = calendar.startOfDay(for: last)
        let candidate = day.addingTimeInterval(summary.meanMinuteOfDay * 60)
        // 落在最后一次入睡前后 12 小时之内
        var best = candidate
        for shift in [-1, 0, 1] {
            let option = candidate.addingTimeInterval(TimeInterval(shift) * 86_400)
            if abs(option.timeIntervalSince(last)) < abs(best.timeIntervalSince(last)) {
                best = option
            }
        }
        return best
    }

    /// 基础需求的个性化（§5.9.3）。
    static func personalizedNeed(cycles: [CycleResult], base: Double, calendar: Calendar) -> PersonalizedNeed {
        let sleep = cycles.map(\.sleepMetrics.totalSleepHours)
        let debts: [(Double, Double)] = cycles.indices.map { index in
            let d1 = index >= 1 ? cycles[index - 1].debtAfterNight : 0
            let d2 = index >= 2 ? cycles[index - 2].debtAfterNight : 0
            return (d1, d2)
        }
        let free = cycles.map { cycle -> Bool in
            let weekday = calendar.component(.weekday, from: cycle.wakeTime)
            return weekday == 1 || weekday == 7
        }
        let nextZ: [Double?] = cycles.indices.map { index in
            index + 1 < cycles.count ? cycles[index + 1].zHRV : nil
        }
        return PersonalizedNeed.make(
            currentBase: base,
            totalSleepHours: sleep,
            previousDebts: debts,
            isFreeDay: free,
            nextZHRV: nextZ
        )
    }
}

extension NightFeatures {
    /// 三项夜间生命体征是否都可用（用于“数据到齐”的判断）。
    var vitalsComplete: Bool {
        respiratoryRate != nil && wristTemperature != nil && spo2MedianPercent != nil
    }
}
