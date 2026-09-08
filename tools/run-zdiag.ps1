# 编译诊断版 -> 运行 3 秒 -> 结束进程
& d:\AI\nsis\nsis\makensis.exe d:\AI\nsis\build\test-diag.nsi | Select-String -Pattern 'Output|Error' | ForEach-Object { $_.Line }
$p = Start-Process 'd:\AI\nsis\build\test-diag.exe' -PassThru
Start-Sleep -Seconds 3
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Output 'run done'
