// 全部常数集中在这里。每个常数都写明出处：
//   PRD §x.y          = docs/PRD.md 的章节
//   SC.field          = Packages/VigorScoring/.../ScoringConfig.swift 的字段
//   代码 File.swift   = Vigor 代码里的常数
//   M-xx              = 本项目（Muse）新定的取值，依据见 Muse/ALGORITHM.md 附录“Vigor 没有的常数”

export const CONFIG = Object.freeze({
  // 时区：固定偏移（分钟）。合成数据和用户都在 Asia/Shanghai（无夏令时）。M-01
  tzOffsetMinutes: 480,

  // 睡眠会话（PRD §5.2，SC.*）
  sessionMergeGapMin: 45,          // SC.sessionMergeGap
  segmentedSleepMaxGapMin: 120,    // SC.segmentedSleepMaxGap
  nightWindowStartHour: 19,        // SC.nightWindowStartHour
  nightWindowEndHour: 11,          // SC.nightWindowEndHour
  napOnlyStartHour: 15,            // SC.napOnlyStartHour
  napOnlyEndHour: 19,              // SC.napOnlyEndHour
  mainSleepMinHours: 3,            // SC.mainSleepMinDuration
  napMinMinutes: 15,               // SC.napMinDuration
  nightKeyShiftHours: 15,          // 代码 SleepSessionBuilder.swift：夜晚键 = 中点 − 15 小时
  awakeningMinMinutes: 2,          // SC.awakeningMinDuration
  hypnogramMinMinutes: 1,          // SC.hypnogramMinDuration（只影响显示）
  wearGapMinutes: 60,              // SC.wearGapMinutes

  // 夜间静息心率（PRD §5.4）
  restingPercentile: 0.10,         // SC.restingPercentile
  restingMinSamples: 10,           // SC.restingMinSampleCount
  restingExcludeAwakeMinutes: 5,   // SC.restingExcludeAwakeSeconds

  // 生命体征（PRD §5.5）
  respiratoryMinSamples: 3,        // SC.respiratoryMinSamples
  oxygenMinSamples: 3,             // SC.oxygenMinSamples
  oxygenLowPercent: 90,            // SC.oxygenLowThresholdPercent
  breathingDisturbanceElevated: 10, // SC.breathingDisturbanceElevated（单位待真实数据校准）

  // 基线（PRD §5.6，代码 Baseline.swift / PopulationPriors.swift）
  baselineWindow: 30,
  priorWeight: 7,
  madToSigma: 1.4826,
  calibratingBelow: 4,
  sigmaFloor: {
    lnSDNN: 0.06, restingHeartRate: 1.5, respiratoryRate: 0.3,
    wristTemperature: 0.15, oxygenSaturation: 0.5,
    totalSleepHours: 0.1, restorativeHours: 0.1,
  },

  // 恢复（PRD §5.8）
  zClip: 3,
  weights: { hrv: 0.55, rhr: 0.25, sleep: 0.20 },
  logisticK: 1.4,
  logisticOffset: 0.35,
  zoneGreenMin: 67,
  zoneRedMax: 33,
  illnessCap: 33,
  sleepScoreCenter: 80,            // z_sleep = (睡眠分 − 80) / 12
  sleepScoreScale: 12,

  // 睡眠需求（PRD §5.9.3，代码 SleepNeed.swift）
  baseSleepNeedHours: 7.5,         // PipelineInput.baseSleepNeedHours 默认值
  debtDecay: 0.8,
  repaymentRate: 0.3,
  maxDebtHours: 10,
  maxRepaymentHours: 2,
  napCreditFactor: 0.8,
  loadAdditionMinPerStrain: 4,
  loadAdditionStrainFloor: 8,
  loadAdditionMaxMin: 52,

  // 睡眠分（PRD §5.9.4）
  sleepWeights: { duration: 0.55, efficiency: 0.15, consistency: 0.15, restorative: 0.15 },
  sriDays: 7,
  sriMinDays: 5,

  // 负荷（PRD §5.10，代码 LoadCalculator.swift / Strain.swift）
  interpolationGapMin: 15,
  unwornGapMin: 60,
  trimpMinHRR: 0.25,
  strainScale: 5.3,
  strainTrimpDivisor: 10,
  strainMax: 21,

  // 负荷目标（PRD §5.11）
  loadTargets: { green: [14, 18], yellow: [10, 14], red: [0, 10] },
  acwrHigh: 1.3,

  // 生病预警（PRD §5.12.1，代码 IllnessWarning.swift）
  illness: { tempDelta: 0.5, zResp: 1.5, zHRV: -1.5, rhrSigmas: 2, maxConsecutiveHours: 36 },

  // 数据质量阈值（PRD §5.7）
  qualityHigh: 0.75,
  qualityMedium: 0.5,

  // —— 以下是 Muse 分档新增的常数（Vigor 没有），依据见 ALGORITHM.md 附录 ——
  // A 档：HRV 来自睡眠窗口内的 Apple SDNN 记录条数（M-03）
  tierAHrvQuality: { 3: 0.8, 2: 0.6, 1: 0.4 },
  // B/C 档：分量质量（M-04）
  tierBQuality: { hrv: 0.5, hr: 0.5 },
  tierCQuality: { hrv: 0.5, hr: 0.5, sleep: 0.5 },
  // 基线有效夜的质量门槛：A/B 为“至少中”（PRD §5.6），C 档整体为低，门槛放到 0.4（M-05）
  baselineValidMinQuality: { A: 0.5, B: 0.5, C: 0.4, H: 0.5 },
  // H 档（探测实测：Muse 只拿到每小时汇总 + 整晚睡眠会话总量，M-09）
  tierHHrQuality: 0.5,             // 心率只有每小时平均
  tierHMinHourlyVitals: 2,         // 呼吸率、血氧至少 2 个小时值才取中位数
  tierHRestingSource: 'hourlyMin',  // 'hourlyMin' | 'appleDaily'：对照 Vigor，夜间最低小时均值明显更接近（COMPARISON.md）
  // B/C 档负荷估算（M-06）
  nonWorkoutKcalFloor: 300,        // 日常零碎活动消耗，不产生 HRR ≥ 0.25 的负荷
  trimpPerKcal: 0.075,             // 快走约 4.5 kcal/min、HRR≈0.3 → 男性 TRIMP ≈0.34/min
  tierCWorkoutHRR: 0.55,           // C 档没有心率：训练分钟按 HRR 0.55 计
  tierCWorkoutKcalPerMin: 8,       // C 档从总活动能量里扣掉训练部分时，按每分钟 8 kcal 估
});

// 人群先验（代码 PopulationPriors.swift，冷启动收缩用）
export function prior(metric, profile, year) {
  const age = profile?.birthYear ? year - profile.birthYear : null;
  const group = age == null ? 1 : age < 30 ? 0 : age < 40 ? 1 : age < 50 ? 2 : age < 60 ? 3 : 4;
  const sdnn = [60, 52, 45, 40, 35];
  switch (metric) {
    case 'lnSDNN': return { mu: Math.log(sdnn[group]), sigma: 0.30 };
    case 'restingHeartRate': {
      const mu = profile?.sex === 'male' ? 55 : profile?.sex === 'female' ? 58 : 56;
      return { mu, sigma: 5 };
    }
    case 'respiratoryRate': return { mu: 14.5, sigma: 1.2 };
    case 'wristTemperature': return { mu: null, sigma: 0.25 };
    case 'oxygenSaturation': return { mu: 96.5, sigma: 1.0 };
    case 'totalSleepHours': return { mu: 7.0, sigma: 0.6 };
    case 'restorativeHours': return { mu: 2.6, sigma: 0.5 };
    default: throw new Error(`没有先验：${metric}`);
  }
}
