# 外部枚举运行中安装器的窗口树 v2：GetWindow(GW_CHILD/GW_HWNDNEXT)
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WI {
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public struct RECT { public int L; public int T; public int R; public int B; }
}
"@
$e = Get-ChildItem 'd:\AI\nsis\build\*.exe' |
    Where-Object { $_.Name -like '存档备份【医院666*】_*' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$p = Start-Process $e.FullName -PassThru
Start-Sleep -Seconds 3
$p.Refresh()
$top = $p.MainWindowHandle
if ($top -eq [IntPtr]::Zero) { Stop-Process -Id $p.Id -Force; Write-Output 'no window'; exit 1 }
$sb = New-Object System.Text.StringBuilder 256
[WI]::GetWindowText($top, $sb, 256) | Out-Null
Write-Output ("parent=" + $top + " text=" + $sb.ToString())

function DumpTree([IntPtr]$h, [string]$indent) {
    # GW_CHILD=5 进入子窗口，GW_HWNDNEXT=2 沿 Z 序走
    $c = [WI]::GetWindow($h, 5)
    while ($c -ne [IntPtr]::Zero) {
        $cn = New-Object System.Text.StringBuilder 256
        [WI]::GetClassName($c, $cn, 256) | Out-Null
        $tt = New-Object System.Text.StringBuilder 256
        [WI]::GetWindowText($c, $tt, 256) | Out-Null
        $r = New-Object WI+RECT
        [WI]::GetWindowRect($c, [ref]$r) | Out-Null
        $vis = [WI]::IsWindowVisible($c)
        $txt = $tt.ToString()
        if ($txt.Length -gt 40) { $txt = $txt.Substring(0, 40) }
        Write-Output ("$indent hwnd=$c class=" + $cn.ToString() + " text=" + $txt + " rect=(" + $r.L + "," + $r.T + ")-(" + $r.R + "," + $r.B + ") vis=" + $vis)
        DumpTree $c ($indent + '    ')
        $c = [WI]::GetWindow($c, 2)
    }
}
DumpTree $top ''
Stop-Process -Id $p.Id -Force
Write-Output 'inspect done'
