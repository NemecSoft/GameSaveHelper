// 探测 fluency 风格下可用的图标名称
import fs from 'fs';
const names = ['backup', 'data-recovery', 'cloud-backup', 'database-backup', 'box', 'archive', 'safebox', 'restore', 'hard-disk'];
for (const n of names) {
    const url = `https://img.icons8.com/fluency/256/${n}.png`;
    try {
        const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
        if (res.ok) {
            const buf = Buffer.from(await res.arrayBuffer());
            if (buf[0] === 0x89) {
                fs.writeFileSync(`d:/AI/nsis/assets/candidates/icon-candidate-1.png`, buf);
                console.log(`OK: ${n} -> ${buf.length} bytes`);
                break;
            }
        } else {
            console.log(`${res.status}: ${n}`);
        }
    } catch (e) {
        console.log(`ERR: ${n} ${e.message}`);
    }
}
