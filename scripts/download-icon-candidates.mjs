// ============================================================================
//  download-icon-candidates.mjs - 从 icons8 下载 3 款候选图标（256px PNG）
//  icons8 静态 CDN 按「风格/尺寸/名称」给 URL，免费使用需署名（见输出提示）
// ============================================================================
import fs from 'fs';

const CANDIDATES = [
    { id: 1, name: 'data-backup', style: 'fluency', url: 'https://img.icons8.com/fluency/256/data-backup.png' },
    { id: 2, name: 'archive',     style: 'color',   url: 'https://img.icons8.com/color/256/archive.png' },
    { id: 3, name: 'data-backup', style: 'dusk',    url: 'https://img.icons8.com/dusk/256/data-backup.png' },
];

fs.mkdirSync('d:/AI/nsis/assets/candidates', { recursive: true });

for (const c of CANDIDATES) {
    const file = `d:/AI/nsis/assets/candidates/icon-candidate-${c.id}.png`;
    try {
        const res = await fetch(c.url, { signal: AbortSignal.timeout(20000) });
        if (!res.ok) throw new Error('HTTP ' + res.status);
        const buf = Buffer.from(await res.arrayBuffer());
        if (!(buf[0] === 0x89 && buf[1] === 0x50)) throw new Error('not a PNG');
        fs.writeFileSync(file, buf);
        console.log(`candidate ${c.id} (${c.style}/${c.name}): ${buf.length} bytes -> ${file}`);
    } catch (e) {
        console.log(`candidate ${c.id} (${c.style}/${c.name}) FAILED: ${e.message}`);
    }
}
