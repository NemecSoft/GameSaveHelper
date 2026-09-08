@echo off
REM ============================================================================
REM  GameSaveHelper.bat - 兼容转发入口
REM
REM  建议直接用 GameSaveHelper.exe（严格参数检查，不做推断）：
REM      GameSaveHelper.exe 大富翁11 "D:\games\Z\Richman 11\2074800\*.*"
REM      GameSaveHelper.exe 大富翁11            REM 走 config.json 配置
REM
REM  这个 bat 只把参数原样转给 exe：
REM      GameSaveHelper.bat 大富翁11 "D:\...2074800\*.*" "D:\...settings\*.*"
REM ============================================================================
"%~dp0GameSaveHelper.exe" %*
exit /b %ERRORLEVEL%
