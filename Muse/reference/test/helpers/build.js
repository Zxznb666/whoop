// 测试用的小型数据构造器。时间都是 Unix 秒，本地时区 +08:00。
export const H = 3600;
export const M = 60;
/** 本地时间 → Unix 秒，例如 at('2026-11-10', 23, 30) */
export function at(day, h, m = 0) {
  const [y, mo, d] = day.split('-').map(Number);
  return Date.UTC(y, mo - 1, d, h, m) / 1000 - 8 * H;
}
const watch = { productType: 'Watch7,1', sourceBundleID: 'com.apple.health.watch' };
/** 一晚的分期：segments = [[分期, 分钟], ...]，从 start 开始首尾相接 */
export function night(start, segments, src = watch) {
  const out = [];
  let t = start;
  for (const [stage, min] of segments) {
    out.push({ start: t, end: t + min * M, stage, ...src });
    t += min * M;
  }
  return out;
}
/** 每隔 every 秒一个心率点 */
export function hrSeries(from, to, every, bpm) {
  const out = [];
  for (let t = from; t < to; t += every) out.push({ date: t, bpm: typeof bpm === 'function' ? bpm(t) : bpm });
  return out;
}
/** 标准的 8 小时夜：23:00 入睡，07:00 醒来 */
export const STD_NIGHT = [['core', 90], ['deep', 60], ['rem', 30], ['core', 90], ['awake', 10], ['deep', 30], ['rem', 60], ['core', 110]];

/** 两个日期键之间的天数偏移 */
export function addDays(day, n) {
  const [y, mo, d] = day.split('-').map(Number);
  const t = new Date(Date.UTC(y, mo - 1, d + n));
  return t.toISOString().slice(0, 10);
}

/**
 * 生成一份 A 档输入：从 firstDay 起 n 晚，每晚 23:00 入睡、07:00 醒来（STD_NIGHT）。
 * perNight(i) 可以返回覆盖项：{ skip, sdnn:[ms...], sleepHR, resp, temp, spo2, daytimeSDNN:[ms...], extraHR:[...], workouts:[...] }
 */
export function scenario(firstDay, n, perNight = () => ({})) {
  const input = {
    tier: 'A', profile: { birthYear: 1994, sex: 'male' }, rangeStart: at(firstDay, 12), asOf: at(addDays(firstDay, n), 22),
    sleep: [], inBed: [], heartRate: [], sdnn: [], restingHR: [], respiratory: [], wristTemperature: [], oxygen: [], breathing: [], workouts: [],
  };
  for (let i = 0; i < n; i++) {
    const day = addDays(firstDay, i);
    const wakeDay = addDays(day, 1);
    const o = { sdnn: [55, 60, 65], sleepHR: 52, resp: 14.5, temp: 36.1, spo2: 0.97, ...perNight(i) };
    const bed = at(day, 23);
    const wake = bed + 8 * H;
    // 白天心率：前一天醒来后到入睡，每 5 分钟 70 bpm（第一晚之前没有）
    if (i > 0) input.heartRate.push(...hrSeries(bed - 16 * H, bed, 300, 70));
    if (o.skip) continue;
    input.sleep.push(...night(bed, STD_NIGHT));
    input.heartRate.push(...hrSeries(bed, wake, 300, o.sleepHR));
    [1, 3, 5].forEach((h, k) => { if (o.sdnn[k] != null) input.sdnn.push({ start: at(wakeDay, h), end: at(wakeDay, h) + 60, value: o.sdnn[k] }); });
    (o.daytimeSDNN ?? []).forEach((v, k) => input.sdnn.push({ start: at(wakeDay, 10 + 3 * k), end: at(wakeDay, 10 + 3 * k) + 60, value: v }));
    for (let t = bed; t < wake; t += 300) input.respiratory.push({ start: t, end: t + 300, value: o.resp });
    for (let t = bed; t < wake; t += 1200) input.oxygen.push({ start: t, end: t + 60, value: o.spo2 });
    input.wristTemperature.push({ start: wake - 600, end: wake, value: o.temp });
    input.restingHR.push({ start: wake, end: wake, value: o.sleepHR + 2 });
    if (o.extraHR) input.heartRate.push(...o.extraHR);
    if (o.workouts) input.workouts.push(...o.workouts);
  }
  input.heartRate.sort((a, b) => a.date - b.date);
  input.sdnn.sort((a, b) => a.start - b.start);
  return input;
}
