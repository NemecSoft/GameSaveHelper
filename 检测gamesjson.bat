@echo off
chcp 65001 >nul
title GameSaveHelper - 检测 games.json

REM ============================================================================
REM  检测gamesjson.bat - 检查 games.json 格式问题并报出行号
REM  结果：屏幕显示 + 完整清单写入 gamesjson-问题清单.txt
REM  用法：直接双击；或带参数指定其他 games.json 路径
REM ============================================================================

cd /d "%~dp0"

set "GAMESJSON=%~1"
if "%GAMESJSON%"=="" set "GAMESJSON=D:\AI\Code\Playnite\Playday\games.json"

if not exist "%GAMESJSON%" (
    echo [ERROR] 找不到文件：%GAMESJSON%
    pause
    exit /b 2
)

node "tools\check-gamesjson.mjs" "%GAMESJSON%"
if errorlevel 1 (
    echo.
    echo [ERROR] 检测脚本运行失败，请确认已安装 node（v18+）。
    pause
    exit /b 1
)

echo.
set /p OPEN=是否打开完整清单（gamesjson-问题清单.txt）？[Y/N]：
if /i "%OPEN%"=="Y" start "" "gamesjson-问题清单.txt"
exit /b 0
