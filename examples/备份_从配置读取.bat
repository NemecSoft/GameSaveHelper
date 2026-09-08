@echo off
REM ============================================================================
REM  一键备份存档（方式二：只有游戏名，路径从 config.json 读取）
REM
REM  前提：先在项目根目录的 config.json 里配好该游戏的存档路径，例如：
REM    {
REM      "大富翁11": [
REM        "D:\\games\\Z\\Richman 11\\2074800\\*.*",
REM        "D:\\games\\Z\\Richman 11\\settings\\*.*"
REM      ]
REM    }
REM ============================================================================
setlocal
cd /d "%~dp0.."

REM ↓↓↓ 改成 config.json 里已配置的游戏名 ↓↓↓
start "" /wait "%~dp0..\GameSaveHelper.exe" 大富翁11
if errorlevel 1 (
    echo.
    echo [备份失败] 请检查 config.json 配置，或看程序窗口里的提示。
    pause
)
endlocal
exit /b %ERRORLEVEL%
