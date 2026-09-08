// 调试：解析漫漫长夜块和它前一个对象，输出真实错误位置
import fs from 'fs';
import * as parser from '@babel/parser';
const lines = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8').split(/\r?\n/);

function chunkBounds(fromLine) {
    // 向上找对象起点 \t{，向下找终点（下一个 \t{ 前）
    let s = fromLine - 1;
    while (s > 0 && !/^\t\{\s*$/.test(lines[s - 1])) s--;
    let e = s;
    while (e + 1 < lines.length && !/^\t\{\s*$/.test(lines[e + 1])) e++;
    return [s, e];
}

const [cs, ce] = chunkBounds(108868);
console.log(`漫漫长夜块：第 ${cs + 1}~${ce + 1} 行`);
const text = lines.slice(cs, ce + 1).join('\n').replace(/,\s*$/, '');
try {
    const ast = parser.parse('(' + text + ')', { sourceType: 'unambiguous', errorRecovery: true });
    console.log('本块可恢复错误数：', (ast.errors || []).length);
    for (const e of ast.errors || []) console.log(`  块内第${e.loc?.line}行列${e.loc?.column} → ${e.message}`);
} catch (e) {
    console.log('致命：', e.message);
}

// 再看前一个对象（108867 往上）
const [ps, pe] = chunkBounds(cs);
console.log(`\n前一个对象：第 ${ps + 1}~${pe + 1} 行（若 pe+1 >= cs 则两块重叠/未收尾）`);
const ptext = lines.slice(ps, pe + 1).join('\n').replace(/,\s*$/, '');
try {
    const ast = parser.parse('(' + ptext + ')', { sourceType: 'unambiguous', errorRecovery: true });
    console.log('本块可恢复错误数：', (ast.errors || []).length);
    for (const e of ast.errors || []) console.log(`  块内第${e.loc?.line}行 → ${e.message}`);
} catch (e) {
    console.log('致命：', e.message);
}
