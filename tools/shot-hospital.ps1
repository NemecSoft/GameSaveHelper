# 对最新的医院666 备份包截屏
$e = Get-ChildItem 'd:\AI\nsis\build\*.exe' |
    Where-Object { $_.Name -like '存档备份【医院666*】_*' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
Write-Output ("using " + $e.FullName)
& 'd:\AI\nsis\tools\screenshot-window.ps1' -Exe $e.FullName -OutPng 'd:\AI\nsis\build\ui-orange2.png'
