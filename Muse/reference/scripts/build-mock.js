// 生成视觉样机：把四档（H = Muse 实测档，默认显示）最近 14 天的结果嵌入 mock/template.html，输出单文件 mock/index.html。
// 用法：node scripts/build-mock.js [fixtures 目录]（默认合成数据）
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readSnapshot } from '../src/io.js';
import { toTierA, toTierB, toTierC, toTierH } from '../src/tiers.js';
import { run } from '../src/pipeline.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dir = process.argv[2] ?? join(root, 'fixtures/synthetic-seed42');
const snap = readSnapshot(dir);
const keep = 14;
const tiers = {};
let unwornExample = null;
for (const [k, f] of Object.entries({ H: toTierH, A: toTierA, B: toTierB, C: toTierC })) {
  const all = run(f(snap));
  // H 档的心率曲线是每小时一个点 {t, bpm}，转成样机通用的 [t, bpm]；中间缺的小时补 null 以便断线
  if (k === 'H') for (const d of all) {
    const c = d.strain?.curve;
    if (!c?.length) continue;
    const out = [];
    for (let i = 0; i < c.length; i++) {
      if (i && c[i].t - c[i - 1].t > 3600) out.push([c[i - 1].t + 3600, null]);
      out.push([c[i].t, c[i].bpm]);
    }
    d.strain.curve = out;
  }
  tiers[k] = {
    days: all.filter((d) => d.recovery.status !== 'unworn').slice(-keep),
    history: all.map((d) => ({ wakeDay: d.wakeDay, status: d.recovery.status, score: d.recovery.score, zone: d.recovery.zone })),
  };
  if (k === 'H') unwornExample = all.findLast((d) => d.recovery.status === 'unworn') ?? null;
}
const data = { source: basename(dir) === 'synthetic-seed42' ? 'Vigor 合成场景（seed 42）' : basename(dir), tiers, unwornExample };
const html = readFileSync(join(root, '../mock/template.html'), 'utf8').replace('/*__DATA__*/null', JSON.stringify(data));
const out = join(root, '../mock/index.html');
writeFileSync(out, html);
console.log(`样机已生成：${out}（${Math.round(html.length / 1024)} KB）`);
