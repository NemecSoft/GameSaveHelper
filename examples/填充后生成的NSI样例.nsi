; ============================================================================
;  GameSaveHelper - 游戏存档备份包
;  本文件由 GameSaveHelper.bat -> tools\Build-GameSave.ps1 自动生成
;  生成时间: 2026-09-08 12:36:42
;  *** 请勿手工修改，修改会被下次生成覆盖 ***
;  如需定制外观/流程，请修改 template\GameSaveHelper.nsi
; ============================================================================

Unicode true
SetCompressor /SOLID lzma
SetCompressorDictSize 32
SetDatablockOptimize on
SetOverwrite on
CRCCheck on
XPStyle on
AllowSkipFiles off
AutoCloseWindow false
ShowInstDetails show
RequestExecutionLevel user

!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"

; ---------------------------- 基本信息（自动填充） ---------------------------
!define PRODUCT_NAME "大富翁11"
!define BACKUP_TIME  "2026-09-08 12:36:42"
!define BACKUP_STAMP "20260908_123642"
!define TOTAL_FILES  "4"
!define TOTAL_SIZE   "22 B"
!define PART_COUNT   "3"
!define BACKUP_MODE  "含子目录"

!define MUI_ICON "D:\AI\nsis\nsis\Contrib\Graphics\Icons\modern-install.ico"

Name "${PRODUCT_NAME} ${BACKUP_TIME} 存档备份"
OutFile "D:\AI\nsis\out\大富翁11_存档备份_20260908_123642.exe"
InstallDir "$DESKTOP\${PRODUCT_NAME}_${BACKUP_STAMP}"
BrandingText "GameSaveHelper - ${BACKUP_TIME}"

; ---------------------------- 界面页面 --------------------------------------
!define MUI_WELCOMEPAGE_TITLE "游戏存档备份包"
!define MUI_WELCOMEPAGE_TEXT \
  "本程序包含你在 ${BACKUP_TIME} 备份的游戏存档。$\r$\n$\r$\n\
游戏：${PRODUCT_NAME}$\r$\n\
位置：${PART_COUNT} 个   文件：${TOTAL_FILES} 个   大小：${TOTAL_SIZE}$\r$\n$\r$\n\
点击“下一步”选择还原方式。"
!insertmacro MUI_PAGE_WELCOME

Page custom pgRestoreCreate pgRestoreLeave

!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_TITLE "还原完成"
!define MUI_FINISHPAGE_TEXT "存档已还原完毕。$\r$\n$\r$\n\
注意：如果还原前目标位置已经存在，原位置已被整体重命名为 *.bak_${BACKUP_STAMP}，不会覆盖、不会丢数据。$\r$\n\
确认新存档可用后，再自行删除这些 .bak 文件夹。"
!define MUI_FINISHPAGE_SHOWREADME ""
!define MUI_FINISHPAGE_SHOWREADME_TEXT "打开还原后的文件夹"
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION OpenResultDir
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "SimpChinese"

; ---------------------------- 变量 ------------------------------------------
Var Mode            ; 0 = 还原到原始位置   1 = 还原到指定文件夹
Var DestDir         ; 指定文件夹
Var ResultDir       ; 还原后的第一个目标目录（完成页用）
Var BackupOld       ; 1 = 还原前把已有文件重命名备份
Var hMode0
Var hMode1
Var hDir
Var hBrowse
Var hInfo
Var hTip
Var CB0
Var ST0
Var CB1
Var ST1
Var CB2
Var ST2

; ---------------------------- 初始化 ----------------------------------------
Function .onInit
  InitPluginsDir
  StrCpy $Mode 0
  StrCpy $BackupOld 1
  StrCpy $DestDir "$DESKTOP\${PRODUCT_NAME}_${BACKUP_STAMP}"
  StrCpy $ResultDir ""
  StrCpy $ST0 1
  StrCpy $ST1 1
  StrCpy $ST2 1

  ; 命令行参数支持（NSIS 内置）：/D=<路径>  ->  直接还原到指定文件夹
  ; 可与 /S 静默配合：  xxx.exe /S /D=D:\my\saves
  ${If} $INSTDIR != ""
  ${AndIf} $INSTDIR != "$DESKTOP\${PRODUCT_NAME}_${BACKUP_STAMP}"
    StrCpy $Mode 1
    StrCpy $DestDir $INSTDIR
    StrCpy $R2 $DestDir 1 -1
    ${If} $R2 == "\"          ; 去掉尾部多余的反斜杠
      StrLen $R2 $DestDir
      IntOp $R2 $R2 - 1
      StrCpy $DestDir $DestDir $R2
    ${EndIf}
  ${EndIf}
FunctionEnd

; ---------------------------- 浏览文件夹 ------------------------------------
Function OnBrowse
  Pop $0
  ${NSD_GetText} $hDir $1
  nsDialogs::SelectFolderDialog "请选择还原目标文件夹" "$1"
  Pop $0
  ${If} $0 != "error"
    StrCpy $DestDir $0
    ${NSD_SetText} $hDir "$DestDir"
  ${EndIf}
FunctionEnd

; ---------------------------- 模式切换 --------------------------------------
Function OnModeClick
  Pop $0
  ${If} $0 == $hMode0
    StrCpy $Mode 0
    ${NSD_SetState} $hMode0 ${BST_CHECKED}
    ${NSD_SetState} $hMode1 ${BST_UNCHECKED}
    EnableWindow $hDir 0
    EnableWindow $hBrowse 0
  ${Else}
    StrCpy $Mode 1
    ${NSD_SetState} $hMode0 ${BST_UNCHECKED}
    ${NSD_SetState} $hMode1 ${BST_CHECKED}
    EnableWindow $hDir 1
    EnableWindow $hBrowse 1
  ${EndIf}
FunctionEnd

; ---------------------------- 自定义页：创建 --------------------------------
Function pgRestoreCreate
  !insertmacro MUI_HEADER_TEXT "选择还原方式" "决定把这些存档写回到哪里"

  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == "error"
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 0 100% 24u \
    "游戏：${PRODUCT_NAME}$\r$\n\
备份时间：${BACKUP_TIME}    位置：${PART_COUNT} 个    文件：${TOTAL_FILES} 个（${TOTAL_SIZE}）"
  Pop $hInfo

  ${NSD_CreateLabel} 0 26u 100% 9u "还原到："
  Pop $0
  ${NSD_CreateRadioButton} 4u 36u 96% 10u "备份时的原始位置（推荐）"
  Pop $hMode0
  ${NSD_CreateRadioButton} 4u 47u 96% 10u "我选择的文件夹"
  Pop $hMode1
  ${NSD_CreateText} 14u 58u 74% 13u "$DestDir"
  Pop $hDir
  ${NSD_CreateBrowseButton} 78% 58u 22% 13u "浏览..."
  Pop $hBrowse

  ${NSD_OnClick} $hMode0  OnModeClick
  ${NSD_OnClick} $hMode1  OnModeClick
  ${NSD_OnClick} $hBrowse OnBrowse

  ${If} $Mode == 1
    ${NSD_SetState} $hMode1 ${BST_CHECKED}
    ${NSD_SetState} $hMode0 ${BST_UNCHECKED}
    EnableWindow $hDir 1
    EnableWindow $hBrowse 1
  ${Else}
    ${NSD_SetState} $hMode0 ${BST_CHECKED}
    ${NSD_SetState} $hMode1 ${BST_UNCHECKED}
    EnableWindow $hDir 0
    EnableWindow $hBrowse 0
  ${EndIf}

  ${NSD_CreateLabel} 0 73u 100% 9u "要还原的位置（可多选）："
  Pop $0

  ${NSD_CreateCheckbox} 0 84u 48% 10u "[1] Richman 11\2074800\  (2 个文件, 14 B)"
  Pop $CB0
  ${If} $ST0 == 1
    ${NSD_SetState} $CB0 ${BST_CHECKED}
  ${EndIf}
  ${NSD_CreateCheckbox} 52% 84u 48% 10u "[2] Richman 11\settings\  (1 个文件, 6 B)"
  Pop $CB1
  ${If} $ST1 == 1
    ${NSD_SetState} $CB1 ${BST_CHECKED}
  ${EndIf}
  ${NSD_CreateCheckbox} 0 95u 48% 10u "[3] Richman 11\Mods\  (1 个文件, 2 B)"
  Pop $CB2
  ${If} $ST2 == 1
    ${NSD_SetState} $CB2 ${BST_CHECKED}
  ${EndIf}

  ${NSD_CreateCheckbox} 0 107u 100% 11u "还原前把已存在的同名文件重命名为 .bak_${BACKUP_STAMP}"
  Pop $0
  ${If} $BackupOld == 1
    ${NSD_SetState} $0 ${BST_CHECKED}
  ${EndIf}
  ${NSD_OnClick} $0 OnBackupOldClick

  nsDialogs::Show
FunctionEnd

Function OnBackupOldClick
  Pop $0
  ${NSD_GetState} $0 $BackupOld
FunctionEnd

; ---------------------------- 自定义页：校验 --------------------------------
Function pgRestoreLeave
  ${NSD_GetState} $hMode0 $0
  ${If} $0 == ${BST_CHECKED}
    StrCpy $Mode 0
  ${Else}
    StrCpy $Mode 1
  ${EndIf}

  ${If} $Mode == 1
    ${NSD_GetText} $hDir $DestDir
    ${If} $DestDir == ""
      MessageBox MB_ICONEXCLAMATION|MB_OK "请先选择或填写一个还原目标文件夹。"
      Abort
    ${EndIf}
  ${EndIf}

  StrCpy $R1 0
  ${NSD_GetState} $CB0 $ST0
  ${NSD_GetState} $CB1 $ST1
  ${NSD_GetState} $CB2 $ST2
  IntOp $R1 $R1 + $ST0
  IntOp $R1 $R1 + $ST1
  IntOp $R1 $R1 + $ST2
  ${If} $R1 == 0
    MessageBox MB_ICONEXCLAMATION|MB_OK "请至少勾选一个要还原的位置。"
    Abort
  ${EndIf}
FunctionEnd

; ---------------------------- 完成页：打开文件夹 ----------------------------
Function OpenResultDir
  ${If} $ResultDir != ""
    ExecShell "explore" "$ResultDir"
  ${EndIf}
FunctionEnd

; ---------------------------- 主还原流程 ------------------------------------
Section "-还原存档" SEC_MAIN
  SetDetailsPrint none
  InitPluginsDir
  ; --- 位置 1：Richman 11\2074800 ---
  SetOutPath "$PLUGINSDIR\p0"
  File /r "D:\AI\nsis\_test\Richman 11\2074800\*.*"
  ${If} $ST0 == 1
    ${If} $Mode == 1
      StrCpy $R0 "$DestDir\Richman 11"
    ${Else}
      StrCpy $R0 "D:\AI\nsis\_test\Richman 11\2074800"
    ${EndIf}
    DetailPrint "还原：[1] $R0"
    ${If} $BackupOld == 1
      IfFileExists "$R0\*.*" 0 +2
      Rename "$R0" "$R0.bak_${BACKUP_STAMP}"
    ${EndIf}
    CreateDirectory "$R0"
    CopyFiles /SILENT "$PLUGINSDIR\p0\*.*" "$R0"
    ${If} $ResultDir == ""
      StrCpy $ResultDir "$R0"
    ${EndIf}
  ${EndIf}

  ; --- 位置 2：Richman 11\settings ---
  SetOutPath "$PLUGINSDIR\p1"
  File /r "D:\AI\nsis\_test\Richman 11\settings\*.*"
  ${If} $ST1 == 1
    ${If} $Mode == 1
      StrCpy $R0 "$DestDir\settings"
    ${Else}
      StrCpy $R0 "D:\AI\nsis\_test\Richman 11\settings"
    ${EndIf}
    DetailPrint "还原：[2] $R0"
    ${If} $BackupOld == 1
      IfFileExists "$R0\*.*" 0 +2
      Rename "$R0" "$R0.bak_${BACKUP_STAMP}"
    ${EndIf}
    CreateDirectory "$R0"
    CopyFiles /SILENT "$PLUGINSDIR\p1\*.*" "$R0"
    ${If} $ResultDir == ""
      StrCpy $ResultDir "$R0"
    ${EndIf}
  ${EndIf}

  ; --- 位置 3：Richman 11\Mods ---
  SetOutPath "$PLUGINSDIR\p2"
  File /r "D:\AI\nsis\_test\Richman 11\Mods\*.*"
  ${If} $ST2 == 1
    ${If} $Mode == 1
      StrCpy $R0 "$DestDir\Mods"
    ${Else}
      StrCpy $R0 "D:\AI\nsis\_test\Richman 11\Mods"
    ${EndIf}
    DetailPrint "还原：[3] $R0"
    ${If} $BackupOld == 1
      IfFileExists "$R0\*.*" 0 +2
      Rename "$R0" "$R0.bak_${BACKUP_STAMP}"
    ${EndIf}
    CreateDirectory "$R0"
    CopyFiles /SILENT "$PLUGINSDIR\p2\*.*" "$R0"
    ${If} $ResultDir == ""
      StrCpy $ResultDir "$R0"
    ${EndIf}
  ${EndIf}
  SetDetailsPrint both
  DetailPrint ""
  DetailPrint "全部完成。"
SectionEnd
