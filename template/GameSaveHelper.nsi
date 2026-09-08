; ============================================================================
;  GameSaveHelper - 游戏存档恢复包（单页面 / 一步到位）
;  本文件由 GameSaveHelper.exe 自动生成，请勿手工修改
;  生成时间: @@BUILD_TIME@@
;  如需定制界面，请修改 template\GameSaveHelper.nsi
; ============================================================================

Unicode true
SetCompressor /SOLID lzma
SetCompressorDictSize 32
SetDatablockOptimize on
CRCCheck on
XPStyle on
AllowSkipFiles off
AutoCloseWindow true
RequestExecutionLevel user
BrandingText " "

!include "nsDialogs.nsh"
!include "LogicLib.nsh"
!include "WinMessages.nsh"

; ------------------------- 基本信息（自动填充） -----------------------------
!define PRODUCT_NAME "@@PRODUCT_NAME@@"
!define BACKUP_TIME  "@@BACKUP_TIME@@"
!define BACKUP_STAMP "@@BACKUP_STAMP@@"
!define TOTAL_FILES  "@@TOTAL_FILES@@"
!define TOTAL_SIZE   "@@TOTAL_SIZE@@"
!define PART_COUNT   "@@PART_COUNT@@"

; 现代扁平配色：橘红主色（取自 GameSaveHelper 图标手柄色 #F96534）
; 注意：NSIS 的 SetCtlColors 实测按 0xRRGGBB（网页色序）解析
!define CLR_ACCENT      0xF96534   ; 橘红主色 RGB(249,101,52)
!define CLR_ACCENT_DEEP 0xE2542B   ; 深橘红（横幅右侧拼接） RGB(226,84,43)
!define CLR_TITLE       0xFFFFFF   ; 横幅标题白
!define CLR_SUB         0xFFE0D1   ; 横幅副标题浅暖色 RGB(255,224,209)
!define CLR_TEXT        0x1B1B1B   ; 正文深色
!define CLR_MUTED       0x8A5B4A   ; 提示暖灰 RGB(138,91,74)
!define CLR_EDITBG      0xFFF6F0   ; 输入框暖白 RGB(255,246,240)
!define WND_W           640        ; 窗口宽（像素）
; 窗口高度按存档位置数量动态计算，消除底部大片空白：
;   内容底 ≈ (206 + 18*行数) u，u→像素 ≈ ×1.4，再加标题栏与边距
!define ROWS            @@PART_COUNT@@
!define /math WND_C1    ${ROWS} * 18
!define /math WND_C2    ${WND_C1} + 206
!define /math WND_C3    ${WND_C2} * 14
!define /math WND_C4    ${WND_C3} / 10
!define /math WND_H     ${WND_C4} + 60

@@ICON_LINE@@

Name "${PRODUCT_NAME} 恢复存档 ${BACKUP_TIME}"
Caption "${PRODUCT_NAME} 恢复存档 ${BACKUP_TIME}"
OutFile "@@OUT_FILE@@"
InstallDir "$DESKTOP"

; ------------------------- 变量 ---------------------------------------------
Var hHead
Var hHead2
Var hTitle
Var hSub
Var hBar
Var hSec
Var hTip
Var hBand
Var hFoot
Var hBtnClose
Var hBtnGo
Var OK
Var FAIL
Var REPORT
Var OVERLIST
@@PART_VARS@@

; ========================= 页面（只有一个） =================================
Page custom MainPageCreate MainPageLeave

; ------------------------- 初始化 -------------------------------------------
Function .onInit
  InitPluginsDir
  StrCpy $OK 0
  StrCpy $FAIL 0
  StrCpy $REPORT ""
@@PART_INIT@@
FunctionEnd

; ------------------------- 窗口放大 + 居中 + 内页铺满 ------------------------
Function .onGUIInit
  ; 放大主窗口
  System::Call "user32::SetWindowPos(p $HWNDPARENT, p 0, i 0, i 0, i ${WND_W}, i ${WND_H}, i 4)"
  ; 居中
  System::Call "user32::GetSystemMetrics(i 0)i.r0"
  System::Call "user32::GetSystemMetrics(i 1)i.r1"
  IntOp $2 $0 - ${WND_W}
  IntOp $2 $2 / 2
  IntOp $3 $1 - ${WND_H}
  IntOp $3 $3 / 2
  System::Call "user32::SetWindowPos(p $HWNDPARENT, p 0, i $2, i $3, i 0, i 0, i 0x15)"

  ; 关键：NSIS 放大窗口后内页(1018)不会自动跟随，必须手动铺满客户区，
  ; 否则页面内容会被裁在内页原始尺寸里（这就是之前"界面缺失/不协调"的根源）
  System::Call "*(i 0, i 0, i 0, i 0)p.r1"
  System::Call "user32::GetClientRect(p $HWNDPARENT, p r1)"
  System::Call "*$1(i.r2, i.r3, i.r4, i.r5)"
  GetDlgItem $6 $HWNDPARENT 1018
  System::Call "user32::SetWindowPos(p $6, p 0, i 0, i 0, i $4, i $5, i 4)"

  ; 主窗口自带的三颗按钮全部隐藏，改用页内自建按钮（不会被内页盖住）
  GetDlgItem $6 $HWNDPARENT 1
  ShowWindow $6 ${SW_HIDE}
  GetDlgItem $6 $HWNDPARENT 2
  ShowWindow $6 ${SW_HIDE}
  GetDlgItem $6 $HWNDPARENT 3
  ShowWindow $6 ${SW_HIDE}
FunctionEnd

; ------------------------- 浏览文件夹 ---------------------------------------
Function OnBrowse
  Pop $0
  ${NSD_GetText} $0 $1
  nsDialogs::SelectFolderDialog "选择恢复到的文件夹" "$1"
  Pop $2
  ${If} $2 != "error"
    ${NSD_SetText} $0 "$2"
  ${EndIf}
FunctionEnd

; ------------------------- 页面创建 -----------------------------------------
Function MainPageCreate
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == "error"
    Abort
  ${EndIf}

  ; ============ 内容控件（先创建 = 显示在上层） ============

  ; 顶部橘红横幅（加大到 86u，更有气势）
  ${NSD_CreateLabel} 0 0 100% 86u ""
  Pop $hHead
  SetCtlColors $hHead ${CLR_ACCENT} ${CLR_ACCENT}

  ; 横幅大标题（白字加粗）
  ${NSD_CreateLabel} 16u 22u 90% 18u "${PRODUCT_NAME} 恢复存档"
  Pop $hTitle
  SetCtlColors $hTitle ${CLR_TITLE} ${CLR_ACCENT}
  CreateFont $1 "Microsoft YaHei UI" 16 700
  SendMessage $hTitle ${WM_SETFONT} $1 1

  ; 横幅副标题（浅暖小字）
  ${NSD_CreateLabel} 16u 50u 90% 12u \
    "备份于 ${BACKUP_TIME} · 共 ${PART_COUNT} 个位置 / ${TOTAL_FILES} 个文件（${TOTAL_SIZE}）"
  Pop $hSub
  SetCtlColors $hSub ${CLR_SUB} ${CLR_ACCENT}
  CreateFont $1 "Microsoft YaHei UI" 10 400
  SendMessage $hSub ${WM_SETFONT} $1 1

  ; 正文小节标题（透明背景 + 加粗小标）
  ${NSD_CreateLabel} 16u 96u 90% 12u "恢复到以下位置（可以直接修改）："
  Pop $hSec
  SetCtlColors $hSec ${CLR_TEXT} transparent
  CreateFont $1 "Microsoft YaHei UI" 11 600
  SendMessage $hSec ${WM_SETFONT} $1 1

@@PART_CREATE@@

  ${NSD_CreateLabel} 14u @@TIP_Y@@u 90% 18u \
    "点「恢复存档」开始。若目标位置已有文件，会先问你要不要覆盖。"
  Pop $hTip
  SetCtlColors $hTip ${CLR_MUTED} transparent

  ; 页内按钮：关闭 + 恢复存档（创建后提顶，确保显示在收边条之上）
  ${NSD_CreateButton} 73% @@BTN_Y@@u 12% 22u "关闭"
  Pop $hBtnClose
  ${NSD_OnClick} $hBtnClose OnCloseClick
  System::Call "user32::BringWindowToTop(p $hBtnClose)"
  ${NSD_CreateButton} 86% @@BTN_Y@@u 13% 22u "恢复存档"
  Pop $hBtnGo
  ${NSD_OnClick} $hBtnGo OnGoClick
  System::Call "user32::BringWindowToTop(p $hBtnGo)"

  ; 底部橘色收边条（与横幅呼应；高度超出部分会被页面对话框裁掉）
  ${NSD_CreateLabel} 0 @@BAND_Y@@u 100% 200u ""
  Pop $hBand
  SetCtlColors $hBand ${CLR_ACCENT} ${CLR_ACCENT}

  nsDialogs::Show
FunctionEnd

; ------------------------- 离开页面：读取输入 + 覆盖确认 ---------------------
Function MainPageLeave
@@PART_LEAVE@@

  ; 覆盖检查：列出所有已经有内容的目标位置
  StrCpy $OVERLIST ""
@@PART_OVERWRITE@@
  ${If} $OVERLIST != ""
    MessageBox MB_YESNO|MB_ICONEXCLAMATION|MB_DEFBUTTON2 \
      "下面这些位置里已经有文件了，恢复会覆盖它们：$\r$\n$\r$\n$OVERLIST$\r$\n确定要覆盖吗？" \
      IDYES +2
    Abort
  ${EndIf}

  Call DoRestore

  ${If} $FAIL == 0
    MessageBox MB_OK|MB_ICONINFORMATION \
      "恢复完成，共 $OK 个位置。$\r$\n$\r$\n$REPORT"
  ${Else}
    MessageBox MB_OK|MB_ICONEXCLAMATION \
      "恢复结束：成功 $OK 个，失败 $FAIL 个。$\r$\n$\r$\n$REPORT$\r$\n失败多半是文件正被游戏占用，先关掉游戏再试一次。"
  ${EndIf}

  Quit
FunctionEnd

; ------------------------- 执行恢复 -----------------------------------------
Function DoRestore
  InitPluginsDir
  StrCpy $OK 0
  StrCpy $FAIL 0
  StrCpy $REPORT ""
@@PART_RESTORE@@
FunctionEnd

; ------------------------- 页内按钮点击处理 ---------------------------------
; 页内「关闭」→ 模拟点击主窗口的取消按钮（退出安装器）
Function OnCloseClick
  SendMessage $HWNDPARENT 0x408 2 0
FunctionEnd

; 页内「恢复存档」→ 模拟点击主窗口的下一步按钮（进入恢复流程）
Function OnGoClick
  SendMessage $HWNDPARENT 0x408 1 0
FunctionEnd

; NSIS 需要有 Section 才会生成安装程序本体
; 交互时流程已经在 MainPageLeave 里走完并 Quit 了，这里只处理静默调用：
;   xxx.exe /S            直接恢复到备份时的原位置（不弹窗）
Section "-"
  ${If} ${Silent}
    Call DoRestore
  ${EndIf}
SectionEnd
