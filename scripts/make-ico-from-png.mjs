// ============================================================================
//  make-ico-from-png.mjs - 把候选 PNG 转成多尺寸 ICO（256PNG + 48/32/16 BMP）
//  用法：node make-ico-from-png.mjs <输入.png> <输出.ico> <预览.png>
// ============================================================================
import fs from 'fs';
import zlib from 'zlib';

const [inPng, outIco, outPreview] = process.argv.slice(2);

// ---------------- PNG 解码（8bit，色型 6=RGBA / 2=RGB / 3=调色板） ----------
function decodePNG(buf) {
    if (!(buf[0] === 0x89 && buf[1] === 0x50)) throw new Error('not png');
    let pos = 8, w = 0, h = 0, colorType = 0, bitDepth = 0, interlace = 0;
    const idat = [], plte = [], trns = [];
    while (pos < buf.length) {
        const len = buf.readUInt32BE(pos);
        const type = buf.toString('ascii', pos + 4, pos + 8);
        const data = buf.subarray(pos + 8, pos + 8 + len);
        if (type === 'IHDR') {
            w = data.readUInt32BE(0); h = data.readUInt32BE(4);
            bitDepth = data[8]; colorType = data[9];
            interlace = data[12];
        } else if (type === 'PLTE') plte.push(...data);
        else if (type === 'tRNS') trns.push(...data);
        else if (type === 'IDAT') idat.push(data);
        pos += 12 + len;
    }
    if (bitDepth !== 8) throw new Error('unsupported bitDepth ' + bitDepth);
    if (interlace) throw new Error('interlaced png not supported');
    const channels = { 6: 4, 2: 3, 3: 1 }[colorType];
    if (!channels) throw new Error('unsupported colorType ' + colorType);

    const raw = zlib.inflateSync(Buffer.concat(idat));
    const stride = w * channels;
    const img = new Uint8ClampedArray(w * h * 4);
    let prev = new Uint8Array(stride);
    for (let y = 0; y < h; y++) {
        const f = raw[y * (stride + 1)];
        const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
        const cur = new Uint8Array(stride);
        for (let i = 0; i < stride; i++) {
            const a = i >= channels ? cur[i - channels] : 0;
            const b = prev[i];
            const c = i >= channels ? prev[i - channels] : 0;
            let v = line[i];
            if (f === 1) v += a;
            else if (f === 2) v += b;
            else if (f === 3) v += (a + b) >> 1;
            else if (f === 4) {
                const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
                v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
            }
            cur[i] = v & 0xFF;
        }
        prev = cur;
        for (let x = 0; x < w; x++) {
            const o = (y * w + x) * 4;
            if (colorType === 6) {
                img[o] = cur[x * 4]; img[o + 1] = cur[x * 4 + 1];
                img[o + 2] = cur[x * 4 + 2]; img[o + 3] = cur[x * 4 + 3];
            } else if (colorType === 2) {
                img[o] = cur[x * 3]; img[o + 1] = cur[x * 3 + 1];
                img[o + 2] = cur[x * 3 + 2]; img[o + 3] = 255;
            } else {
                const pi = cur[x] * 3;
                img[o] = plte[pi]; img[o + 1] = plte[pi + 1]; img[o + 2] = plte[pi + 2];
                img[o + 3] = trns.length > x ? trns[x] : 255;
            }
        }
    }
    return { rgba: img, w, h };
}

// ---------------- 尺寸工具 / PNG / BMP 编码（与 gen-app-icon.mjs 一致） ------
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
    ihdr[8] = 8; ihdr[9] = 6;
    const raw = Buffer.alloc(h * (1 + w * 4));
    for (let y = 0; y < h; y++) {
        raw[y * (1 + w * 4)] = 0;
        Buffer.from(rgba.buffer, y * w * 4, w * 4).copy(raw, y * (1 + w * 4) + 1);
    }
    return Buffer.concat([
        Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        chunk('IHDR', ihdr),
        chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
        chunk('IEND', Buffer.alloc(0)),
    ]);
}
function encodeBmpEntry(rgba, w, h) {
    const hdr = Buffer.alloc(40);
    hdr.writeUInt32LE(40, 0);
    hdr.writeInt32LE(w, 4);
    hdr.writeInt32LE(h * 2, 8);
    hdr.writeUInt16LE(1, 12);
    hdr.writeUInt16LE(32, 14);
    const maskRow = ((w + 31) >> 5) << 2;
    hdr.writeUInt32LE(w * h * 4 + maskRow * h, 20);
    const px = Buffer.alloc(w * h * 4);
    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
            const si = (y * w + x) * 4;
            const di = ((h - 1 - y) * w + x) * 4;
            px[di] = rgba[si + 2]; px[di + 1] = rgba[si + 1];
            px[di + 2] = rgba[si]; px[di + 3] = rgba[si + 3];
        }
    }
    return Buffer.concat([hdr, px, Buffer.alloc(maskRow * h)]);
}
function buildICO(img, size) {
    const entries = [
        { size: 256, data: encodePNG(img, 256, 256) },
        { size: 48, data: encodeBmpEntry(downscale(img, size, 48), 48, 48) },
        { size: 32, data: encodeBmpEntry(downscale(img, size, 32), 32, 32) },
        { size: 16, data: encodeBmpEntry(downscale(img, size, 16), 16, 16) },
    ];
    const dir = Buffer.alloc(6);
    dir.writeUInt16LE(0, 0); dir.writeUInt16LE(1, 2); dir.writeUInt16LE(entries.length, 4);
    const offs = [6 + 16 * entries.length];
    const dirEntries = entries.map((e, i) => {
        const de = Buffer.alloc(16);
        de[0] = e.size === 256 ? 0 : e.size;
        de[1] = e.size === 256 ? 0 : e.size;
        de.writeUInt16LE(1, 4); de.writeUInt16LE(32, 6);
        de.writeUInt32LE(e.data.length, 8);
        de.writeUInt32LE(offs[i], 12);
        offs.push(offs[i] + e.data.length);
        return de;
    });
    return Buffer.concat([dir, ...dirEntries, ...entries.map(e => e.data)]);
}

// ---------------- 主流程 ----------------
const { rgba, w, h } = decodePNG(fs.readFileSync(inPng));
if (w !== 256 || h !== 256) throw new Error(`expect 256x256, got ${w}x${h}`);
fs.writeFileSync(outIco, buildICO(rgba, 256));
fs.writeFileSync(outPreview, encodePNG(rgba, 256, 256));
console.log(`${outIco} written`);
