// 打印漫漫长夜对象的全部行（带行号），并对比一个正常对象的字段序列
import fs from 'fs';
const lines = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8').split(/\r?\n/);
const [a, b] = [108868, 108952];
console.log(`=== 第 ${a}~${b} 行（漫漫长夜，共 ${b - a + 1} 行）===`);
for (let i = a - 1; i < b; i++) {
    console.log(String(i + 1).padEnd(7), lines[i]);
}
