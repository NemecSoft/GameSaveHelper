@echo off
chcp 65001 >nul
title GameSaveHelper - 从配置读取备份

REM ============================================================================
REM  备份_从配置读取_游戏名.bat
REM  用法：备份_从配置读取_游戏名.bat 游戏名
REM  说明：游戏名必须和配置文件（games.json / config.json）里的 name 一致，
REM        存档路径从配置读取，备份包生成到桌面（可用 /out: 改）。
REM  示例：备份_从配置读取_游戏名.bat 大富翁11
REM ============================================================================

if "%~1"=="" (
    echo 用法：%~nx0 游戏名
    echo 示例：%~nx0 大富翁11
    echo.
    echo 可选参数：
    echo   /config:文件路径   指定配置文件（默认自动查找 games.json / config.json）
    echo   /out:目录          指定备份输出目录（默认桌面）
    echo   /q                 静默模式（不出窗口，方便脚本调用）
    pause
    exit /b 2
)

cd /d "%~dp0"
"GameSaveHelper.exe" %*
exit /b %ERRORLEVEL%
