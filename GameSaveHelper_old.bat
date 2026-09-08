chcp 65001 > nul
mode con: cols=91 lines=30
@echo off&title %1存档备份&color 1f
 
cd %~dp0

if "%1"=="" ( 
 color 4f
 @echo 备份失败，参数错误，请联系管理员...
 pause
 exit
)
::☆※＊
::echo ======游戏名称存档路径======
::echo %1
::echo %2
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set datetime=%%a
set YEAR=%datetime:~0,4%
set MONTH=%datetime:~4,2%
set DAY=%datetime:~6,2%
set HOUR=%datetime:~8,2%
set MINUTE=%datetime:~10,2%
set SECOND=%datetime:~12,2%

set sfxname=%YEAR%%MONTH%%DAY%%HOUR%%MINUTE%%SECOND%
::用0替换掉空格
set sfxname=%sfxname: =0%
set dest_path=C:\Users\Administrator\Desktop\
set dest_file=%1—存档%sfxname%.exe

echo Title=%1-游戏存档恢复>"RAR.info"
echo Text>>"RAR.info"
echo {>>"RAR.info"
echo    ^<h2^>%1-游戏存档恢复^</h2^>>>"RAR.info"
echo    ^<ul^>>>"RAR.info"
echo        ^<li^>请点击"<b>解压</b>"进行游戏存档恢复^</li^>>>"RAR.info"
echo        ^<li^>杀毒软件警报请点击"<b>允许</b>"^</li^>>>"RAR.info"
echo    ^</ul^>>>"RAR.info"
echo }>>"RAR.info"
echo Path="%~dp2">>"RAR.info"
echo Overwrite=1 >>"RAR.info"

@echo 正在生成备份......
"..\WinRAR\Rar.exe" a -r -ep1 -m5 -sfx -scfc %dest_path%%dest_file% %2 -zRAR.info -y>nul 
if %errorlevel% == 0 ( 
 color 2f
 @echo 备份成功！
 @echo ===========================================================================================
 @echo 已在桌面生成自解压存档【%dest_file%】
 @echo ===========================================================================================
 @echo 1.保留存档——把以上文件备份到你的网盘、U盘、移动硬盘或微信QQ文件传输助手中即可。 
 @echo 2.使用方法——把备份下载到本电脑，双击一键运行即可恢复存档！
 @echo 3.注意：如果传到微信，微信出于安全会在文件末尾添加.tmp，删除这4个字符，即可双击解压一键恢复
) else (
 color 4f
 @echo 备份失败，没有存档或者存档被锁定了
)
@echo ===========================================================================================
@echo 按任意键即可关闭本窗口...
pause>nul
