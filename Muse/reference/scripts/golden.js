// 导出 golden：逐日的每个中间量和最终分数，供 Muse 空间里的数字逐项比对（施工文档 §5 阶段 2、阶段 5）。
// 用法：node scripts/golden.js [fixtures 目录] [天数，默认 14]
//   合成数据：node scripts/golden.js                         → golden/synthetic/
//   真实数据：先用 vigor-export --snapshot 生成 fixtures/<名字>/，再 node scripts/golden.js fixtures/<名字>
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readJSON, readSnapshot } from '../src/io.js';
import { toTierA, toTierB, toTierC } from '../src/tiers.js';
import { run } from '../src/pipeline.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dir = process.argv[2] ?? join(root, 'fixtures/synthetic-seed42');
const keep = Number(process.argv[3] ?? 14);
const name = basename(dir) === 'synthetic-seed42' ? 'synthetic' : basename(dir);
const out = join(root, 'golden', name);
mkdirSync(out, { recursive: true });

const snap = readSnapshot(dir);
const tiers = { A: run(toTierA(snap)), B: run(toTierB(snap)), C: run(toTierC(snap)) };

for (const [tier, days] of Object.entries(tiers)) {
  writeFileSync(join(out, `${tier}.json`), JSON.stringify({ tier, source: name, days: days.slice(-keep) }, null, 1) + '\n');
  // 全部天数的关键列，便于在手机上逐行比对
  const cols = ['wakeDay', 'status', 'recovery', 'zone', 'quality', 'hrvMs', 'hrvBaseline', 'z_hrv', 'rhr', 'rhrBaseline', 'z_rhr', 'resp', 'z_resp', 'tempDelta', 'spo2', 'z_sleep', 'strain', 'trimp', 'tstH', 'needH', 'debtH', 'performance', 'sleepScore', 'sri'];
  const f = (x, k = 2) => (x == null ? '' : typeof x === 'number' ? x.toFixed(k) : String(x));
  const rows = days.map((d) => {
    const r = d.recovery;
    return [d.wakeDay, r.status, f(r.score), r.zone ?? '', r.quality?.level ?? '', f(r.inputs?.hrvMs), f(r.baselines?.hrvMs),
      f(r.z?.hrv, 3), f(r.inputs?.rhr), f(r.baselines?.restingHeartRate?.mu), f(r.z?.rhr, 3), f(r.inputs?.respiratoryRate), f(r.z?.resp, 3),
      f(r.inputs?.tempDelta, 3), f(r.inputs?.spo2Median), f(r.z?.sleep, 3), f(d.strain?.strain), f(d.strain?.trimp), f(d.sleep?.tstHours, 3),
      f(d.sleep?.need?.total, 3), f(d.sleep?.debtAfterHours, 3), f(d.sleep?.performance), f(d.sleep?.score), f(d.sleep?.sri)].join(',');
  });
  writeFileSync(join(out, `${tier}-days.csv`), [cols.join(','), ...rows].join('\n') + '\n');
}
console.log(`golden 已写入 ${out}：A/B/C 各 ${keep} 天详细 JSON + 全部 ${tiers.A.length} 天关键列 CSV`);
