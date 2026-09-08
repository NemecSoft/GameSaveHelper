@echo off
chcp 65001 >nul
title GameSaveHelper - 构建 Release

REM ============================================================================
REM  build-release.bat - 组装可部署的 release 目录
REM  产物：release\GameSaveHelper.exe + settings.json（配置） + template（模板）
REM        + assets\icon.ico + nsis（编译器，可选）
REM  用法：build-release.bat [gamesJson路径]
REM        第 1 个参数可选，指定 settings.json 里的 games.json 路径
REM  说明：设 SKIP_NSIS=1 可跳过复制 NSIS（几十 MB）
REM ============================================================================

cd /d "%~dp0"
set "REL=release"
set "GAMESJSON=%~1"
if "%GAMESJSON%"=="" set "GAMESJSON=D:\AI\Code\Playnite\Playday\games.json"

echo ==================================================
echo  GameSaveHelper 构建 Release
echo ==================================================

echo [1/4] 编译主程序 ...
call build.bat
if errorlevel 1 goto :fail

echo [2/4] 准备目录 %REL%\ ...
rd /s /q "%REL%" 2>nul
mkdir "%REL%" 2>nul
mkdir "%REL%\template" 2>nul
mkdir "%REL%\assets" 2>nul

echo [3/4] 复制文件 ...
copy /y "GameSaveHelper.exe" "%REL%\" >nul
copy /y "template\GameSaveHelper.nsi" "%REL%\template\" >nul
copy /y "assets\icon.ico" "%REL%\assets\" >nul
copy /y "备份_从配置读取_游戏名.bat" "%REL%\" >nul
if not exist "%REL%\GameSaveHelper.exe" goto :fail

if not "%SKIP_NSIS%"=="1" (
    echo     复制 NSIS 编译器（较大，可 set SKIP_NSIS=1 跳过）...
    robocopy nsis "%REL%\nsis" /E /NFL /NDL /NJH /NJS >nul
    if errorlevel 8 goto :fail
)

echo [4/4] 生成配置文件 settings.json ...
(
echo {
echo   "gamesJson": "%GAMESJSON:\=\\%",
echo   "nsis": "nsis\\makensis.exe",
echo   "outDir": "",
echo   "recurse": "true"
echo }
) > "%REL%\settings.json"

echo.
echo ==================================================
echo  完成！release 目录内容：
echo ==================================================
dir /b "%REL%"
echo.
echo 部署说明：整个 release 文件夹拷到目标机器即可。
echo 如路径有变化，直接编辑 release\settings.json。
exit /b 0

:fail
echo.
echo [ERROR] 构建 release 失败，请检查上面的错误信息。
exit /b 1
