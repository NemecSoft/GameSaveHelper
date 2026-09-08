// ============================================================================
//  check-gamesjson.mjs - 检测 games.json 格式问题，报出行号（用成熟库 @babel/parser）
//  用法：node tools\check-gamesjson.mjs [games.json路径]
//  输出：控制台摘要 + 完整清单 gamesjson-问题清单.txt
//
//  策略：这个文件坏转义严重，整文件解析会致命中断。所以按游戏对象分块
//  （顶层对象以 "\t{" 开头），每块单独用 babel errorRecovery 解析：
//    - 块内可恢复错误 → 逐条报（行号换算回原文件）
//    - 块内致命错误   → 报出块内所有可疑行（坏转义/多余引号正则）
// ============================================================================
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import * as parser from '@babel/parser';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FILE = process.argv[2] || 'D:/AI/Code/Playnite/Playday/games.json';
const REPORT = path.join(path.dirname(HERE), 'gamesjson-问题清单.txt');

const src = fs.readFileSync(FILE, 'utf8');
const lines = src.split(/\r?\n/);
const lineText = (n) => (n >= 1 && n <= lines.length) ? lines[n - 1].trim().slice(0, 120) : '';

// ---------- 按顶层对象分块：以 "\t{" 开头 ----------
const starts = [];
lines.forEach((l, idx) => { if (/^\t\{\s*$/.test(l)) starts.push(idx); });

const report = [];
function addIssue(line, kind, msg) {
    report.push({ line, kind, msg });
}

// 从块文本里提取游戏名（宽容正则）
function chunkName(text) {
    const m = text.match(/"name"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    if (!m) return '(未知游戏)';
    try { return JSON.parse('"' + m[1] + '"'); } catch { return m[1]; }
}

// 块内可疑行（babel 致命失败时的兜底定位）
function suspiciousLines(chunkLines) {
    const out = [];
    chunkLines.forEach((l, i) => {
        const t = l.trim();
        if (/\\"]\s*$/.test(t))                        // ...*.*\"  → 反斜杠把引号转义了
            out.push({ off: i, kind: '末尾反斜杠坏转义', msg: `路径以 \\" 结尾，收尾引号被转义：${t.slice(0, 100)}` });
        else if (/\\{2}""\s*,?\s*$/.test(t))           // ...*\.*"" → 多余引号
            out.push({ off: i, kind: '多余引号', msg: `路径结尾多了一个引号：${t.slice(0, 100)}` });
        else if ((l.replace(/\\./g, '').match(/"/g) || []).length % 2 === 1)
            out.push({ off: i, kind: '引号不配对', msg: `本行引号数量为奇数（字符串没正常收尾，会吞掉后面的结构）：${t.slice(0, 100)}` });
        else if (/^\t\t\{\s*$/.test(l))
            out.push({ off: i, kind: '结构错乱', msg: `缩进异常的对象开始（2 个 Tab）——疑似对象内容重复或合并：${t.slice(0, 100)}` });
    });
    return out;
}

// 单块检测
function checkChunk(startIdx, endIdx) {
    const chunkLines = lines.slice(startIdx, endIdx + 1);
    const text = chunkLines.join('\n');
    const name = chunkName(text);

    let ast = null;
    try {
        const body = text.replace(/,\s*$/, '');
        ast = parser.parse('(' + body + ')', { sourceType: 'unambiguous', errorRecovery: true });
    } catch (e) {
        // 致命错误：报块范围 + 块内可疑行
        addIssue(startIdx + 1, '语法',
            `「${name}」对象存在严重语法错误（babel: ${e.message.replace(/\s*\(\d+:\d+\)\s*$/, '')}），请检查第 ${startIdx + 1}~${endIdx + 1} 行`);
        for (const s of suspiciousLines(chunkLines))
            addIssue(startIdx + 1 + s.off, s.kind, `「${name}」${s.msg}`);
        if (!/["]savePaths["]/.test(text))
            addIssue(startIdx + 1, '缺字段', `「${name}」对象里没有 savePaths 字段（或对象不完整）`);
        return;
    }

    // 可恢复错误逐条报
    for (const err of ast.errors || []) {
        const off = (err.loc?.line ?? 1) - 1;
        addIssue(startIdx + 1 + off, '语法', `「${name}」${err.message}`);
    }

    // 语义检查：savePaths 元素的已知坏模式
    const walk = (node, fn) => { if (!node || typeof node.type !== 'string') return; fn(node); for (const k of Object.keys(node)) { const v = node[k]; if (Array.isArray(v)) v.forEach(x => walk(x, fn)); else if (v && typeof v === 'object') walk(v, fn); } };
    walk(ast.program, (n) => {
        if (n.type !== 'ArrayExpression' || !n.elements?.length) return;
        // 只看元素都是字符串的数组（savePaths 形态）
        if (!n.elements.every(e => e && e.type === 'StringLiteral')) return;
        for (const el of n.elements) {
            const v = el.value;
            if (/\\$/.test(v))
                addIssue(startIdx + (el.loc?.start?.line ?? 1), '末尾反斜杠',
                    `「${name}」路径以反斜杠结尾（会转义掉收尾引号）："${v}"`);
            if (v.includes('"'))
                addIssue(startIdx + (el.loc?.start?.line ?? 1), '含引号',
                    `「${name}」路径里含引号："${v}"`);
        }
    });
}

for (let i = 0; i < starts.length; i++) {
    let end = (i + 1 < starts.length) ? starts[i + 1] - 1 : lines.length - 1;
    // 最后一块要把文件末尾的根数组收尾行 ] 排除掉
    while (end > starts[i] && /^\]\s*$/.test(lines[end])) end--;
    checkChunk(starts[i], end);
}

// ---------- 输出 ----------
report.sort((a, b) => a.line - b.line);
const badLines = new Set(report.map(r => r.line).filter(Boolean));
const out = [];
out.push(`检测文件：${FILE}`);
out.push(`总行数：${lines.length} · 游戏对象：${starts.length} · 问题：${report.length} 处（涉及 ${badLines.size} 行）`);
out.push('='.repeat(70));
for (const r of report) {
    out.push(`第 ${r.line} 行 [${r.kind}] ${r.msg}`);
    const t = lineText(r.line);
    if (t) out.push(`    > ${t}`);
}
out.push('='.repeat(70));
out.push('修复指引：');
out.push('  [末尾反斜杠坏转义] 行尾的 \\" 会转义掉收尾引号：把行尾 \\" 改成 \\\\"，或删掉路径末尾的反斜杠');
out.push('  [多余引号]         行尾多了个 "，删掉即可');
out.push('  [缺逗号]           两个路径元素之间要有英文逗号');
out.push('  [语法]             babel 提示的常规语法问题，按消息修');
fs.writeFileSync(REPORT, out.join('\r\n'), 'utf8');

console.log(`检测完成：共 ${report.length} 处问题（涉及 ${badLines.size} 行 / ${starts.length} 个游戏对象）`);
console.log(`完整清单已写入：${REPORT}`);
console.log('--- 前 30 条 ---');
for (const l of out.slice(4, 4 + 60)) console.log(l);
