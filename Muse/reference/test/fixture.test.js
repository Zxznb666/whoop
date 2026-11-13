// 在 Vigor 合成场景（seed 42，120 晚）上整体验证：与 Vigor 的逐项一致性、可重复性、golden 回归、三档标注。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJSON } from '../src/io.js';
import { toTierA, toTierB, toTierC } from '../src/tiers.js';
import { run } from '../src/pipeline.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const fx = join(root, 'fixtures/synthetic-seed42');
const snap = readJSON(join(fx, 'snapshot.json.gz'));
const vigor = readJSON(join(fx, 'vigor.json'));
const A = run(toTierA(snap));
const B = run(toTierB(snap));
const C = run(toTierC(snap));
const parity = new Map(vigor.parityCycles.map((c) => [c.wakeDay, c]));

function maxDiff(get, ref) {
  let m = 0;
  for (const d of A) {
    const v = parity.get(d.wakeDay);
    if (!v || d.recovery.status === 'unworn') continue;
    const x = get(d); const y = ref(v);
    if (x == null && y == null) continue;
    assert.ok(x != null && y != null, `${d.wakeDay}：一边有值一边没有`);
    m = Math.max(m, Math.abs(x - y));
  }
  return m;
}

test('A 档与 Vigor 的周期一一对应（119 晚 + 1 个未佩戴日）', () => {
  assert.equal(A.filter((d) => d.recovery.status !== 'unworn').length, vigor.cycles.length);
  assert.deepEqual(A.filter((d) => d.recovery.status === 'unworn').map((d) => d.wakeDay), ['2026-08-13']);
});

test('A 档移植一致性：睡眠与生命体征逐项和 Vigor 相同', () => {
  assert.ok(maxDiff((d) => d.sleep.tstHours * 60, (v) => v.tstHours * 60) < 0.01, 'TST');
  assert.ok(maxDiff((d) => d.sleep.efficiency, (v) => v.efficiency) < 1e-4, '效率');
  assert.ok(maxDiff((d) => d.sleep.sri, (v) => v.sri) < 0.01, 'SRI');
  assert.ok(maxDiff((d) => d.recovery.inputs.respiratoryRate, (v) => v.respiratoryRate) < 0.01, '呼吸率');
  assert.ok(maxDiff((d) => d.recovery.inputs.tempDelta, (v) => v.temperatureDelta) < 0.001, '温度偏差');
  assert.ok(maxDiff((d) => d.recovery.inputs.spo2Median, (v) => v.spo2Median) < 0.01, '血氧');
});

test('A 档移植一致性：负荷与睡眠需求的差异在已知范围内', () => {
  // 差异来源：Vigor 在 15–60 分钟空窗用“活动能量 → 心率”回归，Muse 按静息处理（M-07）
  assert.ok(maxDiff((d) => d.strain.strain, (v) => v.strain) < 0.15, 'Strain');
  assert.ok(maxDiff((d) => d.sleep.performance, (v) => v.sleepPerformance) < 0.1, 'Performance');
  assert.ok(maxDiff((d) => d.sleep.score, (v) => v.sleepScore) < 0.1, '睡眠分');
  // 静息心率：Vigor 的样本池还包括逐拍序列的平均心率，Muse 拿不到
  assert.ok(maxDiff((d) => d.recovery.inputs.rhr, (v) => v.rhr) < 1.1, '静息心率');
});

test('可重复：同样的输入两次计算，结果逐字节相同', () => {
  assert.equal(JSON.stringify(run(toTierA(snap))), JSON.stringify(A));
  assert.equal(JSON.stringify(run(toTierC(snap))), JSON.stringify(C));
});

test('golden 回归：重新计算的最近 14 天与 golden/synthetic 完全一致', () => {
  for (const [tier, days] of Object.entries({ A, B, C })) {
    const g = readJSON(join(root, `golden/synthetic/${tier}.json`));
    assert.deepEqual(JSON.parse(JSON.stringify(days.slice(-14))), g.days, `${tier} 档 golden 变了：确认是有意修改后运行 npm run golden`);
  }
});

test('三档标注：B 档 HRV 含日间读数、负荷为估算；C 档低精度、无分期图', () => {
  const b = B.find((d) => d.recovery.status === 'ok');
  assert.ok(b.recovery.labels.includes('HRV 含日间读数'));
  assert.ok(b.strain.labels.includes('估算'));
  const c = C.find((d) => d.recovery.status === 'ok');
  assert.ok(c.recovery.labels.includes('低精度'));
  assert.equal(c.sleep.hypnogram, null);
  assert.equal(c.recovery.quality.level, 'low');
});

test('每个分数都带数据质量和“数据截至”', () => {
  for (const d of [...A, ...B, ...C].filter((x) => x.recovery.status === 'ok')) {
    assert.ok(['high', 'medium', 'low'].includes(d.recovery.quality.level));
    assert.match(d.asOfLocal, /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/);
  }
});
