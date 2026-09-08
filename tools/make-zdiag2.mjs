// 诊断 v2：确认各控件的父窗口到底是谁
import fs from 'fs';

let s = fs.readFileSync('d:/AI/nsis/build/医院666-网吧联机版.nsi', 'utf8');

const diag = `
  ; ==================== Z 序诊断 v2 ====================
  FileOpen $8 "$EXEDIR\\zdiag.txt" w
  FileWrite $8 "page=$0 parent=$HWNDPARENT$\\r$\\n"
  System::Call "user32::GetParent(p $0)p.r9"
  FileWrite $8 "GetParent(page)=$9$\\r$\\n"
  System::Call "user32::GetTopWindow(p $HWNDPARENT)p.r9"
  FileWrite $8 "GetTopWindow(parent)=$9$\\r$\\n"
  System::Call "user32::GetTopWindow(p $0)p.r9"
  FileWrite $8 "GetTopWindow(page)=$9$\\r$\\n"
  System::Call "user32::GetParent(p $hHead)p.r9"
  FileWrite $8 "GetParent(head)=$9$\\r$\\n"
  System::Call "user32::GetParent(p $E0)p.r9"
  FileWrite $8 "GetParent(E0)=$9$\\r$\\n"
  FileClose $8
  ; =====================================================
`;

const anchor = '  nsDialogs::Show';
s = s.replace(anchor, diag + '\n' + anchor);
s = s.replace(/OutFile "[^"]*"/, 'OutFile "d:\\\\AI\\\\nsis\\\\build\\\\test-diag.exe"');
s = s.replace(/^Icon .*\r?\n/m, '');
fs.writeFileSync('d:/AI/nsis/build/test-diag.nsi', s);
console.log('written');
