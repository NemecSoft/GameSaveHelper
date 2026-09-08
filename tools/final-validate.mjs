// 最终校验：严格 JSON.parse + 字段完整性 + 坏结尾检查
import fs from 'fs';
const FILE = 'D:/AI/Code/Playnite/Playday/games.json';
try {
    const j = JSON.parse(fs.readFileSync(FILE, 'utf8'));
    console.log('JSON.parse 严格校验：通过，共', j.length, '个游戏');
    const noName = j.filter(g => !g.name);
    const noSp = j.filter(g => !Array.isArray(g.savePaths));
    console.log('缺 name：', noName.length, '· 缺 savePaths：', noSp.length);
    const badTail = j.filter(g => (g.savePaths || []).some(p => /[\\"]$/.test(p)));
    console.log('路径值末尾仍有反斜杠/引号：', badTail.length);
    const dup = j.length - new Set(j.map(g => g.name)).size;
    console.log('重复游戏名：', dup);
    if (!noName.length && !noSp.length && !badTail.length && !dup) {
        console.log('\n结论：games.json 已完全正确 ✓');
    }
} catch (e) {
    console.log('JSON.parse 失败：', e.message);
}
