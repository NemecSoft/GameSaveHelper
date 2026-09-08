@echo off
REM ============================================================================
REM  build.bat - Compile GameSaveHelper.exe with MSVC (static CRT, single file)
REM  Just double-click this file, or run it from a command prompt.
REM ============================================================================
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "SRCDIR=%ROOT%src"

REM ---------- locate MSVC ----------
set "VCBASE=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC"
if not exist "%VCBASE%" set "VCBASE=C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC"
if not exist "%VCBASE%" set "VCBASE=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC"
if not exist "%VCBASE%" set "VCBASE=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC"
if not exist "%VCBASE%" (
    echo [ERROR] MSVC not found.
    exit /b 3
)

set "VCV="
for /f "delims=" %%i in ('dir /b /o-n "%VCBASE%" 2^>nul') do (
    if not defined VCV set "VCV=%%i"
)
if not defined VCV (
    echo [ERROR] Cannot detect MSVC version.
    exit /b 3
)

REM ---------- locate Windows SDK ----------
set "SDKB=C:\Program Files (x86)\Windows Kits\10"
if not exist "%SDKB%" (
    echo [ERROR] Windows SDK 10 not found.
    exit /b 3
)
set "SDKV="
for /f "delims=" %%i in ('dir /b /o-n "%SDKB%\Include" 2^>nul') do (
    if not defined SDKV set "SDKV=%%i"
)
if not defined SDKV (
    echo [ERROR] Cannot detect Windows SDK version.
    exit /b 3
)

set "VCDIR=%VCBASE%\%VCV%"
echo   MSVC : %VCV%
echo   SDK  : %SDKV%

set "PATH=%VCDIR%\bin\Hostx64\x64;%SDKB%\bin\%SDKV%\x64;%PATH%"
set "INCLUDE=%VCDIR%\include;%SDKB%\Include\%SDKV%\ucrt;%SDKB%\Include\%SDKV%\um;%SDKB%\Include\%SDKV%\shared;%SDKB%\Include\%SDKV%\winrt"
set "LIB=%VCDIR%\lib\x64;%SDKB%\Lib\%SDKV%\ucrt\x64;%SDKB%\Lib\%SDKV%\um\x64"

REM ---------- sync template + icon into src (compiled as resources) ----------
if not exist "%ROOT%template\GameSaveHelper.nsi" (
    echo [ERROR] Missing template: %ROOT%template\GameSaveHelper.nsi
    exit /b 3
)
copy /y "%ROOT%template\GameSaveHelper.nsi" "%SRCDIR%\template.nsi" >nul
REM 主程序图标：优先用 assets\icon.ico（scripts\gen-app-icon.mjs 生成），否则退回 NSIS 自带图标
if exist "%ROOT%assets\icon.ico" (
    copy /y "%ROOT%assets\icon.ico" "%SRCDIR%\app.ico" >nul
) else if exist "%ROOT%nsis\Contrib\Graphics\Icons\modern-install.ico" (
    copy /y "%ROOT%nsis\Contrib\Graphics\Icons\modern-install.ico" "%SRCDIR%\app.ico" >nul
)

pushd "%SRCDIR%"

echo   [1/3] resource...
rc.exe /nologo /fo resource.res resource.rc
if errorlevel 1 (
    echo [ERROR] rc.exe failed
    popd
    exit /b 4
)

echo   [2/3] compile...
cl.exe /nologo /utf-8 /O2 /Oi /GL /Gy /MT /EHsc /std:c++17 /W3 ^
    /DUNICODE /D_UNICODE /DWIN32 /D_WINDOWS /DNDEBUG ^
    /c /Fo:GameSaveHelper.obj GameSaveHelper.cpp
if errorlevel 1 (
    echo [ERROR] cl.exe failed
    popd
    exit /b 4
)

echo   [3/3] link...
link.exe /nologo /LTCG /OPT:REF /OPT:ICF /SUBSYSTEM:WINDOWS /MACHINE:X64 ^
    /OUT:"%ROOT%GameSaveHelper.exe" ^
    GameSaveHelper.obj resource.res ^
    user32.lib gdi32.lib comctl32.lib comdlg32.lib shell32.lib shlwapi.lib ole32.lib advapi32.lib
if errorlevel 1 (
    echo [ERROR] link.exe failed
    popd
    exit /b 4
)

popd

if exist "%ROOT%GameSaveHelper.exe" (
    echo.
    echo   OK: %ROOT%GameSaveHelper.exe
    for %%F in ("%ROOT%GameSaveHelper.exe") do echo   Size: %%~zF bytes
    echo.
    exit /b 0
)

echo [ERROR] exe not produced
exit /b 4
