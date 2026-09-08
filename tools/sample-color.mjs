// 从 doubao_image_1.png 采样手柄的主色（画面中央的橙红区域）
import fs from 'fs';
import zlib from 'zlib';

function decodePNG(buf) {
    let pos = 8, w = 0, h = 0, ct = 0, bd = 0, il = 0;
    const idat = [], plte = [], trns = [];
    while (pos < buf.length) {
        const len = buf.readUInt32BE(pos);
        const type = buf.toString('ascii', pos + 4, pos + 8);
        const d = buf.subarray(pos + 8, pos + 8 + len);
        if (type === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); bd = d[8]; ct = d[9]; il = d[12]; }
        else if (type === 'PLTE') plte.push(...d);
        else if (type === 'tRNS') trns.push(...d);
        else if (type === 'IDAT') idat.push(d);
        pos += 12 + len;
    }
    if (bd !== 8 || il) throw new Error('unsupported png');
    const ch = { 6: 4, 2: 3, 3: 1 }[ct];
    const raw = zlib.inflateSync(Buffer.concat(idat));
    const stride = w * ch, img = new Uint8ClampedArray(w * h * 4);
    let prev = new Uint8Array(stride);
    for (let y = 0; y < h; y++) {
        const f = raw[y * (stride + 1)];
        const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
        const cur = new Uint8Array(stride);
        for (let i = 0; i < stride; i++) {
            const a = i >= ch ? cur[i - ch] : 0, b = prev[i], c = i >= ch ? prev[i - ch] : 0;
            let v = line[i];
            if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
            else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c); }
            cur[i] = v & 0xFF;
        }
        prev = cur;
        for (let x = 0; x < w; x++) {
            const o = (y * w + x) * 4;
            if (ct === 6) { img[o] = cur[x * 4]; img[o + 1] = cur[x * 4 + 1]; img[o + 2] = cur[x * 4 + 2]; img[o + 3] = cur[x * 4 + 3]; }
            else if (ct === 2) { img[o] = cur[x * 3]; img[o + 1] = cur[x * 3 + 1]; img[o + 2] = cur[x * 3 + 2]; img[o + 3] = 255; }
            else { const p = cur[x] * 3; img[o] = plte[p]; img[o + 1] = plte[p + 1]; img[o + 2] = plte[p + 2]; img[o + 3] = trns.length > x ? trns[x] : 255; }
        }
    }
    return { img, w, h };
}

const { img, w, h } = decodePNG(fs.readFileSync('d:/AI/nsis/assets/doubao_image_1.png'));
// 只统计"橙红"像素：R 明显大于 B 且饱和
let r = 0, g = 0, b = 0, n = 0;
for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4;
        const R = img[i], G = img[i + 1], B = img[i + 2];
        if (R > 170 && R > B + 50 && G < R && G > 40) { r += R; g += G; b += B; n++; }
    }
}
r = Math.round(r / n); g = Math.round(g / n); b = Math.round(b / n);
const hex = (v) => v.toString(16).padStart(2, '0').toUpperCase();
console.log(`采样像素 ${n} 个 → 手柄主色 #${hex(r)}${hex(g)}${hex(b)} (RGB ${r},${g},${b})`);
// NSIS SetCtlColors 用 BGR 十六进制：0xBBGGRR
console.log(`NSIS 写法：0x${hex(b)}${hex(g)}${hex(r)}`);
