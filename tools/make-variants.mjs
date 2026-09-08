// 生成两个模板变体用于二分定位：
//   test1 = 完全去掉整页白色背景块
//   test2 = 保留背景 label 但去掉压底层的 System::Call
import fs from 'fs';

let s = fs.readFileSync('d:/AI/nsis/build/大富翁11.nsi', 'utf8');

// 变体1：去掉整个背景块（从注释行到 SetWindowPos 行）
const bgBlock = /  ; 整页白色背景[\s\S]*?SetWindowPos[^\r\n]*\r\n/;
let t1 = s.replace(bgBlock, '');
if (t1 === s) console.log('WARN: t1 bgBlock not matched');

// 变体2：只去掉 System::Call 压底层那行
let t2 = s.replace(/  System::Call "user32::SetWindowPos\(p \$hBg[^\r\n]*\r\n/, '');
if (t2 === s) console.log('WARN: t2 call not matched');

t1 = t1.replace(/OutFile "[^"]*"/, 'OutFile "d:\\\\AI\\\\nsis\\\\build\\\\test1.exe"');
t2 = t2.replace(/OutFile "[^"]*"/, 'OutFile "d:\\\\AI\\\\nsis\\\\build\\\\test2.exe"');

fs.writeFileSync('d:/AI/nsis/build/test1.nsi', t1);
fs.writeFileSync('d:/AI/nsis/build/test2.nsi', t2);
console.log('variants ok');
