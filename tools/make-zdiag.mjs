// 生成带 Z 序诊断的测试版 NSIS 并编译
// 在铺底+提顶之后写入：页面最顶层子窗口、各控件句柄，运行后读 zdiag.txt 判断提顶是否生效
import fs from 'fs';

let s = fs.readFileSync('d:/AI/nsis/build/医院666-网吧联机版.nsi', 'utf8');

const diag = `
  ; ==================== Z 序诊断（写入 zdiag.txt） ====================
  System::Call "user32::GetTopWindow(p $0)p.r9"
  FileOpen $8 "$EXEDIR\\zdiag.txt" w
  FileWrite $8 "page=$0 top=$9$\\r$\\n"
  FileWrite $8 "head=$hHead$\\r$\\ntitle=$hTitle$\\r$\\nsub=$hSub$\\r$\\nsec=$hSec$\\r$\\ntip=$hTip$\\r$\\nbg=$hBg$\\r$\\n"
  FileWrite $8 "E0=$E0 B0=$B0$\\r$\\nE1=$E1 B1=$B1$\\r$\\nE2=$E2 B2=$B2$\\r$\\n"
  FileClose $8
  ; ====================================================================
`;

const anchor = '  nsDialogs::Show';
if (!s.includes(anchor)) throw new Error('anchor not found');
s = s.replace(anchor, diag + '\n' + anchor);
s = s.replace(/OutFile "[^"]*"/, 'OutFile "d:\\\\AI\\\\nsis\\\\build\\\\test-diag.exe"');
s = s.replace(/^Icon .*\r?\n/m, '');   // 图标路径无所谓，去掉防止引用问题
fs.writeFileSync('d:/AI/nsis/build/test-diag.nsi', s);
console.log('test-diag.nsi written');
