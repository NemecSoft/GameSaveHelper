// 备份 games.json 并把误删的「大富翁11」条目补回到根数组末尾
import fs from 'fs';

const FILE = 'D:/AI/Code/Playnite/Playday/games.json';
const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
const BAK = FILE + '.bak-' + stamp;

const src = fs.readFileSync(FILE, 'utf8');
fs.writeFileSync(BAK, src, 'utf8');
console.log('已备份：' + BAK);

if (src.includes('"name": "大富翁11"')) {
    console.log('「大富翁11」已存在，无需补回');
    process.exit(0);
}

// 校验当前文件本身是合法 JSON
JSON.parse(src);

const entry = [
    '\t{',
    '\t\t"name": "大富翁11",',
    '\t\t"savePaths": [',
    '\t\t\t"D:\\\\games\\\\Z\\\\Richman 11\\\\2074800\\\\*.*",',
    '\t\t\t"D:\\\\games\\\\Z\\\\Richman 11\\\\settings\\\\*.*"',
    '\t\t]',
    '\t}',
].join('\n');

// 插到最后一个对象收尾 \t} 之后：...\t}  →  ...\t},\n\t{...新条目...}
const closePos = src.lastIndexOf('\n\t}');
if (closePos < 0) throw new Error('找不到最后一个对象的收尾');
const insertAt = closePos + '\n\t}'.length;
const fixed = src.slice(0, insertAt) + ',\n' + entry + src.slice(insertAt);

// 校验修改后的文件合法
const parsed = JSON.parse(fixed);
const hit = parsed.filter(g => g.name === '大富翁11');
if (hit.length !== 1 || hit[0].savePaths.length !== 2) throw new Error('插入后校验失败');

fs.writeFileSync(FILE, fixed, 'utf8');
console.log('已补回「大富翁11」（2 条 savePaths），总条目：' + parsed.length);
