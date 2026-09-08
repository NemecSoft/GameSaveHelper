// ============================================================================
//  gen-app-icon.mjs - 生成 GameSaveHelper 应用图标
//  产出：
//    assets\icon.ico          （生成的恢复包 exe 用）
//    assets\icon-preview.png  （256 预览图，方便人工查看）
//    src\app.ico 由 build.bat 在编译时从 assets\icon.ico 拷贝（主程序图标）
//  图标内容：Fluent 蓝渐变圆角方块 + 白色「存档箱 + 下落箭头」
//  零依赖：PNG 手工编码（zlib + CRC32），ICO = 256(PNG) + 48/32/16(BMP)
// ============================================================================
import fs from 'fs';
import path from 'path';
import zlib from 'zlib';

const S = 2;                       // 超采样倍数：在 512 上画，再缩到 256
const SZ = 256 * S;                // 画布尺寸

// ---------- 几何工具（坐标都用 256 空间，乘 S 使用） ----------
function inRoundedRect(px, py, x0, y0, x1, y1, r) {
    const cx = Math.min(Math.max(px, x0 + r), x1 - r);
    const cy = Math.min(Math.max(py, y0 + r), y1 - r);
    const dx = px - cx, dy = py - cy;
    const insideRect = px >= x0 && px <= x1 && py >= y0 && py <= y1;
    return insideRect && (dx * dx + dy * dy) <= r * r;
}

function inTriangle(px, py, ax, ay, bx, by, cx, cy) {
    const s1 = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
    const s2 = (cx - bx) * (py - by) - (cy - by) * (px - bx);
    const s3 = (ax - cx) * (py - cy) - (ay - cy) * (px - cx);
    return (s1 >= 0 && s2 >= 0 && s3 >= 0) || (s1 <= 0 && s2 <= 0 && s3 <= 0);
}

// 逐点判断颜色：返回 [r,g,b,a]（0-255），a=0 表示透明
function sample(px256, py256) {
    const x = px256 * S, y = py256 * S;

    // 背景：Fluent 蓝垂直渐变圆角方块
    const bgRr = inRoundedRect(x, y, 8 * S, 8 * S, 248 * S, 248 * S, 52 * S);
    if (!bgRr) return [0, 0, 0, 0];
    const t = (py256 - 8) / 240;                       // 渐变进度
    const bg = [
        Math.round(46 + (11 - 46) * t),                // #2E8DE1 -> #0B5CAA
        Math.round(141 + (92 - 141) * t),
        Math.round(225 + (170 - 225) * t),
    ];

    // 白色图形：箭头（杆 + 头）+ 存档箱（坐标乘 S 对齐超采样画布）
    const inShaft = inRoundedRect(x, y, 116 * S, 48 * S, 140 * S, 112 * S, 8 * S);
    const inHead = inTriangle(x, y, 88 * S, 98 * S, 168 * S, 98 * S, 128 * S, 152 * S);
    const inBox = inRoundedRect(x, y, 56 * S, 128 * S, 200 * S, 204 * S, 14 * S);
    if (inShaft || inHead || inBox) return [255, 255, 255, 255];

    // 箱子的"盖缝"：用背景色横带把箱子切成盖和身
    const inSlot = inRoundedRect(x, y, 56 * S, 146 * S, 200 * S, 160 * S, 0);
    if (inSlot) return [bg[0], bg[1], bg[2], 255];

    return [bg[0], bg[1], bg[2], 255];
}

// ---------- 渲染 256（从 512 超采样平均下来） ----------
function render256() {
    const out = new Uint8ClampedArray(256 * 256 * 4);
    for (let y = 0; y < 256; y++) {
        for (let x = 0; x < 256; x++) {
            let r = 0, g = 0, b = 0, a = 0;
            for (let sy = 0; sy < S; sy++) {
                for (let sx = 0; sx < S; sx++) {
                    const [pr, pg, pb, pa] = sample(x + (sx + 0.5) / S, y + (sy + 0.5) / S);
                    r += pr; g += pg; b += pb; a += pa;
                }
            }
            const n = S * S, i = (y * 256 + x) * 4;
            out[i] = r / n; out[i + 1] = g / n; out[i + 2] = b / n; out[i + 3] = a / n;
        }
    }
    return out;
}

// ---------- 区域平均缩放到任意尺寸 ----------
function downscale(src, sw, dw) {
    const out = new Uint8ClampedArray(dw * dw * 4);
    const ratio = sw / dw;
    for (let y = 0; y < dw; y++) {
        for (let x = 0; x < dw; x++) {
            const x0 = Math.floor(x * ratio), x1 = Math.max(x0 + 1, Math.floor((x + 1) * ratio));
            const y0 = Math.floor(y * ratio), y1 = Math.max(y0 + 1, Math.floor((y + 1) * ratio));
            let r = 0, g = 0, b = 0, a = 0, n = 0;
            for (let yy = y0; yy < y1 && yy < sw; yy++) {
                for (let xx = x0; xx < x1 && xx < sw; xx++) {
                    const i = (yy * sw + xx) * 4;
                    r += src[i]; g += src[i + 1]; b += src[i + 2]; a += src[i + 3]; n++;
                }
            }
            const o = (y * dw + x) * 4;
            out[o] = r / n; out[o + 1] = g / n; out[o + 2] = b / n; out[o + 3] = a / n;
        }
    }
    return out;
}

// ---------- PNG 编码（RGBA8） ----------
const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        t[n] = c >>> 0;
    }
    return t;
})();
function crc32(buf) {
    let c = 0xFFFFFFFF;
    for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
}
function chunk(type, data) {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
}
function encodePNG(rgba, w, h) {
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
    ihdr[8] = 8; ihdr[9] = 6;                          // 8bit RGBA
    const raw = Buffer.alloc(h * (1 + w * 4));
    for (let y = 0; y < h; y++) {
        raw[y * (1 + w * 4)] = 0;                      // filter: none
        Buffer.from(rgba.buffer, y * w * 4, w * 4)
              .copy(raw, y * (1 + w * 4) + 1);
    }
    return Buffer.concat([
        Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        chunk('IHDR', ihdr),
        chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
        chunk('IEND', Buffer.alloc(0)),
    ]);
}

// ---------- BMP 图标项（32bit BGRA + 空 AND 掩码，行倒序） ----------
function encodeBmpEntry(rgba, w, h) {
    const hdr = Buffer.alloc(40);
    hdr.writeUInt32LE(40, 0);
    hdr.writeInt32LE(w, 4);
    hdr.writeInt32LE(h * 2, 8);                        // XOR + AND 两倍高
    hdr.writeUInt16LE(1, 12);                          // planes
    hdr.writeUInt16LE(32, 14);                         // bpp
    const maskRow = ((w + 31) >> 5) << 2;
    hdr.writeUInt32LE(w * h * 4 + maskRow * h, 20);
    const px = Buffer.alloc(w * h * 4);
    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
            const si = (y * w + x) * 4;
            const di = ((h - 1 - y) * w + x) * 4;      // 倒序
            px[di] = rgba[si + 2]; px[di + 1] = rgba[si + 1];
            px[di + 2] = rgba[si]; px[di + 3] = rgba[si + 3];
        }
    }
    return Buffer.concat([hdr, px, Buffer.alloc(maskRow * h)]);
}

// ---------- 组装 ICO ----------
const img256 = render256();
const entries = [
    { size: 256, data: encodePNG(img256, 256, 256), isPng: true },
    { size: 48, data: encodeBmpEntry(downscale(img256, 256, 48), 48, 48) },
    { size: 32, data: encodeBmpEntry(downscale(img256, 256, 32), 32, 32) },
    { size: 16, data: encodeBmpEntry(downscale(img256, 256, 16), 16, 16) },
];

const dir = Buffer.alloc(6);
dir.writeUInt16LE(0, 0); dir.writeUInt16LE(1, 2); dir.writeUInt16LE(entries.length, 4);
const offs = [6 + 16 * entries.length];
const dirEntries = entries.map((e, i) => {
    const de = Buffer.alloc(16);
    de[0] = e.size === 256 ? 0 : e.size;
    de[1] = e.size === 256 ? 0 : e.size;
    de[2] = 0; de[3] = 0;
    de.writeUInt16LE(1, 4); de.writeUInt16LE(32, 6);
    de.writeUInt32LE(e.data.length, 8);
    de.writeUInt32LE(offs[i], 12);
    offs.push(offs[i] + e.data.length);
    return de;
});
const ico = Buffer.concat([dir, ...dirEntries, ...entries.map(e => e.data)]);

fs.mkdirSync('d:/AI/nsis/assets', { recursive: true });
fs.writeFileSync('d:/AI/nsis/assets/icon.ico', ico);
fs.writeFileSync('d:/AI/nsis/assets/icon-preview.png', encodePNG(img256, 256, 256));
console.log('icon.ico', ico.length, 'bytes + preview png written');
