// 诊断 v3：页面真实尺寸 + 最顶层子窗口 + 控件可见性
import fs from 'fs';

let s = fs.readFileSync('d:/AI/nsis/build/医院666-网吧联机版.nsi', 'utf8');

const diag = `
  ; ==================== Z 序诊断 v3 ====================
  System::Call "user32::GetParent(p $hHead)p.r6"      ; 页面对话框句柄
  System::Call "*(i 0, i 0, i 0, i 0)p.r1"
  System::Call "user32::GetWindowRect(p $6, p r1)"
  System::Call "*$1(i.r2, i.r3, i.r4, i.r5)"
  System::Call "user32::GetTopWindow(p $6)p.r9"
  System::Call "user32::IsWindowVisible(p $hHead)i.r10"
  System::Call "user32::IsWindowVisible(p $hTip)i.r11"
  System::Call "user32::IsWindowVisible(p $E2)i.r12"
  FileOpen $8 "$EXEDIR\\zdiag.txt" w
  FileWrite $8 "page=$6 rect=($2,$3)-($4,$5)$\\r$\\n"
  FileWrite $8 "topChild=$9$\\r$\\n"
  FileWrite $8 "head=$hHead visible=$10$\\r$\\n"
  FileWrite $8 "tip=$hTip visible=$11$\\r$\\n"
  FileWrite $8 "E2=$E2 visible=$12$\\r$\\n"
  FileWrite $8 "head==top? $($9 == $hHead)$\\r$\\n"
  FileClose $8
  ; =====================================================
`;

const anchor = '  nsDialogs::Show';
s = s.replace(anchor, diag + '\n' + anchor);
s = s.replace(/OutFile "[^"]*"/, 'OutFile "d:\\\\AI\\\\nsis\\\\build\\\\test-diag.exe"');
s = s.replace(/^Icon .*\r?\n/m, '');
fs.writeFileSync('d:/AI/nsis/build/test-diag.nsi', s);
console.log('written');
