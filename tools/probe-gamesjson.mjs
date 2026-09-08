// 探查 games.json 中指定游戏的对象结构
import fs from 'fs';
const s = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8');
const name = process.argv[2] || '傲气雄鹰：重装上阵';
const i = s.indexOf(name);
console.log('name found at:', i);
if (i >= 0) {
    console.log('ctx before:', JSON.stringify(s.slice(Math.max(0, i - 80), i + name.length + 5)));
    // 找所属对象边界
    const start = s.lastIndexOf('{', i);
    const end = s.indexOf('\n\t}', i);
    const seg = s.slice(start, end + 3);
    const names = (seg.match(/"name"/g) || []).length;
    console.log('"name" count in object:', names);
    const j = seg.indexOf('"savePaths"');
    console.log('savePaths in object at:', j, j >= 0 ? JSON.stringify(seg.slice(j, j + 150)) : '');
}
