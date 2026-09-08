@echo off
chcp 65001 >nul
title GameSaveHelper - 推送到 GitHub

cd /d "%~dp0"

set "REPO_URL=https://github.com/NemecSoft/GameSaveHelper.git"

echo ==================================================
echo  GameSaveHelper 推送到 GitHub
echo  仓库: %REPO_URL%
echo ==================================================
echo.

REM ---------- 1. 初始化仓库（已初始化则跳过） ----------
if not exist ".git" (
    echo [1/5] git init ...
    git init
    if errorlevel 1 goto :fail
) else (
    echo [1/5] 已经是 git 仓库，跳过 init
)

REM ---------- 2. 添加全部文件（.gitignore 排除了编译产物） ----------
echo [2/5] git add ...
git add -A
if errorlevel 1 goto :fail

REM ---------- 3. 提交（有暂存变更才提交，重复运行不会产生空提交） ----------
echo [3/5] git commit ...
git diff --cached --quiet
if errorlevel 1 (
    git commit -m "更新 %date% %time%"
    if errorlevel 1 goto :fail
) else (
    echo        没有新的变更需要提交
)

REM ---------- 4. 分支名改为 main，配置远程仓库 ----------
echo [4/5] 配置分支 main 和远程仓库 ...
git branch -M main 2>nul
git remote get-url origin >nul 2>&1
if errorlevel 1 (
    git remote add origin "%REPO_URL%"
    if errorlevel 1 goto :fail
) else (
    git remote set-url origin "%REPO_URL%"
)

REM ---------- 5. 推送 ----------
echo [5/5] git push ...
git push -u origin main
if errorlevel 1 goto :fail

echo.
echo ==================================================
echo  完成！已推送到 %REPO_URL%
echo ==================================================
pause
exit /b 0

:fail
echo.
echo 推送失败，请检查上面的错误信息。
echo 常见原因：没装 git / 网络·代理不通 / GitHub 未登录授权（首次 push 会弹浏览器登录）。
pause
exit /b 1
