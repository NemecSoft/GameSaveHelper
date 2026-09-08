# 用 PrintWindow 渲染最新备份包窗口到 PNG（不是屏幕截取，只画目标窗口自身）
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PW {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L; public int T; public int R; public int B; }
}
"@
$e = Get-ChildItem 'd:\AI\nsis\build\*.exe' |
    Where-Object { $_.Name -like '存档备份【医院666*】_*' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
Write-Output ("using " + $e.FullName)
$p = Start-Process $e.FullName -PassThru
Start-Sleep -Seconds 3
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { Stop-Process -Id $p.Id -Force; Write-Output 'no window'; exit 1 }
$r = New-Object PW+RECT
[PW]::GetWindowRect($h, [ref]$r) | Out-Null
$wd = $r.R - $r.L; $ht = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $wd, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
[PW]::PrintWindow($h, $dc, 2) | Out-Null
$g.ReleaseHdc($dc)
$bmp.Save('d:\AI\nsis\build\ui-print.png', [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Stop-Process -Id $p.Id -Force
Write-Output "saved ui-print.png ${wd}x${ht}"
