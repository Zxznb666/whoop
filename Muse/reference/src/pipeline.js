// 评分流水线：按醒来时间顺序逐晚计算（PRD §5.0）。同样的输入永远得到同样的输出。
// 三档共用一套“基线 → z → 恢复 / 睡眠 / 负荷”的结构，只有夜间特征和负荷的取法不同（施工文档 §4）。
import { CONFIG, prior } from './config.js';
import { percentile, median, mean } from './stats.js';
import { dayKey, hhmm, localYear, startOfDayKey } from './time.js';
import { buildSessions, sleepMetrics, sleepMetricsFromTotals, sri, sleepNeed, nextDebt, sleepScore, hypnogram } from './sleep.js';
import { BaselineHistory, zScore } from './baseline.js';
import { penalties, recoveryScore, illnessSignals, loadTarget, acwr } from './recovery.js';
import { buildMinuteGrid, observedPeak, tanaka, cycleLoadA, cycleLoadB, dayLoadC } from './load.js';

const METRICS = ['lnSDNN', 'restingHeartRate', 'respiratoryRate', 'wristTemperature', 'oxygenSaturation', 'totalSleepHours', 'restorativeHours'];

function qualityLevel(total, cfg) {
  if (total >= cfg.qualityHigh) return 'high';
  if (total >= cfg.qualityMedium) return 'medium';
  return 'low';
}

// —— A 档夜间特征 ——————————————————————————————————————————————

/** 夜间静息心率（PRD §5.4）：主睡眠内心率点（去掉 ≥ 5 分钟清醒段里的点）的第 10 百分位；不足 10 个点退回 Apple 每日值。 */
export function nightRestingHR(points, session, appleRHR, cfg = CONFIG) {
  const awakeRuns = session.stages.filter((s) => s.stage === 'awake' && s.end - s.start >= cfg.restingExcludeAwakeMinutes * 60);
  const pool = points.filter((p) => !awakeRuns.some((a) => p.date >= a.start && p.date <= a.end)).map((p) => p.bpm);
  if (pool.length >= cfg.restingMinSamples) return { value: percentile(pool, cfg.restingPercentile), source: 'nightP10', n: pool.length };
  if (appleRHR != null) return { value: appleRHR, source: 'appleDaily', n: pool.length };
  return { value: null, source: 'none', n: pool.length };
}

function inWindow(samples, getT, a, b) {
  return samples.filter((s) => getT(s) >= a && getT(s) <= b);
}

/** 血氧单位：Apple Health 存 0–1 的小数；若探测显示 Muse 给的是百分数，传入的值 > 1 时不再乘 100。 */
const spo2Percent = (v) => (v <= 1 ? v * 100 : v);

function featuresA(input, session, cfg) {
  const { start, end, wakeDay } = session;
  const hr = inWindow(input.heartRate, (s) => s.date, start, end).sort((a, b) => a.date - b.date);
  const apple = input.restingHR.find((s) => dayKey(s.start, cfg) === wakeDay)?.value ?? null;
  const rhr = nightRestingHR(hr, session, apple, cfg);
  const sdnn = inWindow(input.sdnn, (s) => s.start, start, end).sort((a, b) => a.start - b.start);
  const resp = inWindow(input.respiratory, (s) => s.start, start, end).map((s) => s.value);
  const ox = inWindow(input.oxygen, (s) => s.start, start, end).map((s) => spo2Percent(s.value));
  const temp = input.wristTemperature.find((s) => dayKey(s.end, cfg) === wakeDay)?.value ?? null;
  const bd = input.breathing.find((s) => dayKey(s.end, cfg) === wakeDay)?.value ?? null;

  // 佩戴：心率点之间（含入睡→第一个点、最后一个点→醒来）的最长空白；> 60 分钟为部分未佩戴（PRD §5.2 第 6 条）
  const dates = [start, ...hr.map((p) => p.date), end];
  let longest = 0; let longGaps = 0;
  for (let i = 1; i < dates.length; i++) {
    const g = dates[i] - dates[i - 1];
    longest = Math.max(longest, g);
    if (g > cfg.wearGapMinutes * 60) longGaps += g;
  }
  const coverage = hr.length ? Math.min(Math.max(1 - longGaps / (end - start), 0), 1) : 0;
  const hours = (end - start) / 3600;

  const n = sdnn.length;
  const qHrv = n >= 3 ? cfg.tierAHrvQuality[3] : n === 2 ? cfg.tierAHrvQuality[2] : n === 1 ? cfg.tierAHrvQuality[1] : 0;
  const qHr = hours > 0 ? Math.min(1, hr.length / hours / 6) : 0;
  const respMed = resp.length >= cfg.respiratoryMinSamples ? median(resp) : null;
  const oxMed = ox.length >= cfg.oxygenMinSamples ? median(ox) : null;
  const qVitals = [respMed, temp, oxMed].filter((x) => x != null).length / 3;
  const reasons = [];
  if (n === 0) reasons.push('睡眠期间没有 HRV 记录，不出恢复分数');
  else if (n < 3) reasons.push(`睡眠期间只有 ${n} 条 HRV 记录`);
  if (hr.length && longest > cfg.wearGapMinutes * 60) reasons.push('睡眠期间有超过 60 分钟没有心率（可能未佩戴）');
  if (rhr.source === 'appleDaily') reasons.push('夜间心率点不足 10 个，静息心率用 Apple 每日值');

  return {
    hrv: { value: n ? median(sdnn.map((s) => s.value)) : null, samples: sdnn.map((s) => ({ t: s.start, ms: s.value })), label: 'SDNN · 睡眠窗口' },
    rhr,
    respiratoryRate: respMed,
    wristTemperature: temp,
    spo2Median: oxMed,
    spo2BelowFraction: oxMed == null ? null : ox.filter((v) => v < cfg.oxygenLowPercent).length / ox.length,
    breathingElevated: bd != null && bd >= cfg.breathingDisturbanceElevated,
    heartRate: { count: hr.length, mean: mean(hr.map((p) => p.bpm)), longestGapMin: hr.length ? longest / 60 : null, partialWear: !hr.length || longest > cfg.wearGapMinutes * 60 },
    quality: { components: { hrv: qHrv, hr: qHr, sleep: coverage, vitals: qVitals }, reasons },
    labels: [],
  };
}

// —— B 档夜间特征 ——————————————————————————————————————————————

function featuresB(input, session, cfg) {
  const d = input.daily.get(session.wakeDay) ?? {};
  const hasHrv = d.sdnnMean != null;
  const vitals = [d.respiratoryAvg, d.wristTemperature].filter((x) => x != null).length / 2;
  const reasons = [];
  if (!hasHrv) reasons.push('醒来当天没有 HRV 记录，不出恢复分数');
  return {
    hrv: { value: d.sdnnMean ?? null, samples: [], label: 'SDNN · 全天平均（含日间读数）' },
    rhr: { value: d.restingHR ?? null, source: d.restingHR != null ? 'appleDaily' : 'none', n: 0 },
    respiratoryRate: d.respiratoryAvg ?? null,
    wristTemperature: d.wristTemperature ?? null,
    spo2Median: null,
    breathingElevated: false,
    heartRate: { count: null, mean: null, longestGapMin: null, partialWear: null },
    quality: {
      components: { hrv: hasHrv ? cfg.tierBQuality.hrv : 0, hr: d.restingHR != null ? cfg.tierBQuality.hr : 0, sleep: 1, vitals },
      reasons,
    },
    labels: ['HRV 含日间读数'],
  };
}

// —— H 档夜间特征（每小时汇总）——————————————————————————————————————

const inHours = (rows, a, b) => rows.filter((r) => r.t >= a && r.t <= b);

function featuresH(input, session, cfg) {
  const { start, end, wakeDay } = session;
  const H = input.hourly;
  // 只取“小时开始时刻落在睡眠窗口内”的小时值（与 Muse 探测 P6 的口径一致）
  const sdnn = inHours(H.sdnn, start, end);
  const resp = inHours(H.resp, start, end).map((r) => r.value);
  const ox = inHours(H.spo2, start, end).map((r) => spo2Percent(r.value));
  // 手腕温度每晚一条，开始于入睡前后：取开始小时 ∈ [入睡所在整点, 醒来] 的值
  const temp = inHours(H.temp, Math.floor(start / 3600) * 3600, end).map((r) => r.value);
  const fullHours = H.hr.filter((r) => r.t >= start && r.t + 3600 <= end);
  const apple = input.restingHR.get(wakeDay) ?? null;
  let rhr;
  if (cfg.tierHRestingSource === 'hourlyMin' && fullHours.length) {
    rhr = { value: Math.min(...fullHours.map((r) => r.value)), source: 'hourlyMin', n: fullHours.length };
  } else {
    rhr = apple != null ? { value: apple, source: 'appleDaily', n: 0 } : fullHours.length
      ? { value: Math.min(...fullHours.map((r) => r.value)), source: 'hourlyMin', n: fullHours.length } : { value: null, source: 'none', n: 0 };
  }
  const n = sdnn.length;
  const qHrv = n >= 3 ? cfg.tierAHrvQuality[3] : n === 2 ? cfg.tierAHrvQuality[2] : n === 1 ? cfg.tierAHrvQuality[1] : 0;
  const respMed = resp.length >= cfg.tierHMinHourlyVitals ? median(resp) : null;
  const oxMed = ox.length >= cfg.tierHMinHourlyVitals ? median(ox) : null;
  const tempV = temp.length ? mean(temp) : null;
  const qVitals = [respMed, tempV, oxMed].filter((x) => x != null).length / 3;
  const reasons = [];
  if (n === 0) reasons.push('睡眠期间没有 HRV 小时值，不出恢复分数');
  else if (n < 3) reasons.push(`睡眠期间只有 ${n} 个 HRV 小时值`);
  return {
    hrv: { value: n ? median(sdnn.map((r) => r.value)) : null, samples: sdnn.map((r) => ({ t: r.t, ms: r.value })), label: 'SDNN · 睡眠窗口内每小时平均' },
    rhr,
    respiratoryRate: respMed,
    wristTemperature: tempV,
    spo2Median: oxMed,
    breathingElevated: false,
    heartRate: { count: fullHours.length, mean: mean(fullHours.map((r) => r.value)), longestGapMin: null, partialWear: null },
    quality: { components: { hrv: qHrv, hr: H.hr.some((r) => r.t >= start && r.t <= end) ? cfg.tierHHrQuality : 0, sleep: 1, vitals: qVitals }, reasons },
    labels: ['HRV 为每小时平均'],
  };
}

// —— 通用：逐晚评分 ——————————————————————————————————————————————

/**
 * A / B 档：有睡眠分期时段，周期 = 本次入睡 → 下次入睡（PRD §3.1）。
 */
export function runStaged(input, cfg = CONFIG) {
  const tier = input.tier;
  const profile = input.profile;
  const sessions = input.sessions ?? buildSessions(input.sleep, input.inBed, cfg);
  const mains = sessions.filter((s) => s.kind === 'main').sort((a, b) => a.end - b.end);
  const naps = sessions.filter((s) => s.kind === 'nap');
  const sleepByEnd = input.sleep ? [...input.sleep].sort((a, b) => a.end - b.end) : [];

  let grid = null;
  let peaks = [];
  if (tier === 'A') {
    grid = buildMinuteGrid(input.heartRate, input.rangeStart, input.asOf);
    const hrSorted = [...input.heartRate].sort((a, b) => a.date - b.date);
    peaks = input.workouts.map((w) => ({ end: w.end, peak: observedPeak(hrSorted.filter((s) => s.date >= w.start && s.date <= w.end)) }))
      .filter((p) => p.peak != null);
  } else {
    peaks = input.workouts.filter((w) => w.maxHR != null).map((w) => ({ end: w.end, peak: w.maxHR }));
  }

  const history = new BaselineHistory(profile, cfg);
  const excluded = new Set();
  const trimps = [];
  const days = [];
  let previousStrain = null;
  let previousDebt = 0;
  let previousAttention = false;
  let previousWake = null;

  mains.forEach((session, index) => {
    const wake = session.end;
    const year = localYear(wake, cfg);
    const f = tier === 'A' ? featuresA(input, session, cfg) : tier === 'H' ? featuresH(input, session, cfg) : featuresB(input, session, cfg);
    const stats = Object.fromEntries(METRICS.map((m) => [m, history.stat(m, year)]));

    // 睡眠（§5.9）
    const sm = tier === 'H' ? sleepMetricsFromTotals(session) : sleepMetrics(session, cfg);
    const lo = sleepByEnd.findIndex((s) => s.end >= wake - 8 * 86400);
    // H 档没有逐段时间线，算不了 SRI：一致性项去掉，权重按比例分给其余三项
    const sriValue = tier === 'H' ? null : sri(lo < 0 ? [] : sleepByEnd.slice(lo).filter((s) => s.end <= wake), wake, cfg);
    const prevWakeT = index > 0 ? mains[index - 1].end : -Infinity;
    const napHours = naps.filter((n) => n.start >= prevWakeT && n.start < session.start).reduce((a, n) => a + n.asleepSeconds, 0) / 3600;
    const need = sleepNeed({ previousStrain, napHours, previousDebt }, cfg);
    const zRestorative = zScore(sm.restorativeHours, stats.restorativeHours);
    const ss = sleepScore({ tstHours: sm.totalSleepHours, napCreditHours: need.napCredit, needHours: need.total, efficiency: sm.efficiency, sriValue, zRestorative }, cfg);

    // 恢复的输入（§5.8.1）：HRV 在对数域和自己的基线比
    const zHRV = f.hrv.value > 0 ? zScore(Math.log(f.hrv.value), stats.lnSDNN) : null;
    const zRHRraw = zScore(f.rhr.value, stats.restingHeartRate);
    const zRHR = zRHRraw == null ? null : -zRHRraw;
    const zResp = zScore(f.respiratoryRate, stats.respiratoryRate);
    const tempDelta = f.wristTemperature == null ? null : stats.wristTemperature.mu == null ? 0 : f.wristTemperature - stats.wristTemperature.mu;

    // 负荷（§5.10）：醒来 → 下一次主睡眠入睡
    const until = index + 1 < mains.length ? mains[index + 1].start : input.asOf;
    const rest = stats.restingHeartRate.mu ?? prior('restingHeartRate', profile, year).mu;
    const peak = peaks.filter((p) => p.end <= until).reduce((a, p) => Math.max(a, p.peak), -Infinity);
    const maxHR = Math.max(tanaka(profile.birthYear, year), peak);
    const cycleWorkouts = input.workouts.filter((w) => w.start >= wake && w.start < until);
    let load;
    if (tier === 'A') {
      load = cycleLoadA({ grid, wake, until, workouts: cycleWorkouts, rest, max: maxHR, sex: profile.sex }, cfg);
    } else if (tier === 'H') {
      const kcal = input.hourly.kcal.filter((r) => r.t >= Math.floor(wake / 3600) * 3600 && r.t < until).reduce((a, r) => a + r.value, 0);
      const wkcal = cycleWorkouts.reduce((a, w) => a + (w.kcal ?? 0), 0);
      load = cycleLoadB({ workouts: cycleWorkouts, nonWorkoutKcal: kcal - wkcal, rest, max: maxHR, sex: profile.sex }, cfg);
      load.curve = input.hourly.hr.filter((r) => r.t >= Math.floor(wake / 3600) * 3600 && r.t < until).map((r) => ({ t: r.t, bpm: Math.round(r.value * 10) / 10 }));
      load.method = 'hourly-estimate';
    } else {
      const d = input.daily.get(session.wakeDay) ?? {};
      const nonWorkoutKcal = d.activeKcal == null ? null : d.activeKcal - (d.workoutKcal ?? 0);
      load = cycleLoadB({ workouts: cycleWorkouts, nonWorkoutKcal, rest, max: maxHR, sex: profile.sex }, cfg);
    }
    const acwrValue = acwr(trimps);
    trimps.push(load.trimp);
    previousStrain = load.strain;

    // 生病预警（§5.12.1）：连续两晚“注意”→“可能不适”，Recovery 封顶 33，两晚都从基线排除
    const sig = illnessSignals({ tempDelta, zResp, zHRV, rhr: f.rhr.value, rhrStat: stats.restingHeartRate }, cfg);
    const consecutive = previousWake != null && wake - previousWake <= cfg.illness.maxConsecutiveHours * 3600;
    const illness = sig.attention ? (previousAttention && consecutive ? 'possiblyUnwell' : 'attention') : 'none';
    if (illness === 'possiblyUnwell') {
      if (index > 0 && !excluded.has(index - 1)) { excluded.add(index - 1); history.invalidate(index - 1); }
      excluded.add(index);
    }
    previousAttention = sig.attention;
    previousWake = wake;

    const pen = penalties({ zResp, tempDelta, spo2Median: f.spo2Median, breathingElevated: f.breathingElevated });
    const rec = recoveryScore({ zHRV, zRHR, zSleep: ss.zSleep, pen, illnessPossible: illness === 'possiblyUnwell' }, cfg);
    const debtAfter = nextDebt(previousDebt, need.baseNeed, sm.totalSleepHours, cfg);

    // 数据质量（§5.7，分量见 featuresA/B）
    const qc = f.quality.components;
    const qTotal = 0.5 * qc.hrv + 0.2 * qc.hr + 0.2 * qc.sleep + 0.1 * qc.vitals;
    const qLevel = qc.hrv === 0 ? 'none' : qualityLevel(qTotal, cfg);

    // 基线观测：只有质量够、没被排除的夜晚才进入之后的基线（§5.6 第 5 条）
    const values = {
      lnSDNN: f.hrv.value > 0 ? Math.log(f.hrv.value) : null,
      restingHeartRate: f.rhr.value,
      respiratoryRate: f.respiratoryRate,
      wristTemperature: f.wristTemperature,
      oxygenSaturation: f.spo2Median,
      totalSleepHours: sm.totalSleepHours,
      restorativeHours: sm.restorativeHours,
    };
    history.push(values, qc.hrv > 0 && qTotal >= cfg.baselineValidMinQuality[tier] && !excluded.has(index));

    days.push(assembleDay({
      tier, input, cfg, session, wake, until, f, stats, sm, sriValue, need, ss, zRestorative,
      zHRV, zRHR, zResp, tempDelta, load, acwrValue, sig, illness, rec, debtAfter, previousDebt, qTotal, qLevel, excluded: excluded.has(index),
    }));
    previousDebt = debtAfter;
  });

  // 排除可能在下一晚才确定，回写
  days.forEach((d, i) => { d.recovery.excludedFromBaseline = excluded.has(i); });
  return withUnwornDays(days, cfg);
}

function round(x, k = 4) {
  if (x == null || !Number.isFinite(x)) return x ?? null;
  const p = 10 ** k;
  return Math.round(x * p) / p;
}

function statOut(s) {
  return s ? { mu: round(s.mu), sigma: round(s.sigma), n: s.n, calibrating: s.calibrating } : null;
}

function assembleDay(c) {
  const { tier, cfg, session, f, stats, sm, rec } = c;
  const status = rec ? 'ok' : 'no-hrv';
  const tierLabels = [...f.labels];
  if (tier === 'B' || tier === 'H') tierLabels.push('负荷为估算');
  return {
    wakeDay: session.wakeDay,
    tier,
    asOf: c.input.asOf,
    asOfLocal: `${dayKey(c.input.asOf, cfg)} ${hhmm(c.input.asOf, cfg)}`,
    cycle: { sleepStart: session.start, sleepEnd: session.end, bedtime: session.bedtime, until: c.until },
    recovery: {
      status,
      score: round(rec?.score, 2),
      zone: rec?.zone ?? null,
      raw: round(rec?.raw),
      capped: rec?.capped ?? false,
      contradiction: rec?.contradiction ?? false,
      quality: { level: c.qLevel, total: round(c.qTotal, 3), components: Object.fromEntries(Object.entries(f.quality.components).map(([k, v]) => [k, round(v, 3)])), reasons: f.quality.reasons },
      labels: tierLabels,
      inputs: {
        hrvMs: round(f.hrv.value, 2), hrvLabel: f.hrv.label, hrvSamples: f.hrv.samples.map((s) => ({ t: s.t, ms: round(s.ms, 2) })),
        rhr: round(f.rhr.value, 2), rhrSource: f.rhr.source, rhrPoolSize: f.rhr.n,
        respiratoryRate: round(f.respiratoryRate, 2), wristTemperature: round(f.wristTemperature, 3),
        tempDelta: round(c.tempDelta, 3), spo2Median: round(f.spo2Median, 2), breathingElevated: f.breathingElevated,
        sleepHeartRate: f.heartRate,
      },
      baselines: {
        hrvMs: stats.lnSDNN.mu == null ? null : round(Math.exp(stats.lnSDNN.mu), 2),
        lnSDNN: statOut(stats.lnSDNN), restingHeartRate: statOut(stats.restingHeartRate),
        respiratoryRate: statOut(stats.respiratoryRate), wristTemperature: statOut(stats.wristTemperature),
        oxygenSaturation: statOut(stats.oxygenSaturation), restorativeHours: statOut(stats.restorativeHours),
      },
      z: { hrv: round(c.zHRV), rhr: round(c.zRHR), sleep: round(c.ss.zSleep), resp: round(c.zResp) },
      penalties: rec ? Object.fromEntries(Object.entries(rec.penalties).map(([k, v]) => [k, round(v)])) : null,
      contributions: rec ? rec.contributions.map((x) => ({ component: x.component, points: round(x.points, 2) })) : null,
      illness: { level: c.illness, signals: { temp: c.sig.t, resp: c.sig.r, hrv: c.sig.h, rhr: c.sig.hr } },
    },
    sleep: {
      onset: session.start, onsetLocal: hhmm(session.start, cfg), wake: session.end, wakeLocal: hhmm(session.end, cfg),
      bedtime: session.bedtime, bedtimeLocal: session.bedtime == null ? null : hhmm(session.bedtime, cfg),
      tstHours: round(sm.totalSleepHours), efficiency: round(sm.efficiency), efficiencyIsSleepPeriod: sm.efficiencyIsSleepPeriod,
      latencyMinutes: round(sm.sleepLatencyMinutes, 1), wasoMinutes: round(sm.wasoMinutes, 1), awakenings: sm.awakenings,
      restorativeHours: round(sm.restorativeHours), stageMinutes: Object.fromEntries(Object.entries(sm.stageMinutes).map(([k, v]) => [k, round(v, 1)])),
      sri: round(c.sriValue, 2), consistency: c.sriValue == null ? null : round(Math.max(0, c.sriValue), 1),
      need: Object.fromEntries(Object.entries(c.need).map(([k, v]) => [k, round(v)])),
      debtBeforeHours: round(c.previousDebt), debtAfterHours: round(c.debtAfter),
      zRestorative: round(c.zRestorative),
      score: round(c.ss.score, 2), performance: round(c.ss.performance, 2),
      components: Object.fromEntries(Object.entries(c.ss.components).map(([k, v]) => [k, round(v)])),
      hypnogram: tier === 'H' ? null : hypnogram(session.stages, cfg).map((s) => ({ start: s.start, end: s.end, label: s.label })),
    },
    strain: {
      method: c.load.method,
      trimp: round(c.load.trimp, 3), strain: round(c.load.strain, 3),
      countedMinutes: c.load.counted ?? null, unwornMinutes: c.load.unworn ?? null, zoneMinutes: c.load.zones ?? null,
      nonWorkoutTrimp: round(c.load.nonWorkoutTrimp ?? null, 3),
      workouts: c.load.workouts.map((w) => ({ type: w.type, start: w.start, end: w.end, minutes: round(w.minutes, 1), trimp: round(w.trimp, 3), strain: round(w.strain, 2), meanHR: round(w.meanHR, 1), peakHR: round(w.peakHR, 1), zones: w.zones ?? null })),
      acwr: round(c.acwrValue, 3),
      target: rec ? loadTarget(rec.zone, c.acwrValue, cfg) : null,
      curve: c.load.curve ?? null,
      labels: tier === 'B' || tier === 'H' ? ['估算'] : [],
    },
  };
}

/** 没有主睡眠的醒来日：不出恢复分数，显示“昨晚未佩戴”（PRD §2.2 约束 C）。 */
function withUnwornDays(days, cfg) {
  if (!days.length) return days;
  const have = new Set(days.map((d) => d.wakeDay));
  const out = [];
  let t = startOfDayKey(days[0].wakeDay, cfg);
  const last = startOfDayKey(days[days.length - 1].wakeDay, cfg);
  const byDay = new Map(days.map((d) => [d.wakeDay, d]));
  for (; t <= last; t += 86400) {
    const k = dayKey(t + 43200, cfg);
    if (have.has(k)) out.push(byDay.get(k));
    else out.push({ wakeDay: k, tier: days[0].tier, recovery: { status: 'unworn', score: null, zone: null, reasons: ['昨晚未佩戴（没有睡眠记录）'] }, sleep: null, strain: null });
  }
  return out;
}

// —— C 档：只有每日汇总 —————————————————————————————————————————————

export function runDaily(input, cfg = CONFIG) {
  const profile = input.profile;
  const keys = [...input.daily.keys()].filter((k) => input.daily.get(k).sleep).sort();
  const history = new BaselineHistory(profile, cfg);
  const trimps = [];
  const days = [];
  let previousStrain = null;
  let previousDebt = 0;

  keys.forEach((k) => {
    const d = input.daily.get(k);
    const year = Number(k.slice(0, 4));
    const stats = Object.fromEntries(METRICS.map((m) => [m, history.stat(m, year)]));
    const sl = d.sleep;
    const tst = sl.asleepH;
    const efficiency = sl.inBedH ? tst / sl.inBedH : tst + sl.awakeH > 0 ? tst / (tst + sl.awakeH) : null;
    const restorative = sl.deepH + sl.remH;
    const need = sleepNeed({ previousStrain, napHours: 0, previousDebt }, cfg);
    const zRestorative = zScore(restorative, stats.restorativeHours);
    const ss = sleepScore({ tstHours: tst, napCreditHours: 0, needHours: need.total, efficiency, sriValue: null, zRestorative }, cfg);
    const zHRV = d.sdnnMean > 0 ? zScore(Math.log(d.sdnnMean), stats.lnSDNN) : null;
    const zr = zScore(d.restingHR ?? null, stats.restingHeartRate);
    const zRHR = zr == null ? null : -zr;
    const rec = recoveryScore({ zHRV, zRHR, zSleep: ss.zSleep }, cfg);
    const load = dayLoadC({ workoutMinutes: d.workoutMinutes ?? 0, activeKcal: d.activeKcal ?? null, sex: profile.sex }, cfg);
    const acwrValue = acwr(trimps);
    trimps.push(load.trimp);
    previousStrain = load.strain;
    const debtAfter = nextDebt(previousDebt, need.baseNeed, tst, cfg);
    const qc = { hrv: d.sdnnMean != null ? cfg.tierCQuality.hrv : 0, hr: d.restingHR != null ? cfg.tierCQuality.hr : 0, sleep: cfg.tierCQuality.sleep, vitals: 0 };
    const qTotal = 0.5 * qc.hrv + 0.2 * qc.hr + 0.2 * qc.sleep + 0.1 * qc.vitals;
    history.push({
      lnSDNN: d.sdnnMean > 0 ? Math.log(d.sdnnMean) : null, restingHeartRate: d.restingHR ?? null,
      totalSleepHours: tst, restorativeHours: restorative,
    }, qc.hrv > 0 && qTotal >= cfg.baselineValidMinQuality.C);
    days.push({
      wakeDay: k, tier: 'C', asOf: input.asOf, asOfLocal: `${dayKey(input.asOf, cfg)} ${hhmm(input.asOf, cfg)}`,
      recovery: {
        status: rec ? 'ok' : 'no-hrv', score: round(rec?.score, 2), zone: rec?.zone ?? null, raw: round(rec?.raw),
        quality: { level: qc.hrv === 0 ? 'none' : qualityLevel(qTotal, cfg), total: round(qTotal, 3), components: qc, reasons: ['只有每日汇总数据'] },
        labels: ['低精度'],
        inputs: { hrvMs: round(d.sdnnMean, 2), hrvLabel: 'SDNN · 全天平均（含日间读数）', rhr: round(d.restingHR, 2), rhrSource: 'appleDaily' },
        baselines: { hrvMs: stats.lnSDNN.mu == null ? null : round(Math.exp(stats.lnSDNN.mu), 2), lnSDNN: statOut(stats.lnSDNN), restingHeartRate: statOut(stats.restingHeartRate), restorativeHours: statOut(stats.restorativeHours) },
        z: { hrv: round(zHRV), rhr: round(zRHR), sleep: round(ss.zSleep) },
        contributions: rec ? rec.contributions.map((x) => ({ component: x.component, points: round(x.points, 2) })) : null,
      },
      sleep: {
        tstHours: round(tst), efficiency: round(efficiency), restorativeHours: round(restorative),
        stageMinutes: { awake: round(sl.awakeH * 60, 1), rem: round(sl.remH * 60, 1), light: round(sl.lightH * 60, 1), deep: round(sl.deepH * 60, 1) },
        need: Object.fromEntries(Object.entries(need).map(([a, v]) => [a, round(v)])), debtAfterHours: round(debtAfter),
        score: round(ss.score, 2), performance: round(ss.performance, 2), hypnogram: null, labels: ['低精度', '无分期图'],
      },
      strain: { method: load.method, trimp: round(load.trimp, 3), strain: round(load.strain, 3), acwr: round(acwrValue, 3), target: rec ? loadTarget(rec.zone, acwrValue, cfg) : null, labels: ['低精度'] },
    });
    previousDebt = debtAfter;
  });
  return withUnwornDays(days, cfg);
}

/** 入口：按档位计算。 */
export function run(input, cfg = CONFIG) {
  return input.tier === 'C' ? runDaily(input, cfg) : runStaged(input, cfg);
}
