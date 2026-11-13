// H 档（Muse 实测粒度：每小时汇总 + 整晚睡眠会话总量）的规则测试。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJSON } from '../src/io.js';
import { hourly, toTierH } from '../src/tiers.js';
import { run } from '../src/pipeline.js';
import { sleepMetricsFromTotals, sleepScore } from '../src/sleep.js';
import { at, H, night, hrSeries, addDays } from './helpers/build.js';

/** 一份最小的 Vigor 格式快照：每晚 02:35 → 09:20 入睡（与探测测试夜同形），n 晚。 */
function snapshot(n, perNight = () => ({})) {
  const s = {
    profile: { birthYear: 1994, sex: 'male' }, rangeStart: at('2026-10-01', 12), rangeEnd: at(addDays('2026-10-01', n + 1), 14),
    sleep: [], inBed: [], heartRate: [], hrvSDNN: [], restingHeartRate: [], respiratoryRate: [], oxygenSaturation: [], wristTemperature: [], activeEnergy: [], workouts: [],
  };
  for (let i = 0; i < n; i++) {
    const d = addDays('2026-10-02', i);
    const o = { sdnn: [[2, 10, 30], [3, 0, 47.767362514019496], [9, 0, 88.2904538976683]], ...perNight(i) };
    const onset = at(d, 2, 35);
    s.sleep.push(...night(onset, [['core', 120], ['deep', 98], ['rem', 87], ['core', 96], ['awake', 4]]));
    s.heartRate.push(...hrSeries(onset, onset + 405 * 60, 300, (t) => (t < at(d, 6) ? 54 : 50)));
    s.heartRate.push(...hrSeries(at(d, 10), at(d, 23), 600, 75));
    for (const [h, m, v] of o.sdnn) s.hrvSDNN.push({ start: at(d, h, m), end: at(d, h, m) + 60, value: v });
    for (let h = 3; h <= 9; h++) s.respiratoryRate.push({ start: at(d, h, 5), end: at(d, h, 6), value: 14 }, { start: at(d, h, 35), end: at(d, h, 36), value: 15 });
    for (let h = 3; h <= 9; h += 2) s.oxygenSaturation.push({ start: at(d, h, 10), end: at(d, h, 11), value: 0.97 });
    s.wristTemperature.push({ start: at(d, 2, 40), end: at(d, 9, 20), value: 34.87 });
    s.restingHeartRate.push({ start: at(d, 1), end: at(d, 1), value: 59 });
    for (let h = 10; h < 23; h++) s.activeEnergy.push({ start: at(d, h), end: at(d, h) + 3600, value: 40 });
  }
  return s;
}

test('每小时汇总：按本地整点小时归类，平均或求和', () => {
  const rows = [{ t: at('2026-11-13', 3, 5), v: 40 }, { t: at('2026-11-13', 3, 55), v: 60 }, { t: at('2026-11-13', 4, 0), v: 10 }];
  assert.deepEqual(hourly(rows, (r) => r.t, (r) => r.v), [{ t: at('2026-11-13', 3), value: 50 }, { t: at('2026-11-13', 4), value: 10 }]);
  assert.deepEqual(hourly(rows, (r) => r.t, (r) => r.v, 'sum')[0], { t: at('2026-11-13', 3), value: 100 });
});

test('HRV：只取开始时刻落在睡眠窗口内的小时值；复现探测 P6 的 68.0 ms', () => {
  const days = run(toTierH(snapshot(1)));
  const r = days[0].recovery.inputs;
  // 02:00 那个小时开始于入睡（02:35）之前，不计入；03:00 与 09:00 两个小时值取中位数
  assert.equal(r.hrvSamples.length, 2);
  assert.equal(r.hrvMs, 68.03);
  assert.equal(Math.round(r.hrvMs * 10) / 10, 68.0);
});

test('静息心率：取完整落在睡眠窗口内的小时平均心率的最小值；没有时退回 Apple 每日值', () => {
  const [d] = run(toTierH(snapshot(1)));
  assert.equal(d.recovery.inputs.rhrSource, 'hourlyMin');
  assert.equal(d.recovery.inputs.rhr, 50);
});

test('血氧 0–1 小数换成百分数，呼吸率取小时值中位数，手腕温度取当晚那条', () => {
  const [d] = run(toTierH(snapshot(1)));
  assert.equal(d.recovery.inputs.spo2Median, 97);
  assert.equal(d.recovery.inputs.respiratoryRate, 14.5);
  assert.equal(d.recovery.inputs.wristTemperature, 34.87);
});

test('睡眠只有会话总量：效率 = 睡着 ÷ 会话时长；没有 SRI 时一致性项按比例让出权重', () => {
  const m = sleepMetricsFromTotals({ start: 0, end: 8 * H, asleepSeconds: 7 * H, totals: { deep: H, rem: 1.5 * H, core: 4.5 * H, awake: 0.25 * H } });
  assert.equal(m.efficiency, 7 / 8);
  assert.equal(m.restorativeHours, 2.5);
  assert.equal(m.awakenings, null);
  const s = sleepScore({ tstHours: 7, napCreditHours: 0, needHours: 7, efficiency: 0.95, sriValue: null, zRestorative: 0 });
  // (0.55×1 + 0.15×1 + 0.15×0.5) ÷ 0.85
  assert.ok(Math.abs(s.score - (100 * (0.55 + 0.15 + 0.075)) / 0.85) < 1e-9);
});

test('H 档：没有分期图、标注 HRV 为每小时平均、负荷为估算', () => {
  const days = run(toTierH(snapshot(5)));
  const d = days.at(-1);
  assert.equal(d.sleep.hypnogram, null);
  assert.equal(d.sleep.sri, null);
  assert.ok(d.recovery.labels.includes('HRV 为每小时平均'));
  assert.ok(d.strain.labels.includes('估算'));
  assert.equal(d.strain.method, 'hourly-estimate');
});

test('H 档：睡眠窗口内没有 HRV 小时值 → 不出恢复分数（不编数）', () => {
  const days = run(toTierH(snapshot(3, (i) => (i === 2 ? { sdnn: [[12, 0, 40]] } : {}))));
  assert.equal(days.at(-1).recovery.status, 'no-hrv');
  assert.equal(days.at(-1).recovery.score, null);
});

test('H 档：漏一晚 → 那天显示未佩戴', () => {
  const s = snapshot(3);
  const skip = at('2026-10-03', 0);
  s.sleep = s.sleep.filter((x) => x.start < skip || x.start > skip + 86400);
  const days = run(toTierH(s));
  assert.deepEqual(days.map((d) => d.recovery.status), ['ok', 'unworn', 'ok']);
});

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const snap = readJSON(join(root, 'fixtures/synthetic-seed42/snapshot.json.gz'));

test('H 档合成数据：可重复，且与 golden/synthetic/H.json 一致', () => {
  const a = run(toTierH(snap));
  assert.equal(JSON.stringify(run(toTierH(snap))), JSON.stringify(a));
  const g = readJSON(join(root, 'golden/synthetic/H.json'));
  assert.deepEqual(JSON.parse(JSON.stringify(a.slice(-14))), g.days, 'H 档 golden 变了：确认是有意修改后运行 npm run golden');
});
