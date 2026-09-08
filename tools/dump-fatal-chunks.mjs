// 查看指定行区间里的"非标准行"（不属于正常字段/收尾的行）
import fs from 'fs';
const lines = fs.readFileSync('D:/AI/Code/Playnite/Playday/games.json', 'utf8').split(/\r?\n/);
const ranges = [[46840, 47016, '大富翁4'], [108958, 109042, '漫漫长夜']];
for (const [a, b, label] of ranges) {
    console.log(`=== ${a}-${b} ${label} ===`);
    for (let i = a - 1; i < b; i++) {
        const l = lines[i];
        if (!/^\t\t"/.test(l) && l.trim() !== '' && !/^\t\}/.test(l))
            console.log(`第${i + 1}行`, JSON.stringify(l.slice(0, 130)));
    }
}
