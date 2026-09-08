@echo off
REM ============================================================================
REM  一键备份存档（方式一：游戏名 + 存档路径）
REM  产物：桌面\游戏名_年月日_时分秒.exe，双击备份包即可还原
REM
REM  用法：改下面两行 = 你的游戏名 / 存档根目录，然后双击本 bat
REM  路径支持通配符，可以写多个（start 那行接着加引号路径即可，最多 6 个）
REM ============================================================================
setlocal
set "GAME_NAME=大富翁11"
set "SAVE_DIR=D:\games\Z\Richman 11"

start "" /wait "%~dp0..\GameSaveHelper.exe" "%GAME_NAME%" "%SAVE_DIR%\2074800\*.*" "%SAVE_DIR%\settings\*.*"
if errorlevel 1 (
    echo.
    echo [备份失败] 请看程序窗口里的提示。
    pause
)
endlocal
exit /b %ERRORLEVEL%
