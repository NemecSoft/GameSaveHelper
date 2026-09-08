// 从 Playday games.json 抽取前 2 个对象生成最小测试文件
import fs from 'fs';
const s = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8');
// 找前两个顶层对象的边界
const spans = [];
let inStr = false, esc = false, depth = 0, objStart = -1;
for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
        if (esc) esc = false;
        else if (c === '\\') esc = true;
        else if (c === '"') inStr = false;
        continue;
    }
    if (c === '"') { inStr = true; continue; }
    if (c === '{' || c === '[') { depth++; if (c === '{' && depth === 2 && objStart < 0) objStart = i; }
    else if (c === '}' || c === ']') {
        if (c === '}' && depth === 2 && objStart >= 0) { spans.push([objStart, i + 1]); objStart = -1; }
        depth--;
    }
}
console.log('total objects:', spans.length);
const first2 = s.slice(spans[0][0], spans[1][1]);
fs.writeFileSync('d:/AI/nsis/build/test-games.json', '[\n' + first2 + '\n]');
// 打印第一个对象里的 name 和 savePaths 供对照
const seg = s.slice(spans[0][0], spans[0][1]);
console.log('name:', JSON.stringify(seg.slice(seg.indexOf('"name"'), seg.indexOf('"name"') + 40)));
const sp = seg.indexOf('"savePaths"');
console.log('savePaths:', JSON.stringify(seg.slice(sp, sp + 80)));
