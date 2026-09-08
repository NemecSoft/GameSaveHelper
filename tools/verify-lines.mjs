// 核实实际行号：打印包含关键内容的真实行号
import fs from 'fs';
const lines = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8').split(/\r?\n/);
const keys = ['Hospital666', 'NBA 2K27', 'SparkingZERO\\\\SaveGame', 'HuaLongZ', 'Goldberg UplayEmu'];
for (const k of keys) {
    const re = new RegExp(k.replace(/\\\\/g, '\\\\'));
    lines.forEach((l, i) => {
        if (l.includes(k.replace(/\\\\/g, '\\'))) console.log(`第${i + 1}行: ${l.trim().slice(0, 110)}`);
    });
}
