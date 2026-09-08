// 用与 C++ 相同的锚点+宽容规则提取 4 个测试游戏的 savePaths，
// 并在 X: 虚拟盘根下创建对应目录结构（医院666 留一个空目录）
import fs from 'fs';
import path from 'path';

const TARGETS = ['双点校园', '影子诡局：被诅咒的海盗', '大富翁11', '医院666-网吧联机版'];
const s = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8');

// 宽容读取字符串（与 C++ ParseJsonStringLenient 相同规则）
function readLenient(str, i) {
    if (str[i] !== '"') return null;
    i++;
    let out = '';
    while (i < str.length) {
        const c = str[i];
        if (c === '\\') {
            if (str[i + 1] === '"') {
                let k = i + 2;
                while (k < str.length && ' \t\r\n'.includes(str[k])) k++;
                if (k >= str.length || ',]}'.includes(str[k])) { out += '\\'; i++; return { v: out, i }; }
            }
            i++;
            const e = str[i++];
            out += ({ n: '\n', r: '\r', t: '\t' }[e] ?? e);
        } else if (c === '"') {
            let k = i + 1;
            while (k < str.length && ' \t\r\n'.includes(str[k])) k++;
            if (k >= str.length || ',]}"'.includes(str[k])) return { v: out, i: i + 1 };
            out += c; i++;
        } else { out += c; i++; }
    }
    return null;
}

const nameKey = '\n\t\t"name": "';
const spKey = '\n\t\t"savePaths"';
let pos = 0;
const found = {};
while (true) {
    const nk = s.indexOf(nameKey, pos);
    if (nk < 0) break;
    const nm = readLenient(s, nk + nameKey.length - 1);
    if (!nm) { pos = nk + 1; continue; }
    pos = nm.i;
    if (!TARGETS.includes(nm.v)) continue;
    const limit = s.indexOf(nameKey, nm.i) < 0 ? s.length : s.indexOf(nameKey, nm.i);
    const sk = s.indexOf(spKey, nm.i);
    if (sk < 0 || sk > limit) { found[nm.v] = []; continue; }
    const lb = s.indexOf('[', sk);
    const rb = s.indexOf(']', lb);
    const paths = [];
    let i = lb + 1;
    while (i < rb) {
        while (i < rb && ' \t\r\n,'.includes(s[i])) i++;
        if (i >= rb || s[i] === ']') break;
        if (s[i] !== '"') { i++; continue; }
        const r = readLenient(s, i);
        if (!r) break;
        i = r.i;
        paths.push(r.v.replace(/[\\\/"]+$/, m => m.length > 1 && r.v.length > 3 ? r.v.slice(-1) === '"' ? r.v.replace(/["]+$/, '') : r.v : r.v).replace(/[\\\/"]+$/, '') || r.v.replace(/[\\\/"]+$/, ''));
    }
    // 简化：直接按 C++ CleanSavePath 规则清洗
    found[nm.v] = paths.map(p => {
        let q = p.trim();
        while (q.length > 3 && /[\\\/"]$/.test(q)) q = q.slice(0, -1);
        return q;
    });
}

const XROOT = process.argv[2] || 'd:/AI/nsis/build/_x';
for (const g of TARGETS) {
    console.log(`\n[${g}]`);
    const ps = found[g];
    if (!ps) { console.log('  未找到'); continue; }
    if (ps.length === 0) { console.log('  savePaths: [] (空)'); continue; }
    ps.forEach((p, idx) => {
        console.log('  ', JSON.stringify(p));
        const dir = p.replace(/\*.*$/, '').replace(/\\$/, '');
        if (/^X:/i.test(dir)) {
            const local = path.join(XROOT, dir.slice(3));
            fs.mkdirSync(local, { recursive: true });
            const emptyIdx = (found['医院666-网吧联机版'] || []).indexOf(p);
            if (!(g === '医院666-网吧联机版' && idx === ps.length - 1)) {
                fs.writeFileSync(path.join(local, 'Save01.sav'), 'save-data-1');
                fs.writeFileSync(path.join(local, 'Save02.sav'), 'save-data-2');
            }
        }
    });
}
console.log('\nX: 结构已建好（医院666 的最后一个位置留空）');
