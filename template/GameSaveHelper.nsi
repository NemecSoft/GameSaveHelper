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
!include "FileFunc.nsh"

; ------------------------- 基本信息（自动填充） -----------------------------
!define PRODUCT_NAME "@@PRODUCT_NAME@@"
!define BACKUP_TIME  "@@BACKUP_TIME@@"
!define BACKUP_STAMP "@@BACKUP_STAMP@@"
!define TOTAL_FILES  "@@TOTAL_FILES@@"
!define TOTAL_SIZE   "@@TOTAL_SIZE@@"
!define PART_COUNT   "@@PART_COUNT@@"

; 现代扁平配色：微软蓝横幅 + 白色页面
!define CLR_ACCENT  0x0078D4
!define CLR_TITLE   0xFFFFFF
!define CLR_SUB     0xDCEFFB
!define CLR_TEXT    0x1B1B1B
!define CLR_MUTED   0x6F6F6F
!define CLR_WHITE   0xFFFFFF

@@ICON_LINE@@

Name "${PRODUCT_NAME} 恢复存档 ${BACKUP_TIME}"
OutFile "@@OUT_FILE@@"
InstallDir "$DESKTOP"

; ------------------------- 变量 ---------------------------------------------
Var hHead
Var hTitle
Var hSub
Var hTip
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

  ; 顶部微软蓝横幅
  ${NSD_CreateLabel} 0 0 100% 48u ""
  Pop $hHead
  SetCtlColors $hHead ${CLR_ACCENT} ${CLR_ACCENT}

  ; 横幅上的大标题（白字加粗）
  ${NSD_CreateLabel} 12u 7u 90% 14u "${PRODUCT_NAME} 恢复存档"
  Pop $hTitle
  SetCtlColors $hTitle ${CLR_TITLE} ${CLR_ACCENT}
  CreateFont $1 "Microsoft YaHei UI" 13 700
  SendMessage $hTitle ${WM_SETFONT} $1 1

  ; 横幅上的副标题（浅蓝小字）
  ${NSD_CreateLabel} 12u 25u 90% 10u \
    "备份于 ${BACKUP_TIME} · 共 ${PART_COUNT} 个位置 / ${TOTAL_FILES} 个文件（${TOTAL_SIZE}）"
  Pop $hSub
  SetCtlColors $hSub ${CLR_SUB} ${CLR_ACCENT}

  ; 正文小节标题
  ${NSD_CreateLabel} 12u 56u 90% 10u "恢复到以下位置（可以直接修改）："
  Pop $0
  SetCtlColors $0 ${CLR_TEXT} ${CLR_WHITE}

@@PART_CREATE@@

  ${NSD_CreateLabel} 12u @@TIP_Y@@u 90% 18u \
    "点「恢复存档」开始。若目标位置已有文件，会先问你要不要覆盖。"
  Pop $hTip
  SetCtlColors $hTip ${CLR_MUTED} ${CLR_WHITE}

  ; 底部主按钮改成「恢复存档」（正常尺寸），「关闭」藏起「上一步」
  GetDlgItem $0 $HWNDPARENT 1
  SendMessage $0 ${WM_SETTEXT} 0 "STR:恢复存档"
  GetDlgItem $0 $HWNDPARENT 2
  SendMessage $0 ${WM_SETTEXT} 0 "STR:关闭"
  GetDlgItem $0 $HWNDPARENT 3
  ShowWindow $0 ${SW_HIDE}

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

; NSIS 需要有 Section 才会生成安装程序本体
; 交互时流程已经在 MainPageLeave 里走完并 Quit 了，这里只处理静默调用：
;   xxx.exe /S            直接恢复到备份时的原位置（不弹窗）
Section "-"
  ${If} ${Silent}
    Call DoRestore
  ${EndIf}
SectionEnd
