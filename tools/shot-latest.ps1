# 找到 build 目录下最新的备份包 exe，截屏保存到 ui-final.png
$e = Get-ChildItem 'd:\AI\nsis\build\*.exe' |
    Where-Object { $_.Name -like '大富翁11_*' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
Write-Output ("using " + $e.FullName)
& 'd:\AI\nsis\tools\screenshot-window.ps1' -Exe $e.FullName -OutPng 'd:\AI\nsis\build\ui-final.png'
