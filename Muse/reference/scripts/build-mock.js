// 生成视觉样机：把三档最近 14 天的结果嵌入 mock/template.html，输出单文件 mock/index.html。
// 用法：node scripts/build-mock.js [fixtures 目录]（默认合成数据）
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readSnapshot } from '../src/io.js';
import { toTierA, toTierB, toTierC } from '../src/tiers.js';
import { run } from '../src/pipeline.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dir = process.argv[2] ?? join(root, 'fixtures/synthetic-seed42');
const snap = readSnapshot(dir);
const keep = 14;
const tiers = {};
let unwornExample = null;
for (const [k, f] of Object.entries({ A: toTierA, B: toTierB, C: toTierC })) {
  const all = run(f(snap));
  tiers[k] = {
    days: all.filter((d) => d.recovery.status !== 'unworn').slice(-keep),
    history: all.map((d) => ({ wakeDay: d.wakeDay, status: d.recovery.status, score: d.recovery.score, zone: d.recovery.zone })),
  };
  if (k === 'A') unwornExample = all.findLast((d) => d.recovery.status === 'unworn') ?? null;
}
const data = { source: basename(dir) === 'synthetic-seed42' ? 'Vigor 合成场景（seed 42）' : basename(dir), tiers, unwornExample };
const html = readFileSync(join(root, '../mock/template.html'), 'utf8').replace('/*__DATA__*/null', JSON.stringify(data));
const out = join(root, '../mock/index.html');
writeFileSync(out, html);
console.log(`样机已生成：${out}（${Math.round(html.length / 1024)} KB）`);
