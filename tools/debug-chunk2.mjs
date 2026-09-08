// 精确解析 108868~108952 行（漫漫长夜）
import fs from 'fs';
import * as parser from '@babel/parser';
const lines = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8').split(/\r?\n/);
const text = lines.slice(108867, 108952).join('\n').replace(/,\s*$/, '');
try {
    const ast = parser.parse('(' + text + ')', { sourceType: 'unambiguous', errorRecovery: true });
    console.log('可恢复错误数：', (ast.errors || []).length);
    for (const e of ast.errors || [])
        console.log(`  原文件第 ${108867 + e.loc.line} 行 列${e.loc.column + 1} → ${e.message}`);
} catch (e) {
    console.log('致命：', e.message);
}
// 同时看前一个对象最后一行和这一块第一行之间
console.log('\n第108866行:', JSON.stringify(lines[108865]));
console.log('第108867行:', JSON.stringify(lines[108866]));
console.log('第108868行:', JSON.stringify(lines[108867]));
