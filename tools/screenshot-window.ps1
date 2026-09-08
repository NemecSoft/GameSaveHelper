param([string]$Exe, [string]$OutPng, [string]$ArgList = "")
# 启动指定 exe，等窗口出来后置顶并截屏窗口区域保存为 png，然后关掉进程
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  public struct RECT { public int L; public int T; public int R; public int B; }
}
"@
if ($ArgList -ne "") {
    $p = Start-Process -FilePath $Exe -ArgumentList $ArgList -PassThru
} else {
    $p = Start-Process -FilePath $Exe -PassThru
}
Start-Sleep -Milliseconds 3500
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { Stop-Process -Id $p.Id -Force; Write-Output "no window"; exit 1 }
# 反复置顶，确保窗口在最前
for ($i = 0; $i -lt 3; $i++) {
    [W]::BringWindowToTop($h) | Out-Null
    [W]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 300
}
Start-Sleep -Milliseconds 500
$r = New-Object W+RECT
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$wd = $r.R - $r.L; $ht = $r.B - $r.T
if ($wd -le 0 -or $ht -le 0) { Stop-Process -Id $p.Id -Force; Write-Output "bad rect"; exit 1 }
$bmp = New-Object System.Drawing.Bitmap $wd, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $wd, $ht))
$bmp.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Stop-Process -Id $p.Id -Force
Write-Output "saved $OutPng ${wd}x${ht}"
