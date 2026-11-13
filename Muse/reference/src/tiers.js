// 三档输入：把一份完整的健康快照，降级成 Muse 在 A / B / C 档下“能拿到的数据”的样子。
// 这样同一份数据可以分别按三档计算，量化降档带来的偏差（施工文档 §4）。
// 快照格式：Vigor 的 HealthSnapshot（schema v3），时间为 Unix 秒。
import { CONFIG } from './config.js';
import { buildSessions } from './sleep.js';
import { dayKey } from './time.js';
import { mean } from './stats.js';

/** A 档：带时间戳的逐条样本，原样使用（拿不到逐拍序列 heartbeatSeries）。 */
export function toTierA(snap) {
  return {
    tier: 'A',
    profile: snap.profile,
    rangeStart: snap.rangeStart,
    asOf: snap.rangeEnd,
    sleep: snap.sleep,
    inBed: snap.inBed ?? [],
    heartRate: snap.heartRate.map((s) => ({ date: s.date, bpm: s.bpm })),
    sdnn: snap.hrvSDNN,
    restingHR: snap.restingHeartRate,
    respiratory: snap.respiratoryRate,
    wristTemperature: snap.wristTemperature,
    oxygen: snap.oxygenSaturation,
    breathing: snap.breathingDisturbances ?? [],
    workouts: snap.workouts,
  };
}

function byDay(samples, getT, getV, agg, cfg) {
  const m = new Map();
  for (const s of samples) {
    const k = dayKey(getT(s), cfg);
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(getV(s));
  }
  return new Map([...m].map(([k, v]) => [k, agg(v)]));
}

const sum = (v) => v.reduce((a, b) => a + b, 0);

/**
 * 每日汇总：Apple Health 的“每日平均/总和”口径，按样本开始时间所在的本地自然日归类。
 * SDNN 是全天平均（含日间读数）——这正是 noop 的取法，B/C 档只能拿到这个。
 */
export function dailySummaries(snap, cfg = CONFIG) {
  const days = new Map();
  const put = (field, map) => {
    for (const [k, v] of map) {
      if (!days.has(k)) days.set(k, {});
      days.get(k)[field] = v;
    }
  };
  put('sdnnMean', byDay(snap.hrvSDNN, (s) => s.start, (s) => s.value, mean, cfg));
  put('restingHR', byDay(snap.restingHeartRate, (s) => s.start, (s) => s.value, (v) => v[0], cfg));
  put('respiratoryAvg', byDay(snap.respiratoryRate, (s) => s.start, (s) => s.value, mean, cfg));
  put('wristTemperature', byDay(snap.wristTemperature, (s) => s.end, (s) => s.value, (v) => v[0], cfg));
  put('activeKcal', byDay(snap.activeEnergy ?? [], (s) => s.start, (s) => s.value, sum, cfg));
  put('workoutMinutes', byDay(snap.workouts, (w) => w.start, (w) => (w.end - w.start) / 60, sum, cfg));
  put('workoutKcal', byDay(snap.workouts, (w) => w.start, (w) => w.activeEnergyKilocalories ?? 0, sum, cfg));
  return days;
}

/** 训练记录的汇总字段（Apple 的训练详情里有平均、最高心率）。 */
export function workoutSummaries(snap) {
  const hr = [...snap.heartRate].sort((a, b) => a.date - b.date);
  return snap.workouts.map((w) => {
    const v = hr.filter((s) => s.date >= w.start && s.date <= w.end).map((s) => s.bpm);
    return {
      activityType: w.activityType, start: w.start, end: w.end,
      kcal: w.activeEnergyKilocalories ?? null,
      avgHR: mean(v), maxHR: v.length ? Math.max(...v) : null,
    };
  });
}

/** B 档：睡眠有分期时段（逐段），其余只有每日值；训练只有汇总。 */
export function toTierB(snap, cfg = CONFIG) {
  return {
    tier: 'B',
    profile: snap.profile,
    asOf: snap.rangeEnd,
    sleep: snap.sleep,
    inBed: snap.inBed ?? [],
    daily: dailySummaries(snap, cfg),
    workouts: workoutSummaries(snap),
  };
}

/** C 档：全部只有每日汇总。睡眠只有总时长和各分期总量（归到醒来那天），没有分期时段。 */
export function toTierC(snap, cfg = CONFIG) {
  const daily = dailySummaries(snap, cfg);
  for (const s of buildSessions(snap.sleep, snap.inBed ?? [], cfg).filter((x) => x.kind === 'main')) {
    const st = (name) => s.stages.filter((x) => x.stage === name).reduce((a, x) => a + x.end - x.start, 0) / 3600;
    if (!daily.has(s.wakeDay)) daily.set(s.wakeDay, {});
    daily.get(s.wakeDay).sleep = {
      asleepH: s.asleepSeconds / 3600,
      deepH: st('deep'), remH: st('rem'), lightH: st('core') + st('asleepUnspecified'), awakeH: st('awake'),
      inBedH: s.bedtime != null && s.bedtime <= s.start ? (s.end - s.bedtime) / 3600 : null,
    };
  }
  return { tier: 'C', profile: snap.profile, asOf: snap.rangeEnd, daily };
}
