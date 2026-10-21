import Foundation

/// 日志页中“从健康数据自动填充”的只读项（PRD §6.5）。取的是“昨天”（醒来日的前一天）的汇总。
public struct JournalAutoFill: Sendable, Hashable {
    /// 咖啡因摄入，毫克
    public var caffeineMilligrams: Double?
    /// 含酒精饮品数（杯）
    public var alcoholicDrinks: Double?
    /// 正念时长，分钟
    public var mindfulMinutes: Double?
    /// 日照时间，分钟
    public var daylightMinutes: Double?
    /// 情绪效价的平均值，范围 −1 到 1；没有记录时为空
    public var meanMoodValence: Double?
    /// 情绪记录条数
    public var moodCount: Int

    public init(
        caffeineMilligrams: Double? = nil,
        alcoholicDrinks: Double? = nil,
        mindfulMinutes: Double? = nil,
        daylightMinutes: Double? = nil,
        meanMoodValence: Double? = nil,
        moodCount: Int = 0
    ) {
        self.caffeineMilligrams = caffeineMilligrams
        self.alcoholicDrinks = alcoholicDrinks
        self.mindfulMinutes = mindfulMinutes
        self.daylightMinutes = daylightMinutes
        self.meanMoodValence = meanMoodValence
        self.moodCount = moodCount
    }

    /// - Parameter night: 日志的醒来日（本地零点）；统计的是它前一天的样本。
    /// 样本按开始时间归属，没有样本的指标保持为空（而不是 0），以便界面区分“没有记录”与“记录为零”。
    public static func summarize(_ snapshot: HealthSnapshot?, night: Date, calendar: Calendar) -> JournalAutoFill {
        guard let snapshot else { return JournalAutoFill() }
        let dayEnd = calendar.startOfDay(for: night)
        guard let dayStart = calendar.date(byAdding: .day, value: -1, to: dayEnd) else { return JournalAutoFill() }

        func inDay(_ date: Date) -> Bool { date >= dayStart && date < dayEnd }
        func sum(_ samples: [ValueSample], transform: (Double) -> Double = { $0 }) -> Double? {
            let values = samples.filter { inDay($0.start) }.map { transform($0.value) }
            return values.isEmpty ? nil : values.reduce(0, +)
        }

        let moods = snapshot.stateOfMind.filter { inDay($0.date) }.map(\.valence)
        return JournalAutoFill(
            caffeineMilligrams: sum(snapshot.dietaryCaffeine),
            alcoholicDrinks: sum(snapshot.alcoholicBeverages),
            mindfulMinutes: sum(snapshot.mindfulSessions) { $0 / 60 },
            daylightMinutes: sum(snapshot.timeInDaylight),
            meanMoodValence: moods.isEmpty ? nil : moods.reduce(0, +) / Double(moods.count),
            moodCount: moods.count
        )
    }
}
