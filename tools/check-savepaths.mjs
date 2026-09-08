// 检查指定游戏的 savePaths 配置
import fs from 'fs';
const games = ['双点校园', '影子诡局：被诅咒的海盗', '大富翁11', '医院666-网吧联机版'];
const s = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8');
// 先修坏转义：\"] -> \\"]
const fixed = s.replace(/\\"]/g, '\\\\"]');
const arr = JSON.parse(fixed);
console.log('total games:', arr.length);
for (const g of games) {
    const hit = arr.filter(x => x.name === g);
    if (hit.length === 0) { console.log(`\n[${g}] 未找到`); continue; }
    for (const x of hit) {
        console.log(`\n[${x.name}] savePaths(${(x.savePaths || []).length}):`);
        (x.savePaths || []).forEach(p => console.log('   ', JSON.stringify(p)));
    }
}
