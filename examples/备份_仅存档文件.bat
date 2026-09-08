@echo off
REM ============================================================================
REM  一键备份存档（方式三：通配符只挑某类文件）
REM  这里只打包 .sav 存档，忽略日志、截图等其它文件。
REM  改成 *.cfg、*.ini 等都行；也可以混合多个路径接着往后写。
REM ============================================================================
setlocal
set "GAME_NAME=我的游戏"
set "SAVE_DIR=D:\games\X\MyGame"

start "" /wait "%~dp0..\GameSaveHelper.exe" "%GAME_NAME%" "%SAVE_DIR%\saves\*.sav"
if errorlevel 1 (
    echo.
    echo [备份失败] 请看程序窗口里的提示。
    pause
)
endlocal
exit /b %ERRORLEVEL%
