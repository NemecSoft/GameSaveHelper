// 原样打印指定游戏 savePaths 附近的原始文本
import fs from 'fs';
const s = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8');
const name = process.argv[2] || '影子诡局：被诅咒的海盗';
let pos = 0;
while (true) {
    const i = s.indexOf('\n\t\t"name": "', pos);
    if (i < 0) break;
    const q1 = i + '\n\t\t"name": "'.length - 1;
    const q2 = s.indexOf('"', q1 + 1);
    const nm = s.slice(q1 + 1, q2);
    pos = q2 + 1;
    if (nm !== name) continue;
    const sp = s.indexOf('\n\t\t"savePaths"', q2);
    const limit = s.indexOf('\n\t\t"name": "', q2) < 0 ? s.length : s.indexOf('\n\t\t"name": "', q2);
    if (sp < 0 || sp > limit) { console.log('no savePaths'); break; }
    const rb = s.indexOf(']', sp);
    console.log('RAW savePaths:');
    console.log(JSON.stringify(s.slice(sp, rb + 1)));
    break;
}
