# =============================================================================
#  Build-GameSave.ps1  -  GameSaveHelper 的生成器
#
#  作用：把一个 / 多个「目录 + 通配符」参数，动态填充到
#        template\GameSaveHelper.nsi 模板中，再调用 makensis.exe 编译出一个
#        自解压式的「游戏存档备份包 exe」。
#
#  由 GameSaveHelper.bat 调用，也可以直接运行：
#    powershell -File tools\Build-GameSave.ps1 "D:\games\X\saves\*.*" "D:\games\X\cfg\*.ini"
#
#  注意：本文件必须保存为 UTF-8 with BOM，否则 Windows PowerShell 5.1
#        会按 ANSI 解析其中的中文，导致输出乱码。
# =============================================================================

[CmdletBinding()]
param(
    # 命令行剩余参数：混合了「源路径」和「选项」，下面自行分拣
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $RawArgs
)

# -----------------------------------------------------------------------------
# 0. 基础环境
# -----------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try { $OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$TemplateFile = Join-Path $RootDir 'template\GameSaveHelper.nsi'
$BuildDir     = Join-Path $RootDir 'build'
$OutDir       = Join-Path $RootDir 'out'
$MaxParts     = 8

function Write-Step([string]$msg) { Write-Host "  $msg" -ForegroundColor Gray }
function Write-Ok([string]$msg)   { Write-Host "  $msg" -ForegroundColor Green }
function Write-Warn2([string]$msg){ Write-Host "  [警告] $msg" -ForegroundColor Yellow }
function Write-Err2([string]$msg) { Write-Host "  [错误] $msg" -ForegroundColor Red }

function Show-Usage {
    Write-Host ''
    Write-Host '用法：' -ForegroundColor Cyan
    Write-Host '  GameSaveHelper.bat "路径1\*.*" ["路径2\*.*" ...] [选项]' -ForegroundColor White
    Write-Host ''
    Write-Host '示例：' -ForegroundColor Cyan
    Write-Host '  GameSaveHelper.bat "D:\games\Z\Richman 11\2074800\*.*"' -ForegroundColor White
    Write-Host '  GameSaveHelper.bat "D:\games\Z\Richman 11\2074800\*.*" "D:\games\Z\Richman 11\settings\*.*"' -ForegroundColor White
    Write-Host '  GameSaveHelper.bat "D:\g\X\saves\*.sav" -name "我的存档" -out "D:\backup"' -ForegroundColor White
    Write-Host ''
    Write-Host '选项：' -ForegroundColor Cyan
    Write-Host '  -name "名称"    指定备份包名称（默认从路径自动推断）' -ForegroundColor White
    Write-Host '  -out  "目录"    指定 exe 输出目录（默认 .\out）' -ForegroundColor White
    Write-Host '  -norecurse      只取当前目录，不含子目录（默认含子目录）' -ForegroundColor White
    Write-Host '  -keepnsi        保留生成的 .nsi 脚本便于排查' -ForegroundColor White
    Write-Host '  -help           显示本帮助' -ForegroundColor White
    Write-Host ''
}

# -----------------------------------------------------------------------------
# 1. 参数分拣
# -----------------------------------------------------------------------------
if (-not $RawArgs -or $RawArgs.Count -eq 0) { Show-Usage; Write-Err2 '缺少参数：至少需要一个带通配符的源路径。'; exit 2 }

$srcArgs   = New-Object System.Collections.ArrayList
$optName   = $null
$optOut    = $null
$recurse   = $true
$keepNsi   = $false

for ($i = 0; $i -lt $RawArgs.Count; $i++) {
    $raw = $RawArgs[$i]
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }

    if ($raw -match '^[-/](.+)$') {
        $t = $Matches[1].Trim()

        # 支持 -name:xxx / -name xxx 两种写法
        if ($t -match '^(name|n)[:=](.*)$')        { $optName = $Matches[2].Trim('"') ; continue }
        if ($t -match '^(out|o)[:=](.*)$')         { $optOut  = $Matches[2].Trim('"') ; continue }
        if ($t -match '^(help|h|\?)$')             { Show-Usage; exit 0 }
        if ($t -match '^(norecurse|nr)$')          { $recurse = $false ; continue }
        if ($t -match '^(keepnsi|k)$')             { $keepNsi = $true  ; continue }

        if ($t -match '^(name|n)$')  { $i++; $optName = $RawArgs[$i].Trim('"') ; continue }
        if ($t -match '^(out|o)$')   { $i++; $optOut  = $RawArgs[$i].Trim('"') ; continue }

        Write-Warn2 "忽略无法识别的选项：-$t"
        continue
    }
    [void]$srcArgs.Add($raw)
}

if ($srcArgs.Count -eq 0) { Show-Usage; Write-Err2 '没有指定任何源路径。'; exit 2 }
if ($srcArgs.Count -gt $MaxParts) { Write-Err2 "最多支持 $MaxParts 个路径，当前 $($srcArgs.Count) 个。"; exit 2 }

# -----------------------------------------------------------------------------
# 2. 解析每个路径：拆成「目录 + 通配符」，并统计文件
# -----------------------------------------------------------------------------
function Get-SizeText([long]$bytes) {
    if ($bytes -lt 1KB) { return "$bytes B" }
    if ($bytes -lt 1MB) { return "{0:N1} KB" -f ($bytes / 1KB) }
    if ($bytes -lt 1GB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N2} GB" -f ($bytes / 1GB)
}

# NSIS 字符串转义：$ " ` 三个字符在 NSIS 里有特殊含义
function ConvertTo-NsisString([string]$s) {
    if ($null -eq $s) { return '' }
    return $s.Replace('$', '$$').Replace('"', '$"').Replace('`', '$`')
}

# 合法化文件名
function ConvertTo-SafeFileName([string]$s) {
    $bad = [IO.Path]::GetInvalidFileNameChars()
    $out = ''
    foreach ($ch in $s.ToCharArray()) {
        if ($bad -contains $ch) { $out += '_' } else { $out += $ch }
    }
    return $out.Trim().TrimEnd('.', ' ')
}

$parts = New-Object System.Collections.ArrayList

foreach ($arg in $srcArgs) {
    $p = $arg.Trim().Trim('"')

    $leaf = Split-Path $p -Leaf
    if ($leaf -match '[*?]') {
        $dir = Split-Path $p -Parent
        $pat = $leaf
    } else {
        # 没有通配符：把整个参数当作目录
        $dir = $p.TrimEnd('\', '/')
        $pat = '*.*'
    }

    if ([string]::IsNullOrWhiteSpace($dir)) { Write-Err2 "无法解析路径：$arg"; exit 2 }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Write-Err2 "目录不存在：$dir"
        exit 2
    }
    $dir = (Resolve-Path -LiteralPath $dir).ProviderPath.TrimEnd('\')

    $search = Join-Path $dir $pat
    $gci = @{ Path = $search; File = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
    if ($recurse) { $gci.Recurse = $true }
    $files = @(Get-ChildItem @gci)

    if ($files.Count -eq 0) {
        Write-Warn2 "没有匹配到任何文件：$search （该位置会被跳过）"
        continue
    }

    $size = 0L
    foreach ($f in $files) { try { $size += $f.Length } catch { } }

    # 列表上显示的短名：取最后两级目录
    $segs = $dir.Split('\')
    $short = if ($segs.Count -ge 2) { $segs[-2] + '\' + $segs[-1] } else { $dir }
    if ($short.Length -gt 46) { $short = '...' + $short.Substring($short.Length - 43) }

    # 还原到「指定文件夹」时使用的子目录名
    $subName = $segs[-1]
    if ($subName -match '^\d+$' -and $segs.Count -ge 2) { $subName = $segs[-2] }

    [void]$parts.Add([pscustomobject]@{
        Index    = $parts.Count
        Dir      = $dir
        Pattern  = $pat
        Search   = $search
        Count    = $files.Count
        Size     = $size
        Short    = $short
        SubName  = $subName
        OutName  = 'p' + $parts.Count
    })
}

if ($parts.Count -eq 0) { Write-Err2 '所有路径都没有匹配到文件，未生成备份包。'; exit 2 }

$totalFiles = 0L; $totalSize = 0L
foreach ($q in $parts) { $totalFiles += $q.Count; $totalSize += $q.Size }

# -----------------------------------------------------------------------------
# 3. 推断备份包名称
# -----------------------------------------------------------------------------
if (-not [string]::IsNullOrWhiteSpace($optName)) {
    $gameName = $optName.Trim()
} else {
    $segs = $parts[0].Dir.Split('\')
    $idx = $segs.Count - 1
    while ($idx -gt 0 -and $segs[$idx] -match '^\d+$') { $idx-- }   # 跳过 Steam 数字目录
    $gameName = $segs[$idx]
}
if ([string]::IsNullOrWhiteSpace($gameName)) { $gameName = 'GameSave' }

if (-not [string]::IsNullOrWhiteSpace($optOut)) {
    $OutDir = $optOut.Trim().Trim('"')
}
if (-not (Test-Path -LiteralPath $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir -Force) }
if (-not (Test-Path -LiteralPath $BuildDir)) { [void](New-Item -ItemType Directory -Path $BuildDir -Force) }

$stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$buildTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$safeName   = ConvertTo-SafeFileName $gameName
$exeName    = "${safeName}_存档备份_${stamp}.exe"
$outExe     = Join-Path $OutDir $exeName

# -----------------------------------------------------------------------------
# 4. 定位 makensis.exe
# -----------------------------------------------------------------------------
$makensis = Join-Path $RootDir 'nsis\makensis.exe'
if (-not (Test-Path -LiteralPath $makensis)) {
    $cmd = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($cmd) { $makensis = $cmd.Source }
    else {
        foreach ($cand in @('C:\Program Files (x86)\NSIS\makensis.exe', 'C:\Program Files\NSIS\makensis.exe')) {
            if (Test-Path -LiteralPath $cand) { $makensis = $cand; break }
        }
    }
}
if (-not $makensis -or -not (Test-Path -LiteralPath $makensis)) {
    Write-Err2 '未找到 makensis.exe，请把 NSIS 放到本项目的 .\nsis 目录，或安装 NSIS 到默认路径。'
    exit 3
}
$nsisHome = Split-Path -Parent $makensis

# 图标
$iconCand = @(
    (Join-Path $RootDir 'assets\icon.ico'),
    (Join-Path $nsisHome 'Contrib\Graphics\Icons\modern-install.ico')
)
$iconLine = '; (未使用自定义图标)'
foreach ($ic in $iconCand) {
    if (Test-Path -LiteralPath $ic) {
        $iconLine = '!define MUI_ICON "' + (ConvertTo-NsisString $ic) + '"'
        break
    }
}

# -----------------------------------------------------------------------------
# 5. 生成 NSI 片段
# -----------------------------------------------------------------------------
$sbVars     = New-Object System.Text.StringBuilder
$sbInit     = New-Object System.Text.StringBuilder
$sbCreate   = New-Object System.Text.StringBuilder
$sbLeave    = New-Object System.Text.StringBuilder
$sbSum      = New-Object System.Text.StringBuilder
$sbSections = New-Object System.Text.StringBuilder

$n = $parts.Count
$twoCols = ($n -ge 3)                                   # 3 个以上分两列，避免页面放不下
$rows    = if ($twoCols) { [math]::Ceiling($n / 2) } else { $n }
$cbTop   = 84
$cbStep  = 11
if ($rows -ge 4) { $cbStep = 10 }
if ($rows -ge 5) { $cbStep = 9 }

for ($i = 0; $i -lt $n; $i++) {
    $q   = $parts[$i]
    $row = if ($twoCols) { [math]::Floor($i / 2) } else { $i }
    $col = if ($twoCols) { $i % 2 } else { 0 }

    if ($twoCols) {
        $x = if ($col -eq 0) { '0' } else { '52%' }
        $w = '48%'
    } else {
        $x = '0'
        $w = '100%'
    }
    $y   = $cbTop + $row * $cbStep
    $lab = ConvertTo-NsisString ("[{0}] {1}\  ({2} 个文件, {3})" -f ($i + 1), $q.Short, $q.Count, (Get-SizeText $q.Size))

    [void]$sbVars.AppendLine("Var CB$i")
    [void]$sbVars.AppendLine("Var ST$i")

    [void]$sbInit.AppendLine("  StrCpy `$ST$i 1")

    [void]$sbCreate.AppendLine("  `${NSD_CreateCheckbox} $x $($y)u $w 10u `"$lab`"")
    [void]$sbCreate.AppendLine("  Pop `$CB$i")
    [void]$sbCreate.AppendLine("  `${If} `$ST$i == 1")
    [void]$sbCreate.AppendLine("    `${NSD_SetState} `$CB$i `${BST_CHECKED}")
    [void]$sbCreate.AppendLine("  `${EndIf}")

    [void]$sbLeave.AppendLine("  `${NSD_GetState} `$CB$i `$ST$i")

    [void]$sbSum.AppendLine("  IntOp `$R1 `$R1 + `$ST$i")

    # --- 还原段 ---
    $srcFull = ConvertTo-NsisString $q.Search
    $rec     = if ($recurse) { '/r ' } else { '' }
    $target  = ConvertTo-NsisString $q.Dir
    $sub     = ConvertTo-NsisString $q.SubName
    $tlab    = ConvertTo-NsisString $q.Short

    [void]$sbSections.AppendLine("  ; --- 位置 $($i + 1)：$tlab ---")
    [void]$sbSections.AppendLine("  SetOutPath `"`$PLUGINSDIR\$($q.OutName)`"")
    [void]$sbSections.AppendLine("  File $rec`"$srcFull`"")
    [void]$sbSections.AppendLine("  `${If} `$ST$i == 1")
    [void]$sbSections.AppendLine("    `${If} `$Mode == 1")
    [void]$sbSections.AppendLine("      StrCpy `$R0 `"`$DestDir\$sub`"")
    [void]$sbSections.AppendLine("    `${Else}")
    [void]$sbSections.AppendLine("      StrCpy `$R0 `"$target`"")
    [void]$sbSections.AppendLine("    `${EndIf}")
    [void]$sbSections.AppendLine("    DetailPrint `"还原：[$($i + 1)] `$R0`"")
    [void]$sbSections.AppendLine("    `${If} `$BackupOld == 1")
    [void]$sbSections.AppendLine("      IfFileExists `"`$R0\*.*`" 0 +2")
    [void]$sbSections.AppendLine("      Rename `"`$R0`" `"`$R0.bak_`${BACKUP_STAMP}`"")
    [void]$sbSections.AppendLine("    `${EndIf}")
    [void]$sbSections.AppendLine("    CreateDirectory `"`$R0`"")
    [void]$sbSections.AppendLine("    CopyFiles /SILENT `"`$PLUGINSDIR\$($q.OutName)\*.*`" `"`$R0`"")
    [void]$sbSections.AppendLine("    `${If} `$ResultDir == `"`"")
    [void]$sbSections.AppendLine("      StrCpy `$ResultDir `"`$R0`"")
    [void]$sbSections.AppendLine("    `${EndIf}")
    [void]$sbSections.AppendLine("  `${EndIf}")
    [void]$sbSections.AppendLine("")
}

# 自定义页可用高度约 123u，放不下时自动隐藏「备份现有文件」选项（默认仍开启）
$lastBottom = $cbTop + ($rows - 1) * $cbStep + 10
$tipY = $lastBottom + 2
if (($tipY + 10) -gt 122) {
    $tipY = 200
    Write-Warn2 '位置较多，界面已省略「备份现有文件」选项（该功能默认开启）。'
}

# -----------------------------------------------------------------------------
# 6. 填充模板
# -----------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $TemplateFile)) { Write-Err2 "模板文件不存在：$TemplateFile"; exit 3 }

$tmpl = [IO.File]::ReadAllText($TemplateFile, [System.Text.Encoding]::UTF8)

$map = [ordered]@{
    '@@BUILD_TIME@@'   = $buildTime
    '@@PRODUCT_NAME@@' = ConvertTo-NsisString $gameName
    '@@BACKUP_TIME@@'  = $buildTime
    '@@BACKUP_STAMP@@' = $stamp
    '@@TOTAL_FILES@@'  = [string]$totalFiles
    '@@TOTAL_SIZE@@'   = Get-SizeText $totalSize
    '@@PART_COUNT@@'   = [string]$n
    '@@BACKUP_MODE@@'  = if ($recurse) { '含子目录' } else { '仅当前目录' }
    '@@OUT_FILE@@'     = ConvertTo-NsisString $outExe
    '@@ICON_LINE@@'    = $iconLine
    '@@PART_VARS@@'    = $sbVars.ToString().TrimEnd()
    '@@PART_INIT@@'    = $sbInit.ToString().TrimEnd()
    '@@PART_CREATE@@'  = $sbCreate.ToString().TrimEnd()
    '@@PART_LEAVE@@'   = $sbLeave.ToString().TrimEnd()
    '@@PART_SUM@@'     = $sbSum.ToString().TrimEnd()
    '@@PART_SECTIONS@@'= $sbSections.ToString().TrimEnd()
    '@@TIP_Y@@'        = [string]$tipY
}

$nsiText = $tmpl
foreach ($k in $map.Keys) {
    $nsiText = $nsiText.Replace($k, [string]$map[$k])
}

# 统一使用 CRLF 行尾（Windows 约定）
$nsiText = $nsiText -replace "`r`n", "`n"
$nsiText = $nsiText -replace "`n", "`r`n"

$nsiPath = Join-Path $BuildDir ("${safeName}.nsi")
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($nsiPath, $nsiText, $utf8Bom)

# -----------------------------------------------------------------------------
# 7. 编译
# -----------------------------------------------------------------------------
Write-Host ''
Write-Host 'GameSaveHelper - 正在生成备份包' -ForegroundColor Cyan
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Host "  名称     : $gameName"
Write-Host "  位置数   : $n"
foreach ($q in $parts) {
    Write-Host ("    [{0}] {1}  ->  {2} 个文件, {3}" -f ($q.Index + 1), $q.Search, $q.Count, (Get-SizeText $q.Size))
}
Write-Host ("  合计     : {0} 个文件, {1}" -f $totalFiles, (Get-SizeText $totalSize))
Write-Host "  匹配方式 : " -NoNewline
if ($recurse) { Write-Host '包含子目录' -ForegroundColor Gray } else { Write-Host '仅当前目录' -ForegroundColor Gray }
Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Step '正在编译（makensis）...'

if (Test-Path -LiteralPath $outExe) { Remove-Item -LiteralPath $outExe -Force -ErrorAction SilentlyContinue }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $makensis
$psi.Arguments = '/V2 "' + $nsiPath + '"'
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
$psi.WorkingDirectory = $nsisHome
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()
$code = $proc.ExitCode

$hasError = $false
foreach ($line in ($stdout + "`n" + $stderr).Split("`n")) {
    $t = $line.Trim()
    if ($t -eq '') { continue }
    if ($t -match '^\s*(warning|Warning)') { Write-Host "    $t" -ForegroundColor Yellow; continue }
    if ($t -match 'error|Error|ERROR') { $hasError = $true; Write-Host "    $t" -ForegroundColor Red; continue }
}

if ($code -ne 0 -or $hasError -or -not (Test-Path -LiteralPath $outExe)) {
    Write-Host ''
    Write-Err2 "编译失败（退出码 $code）。生成的脚本已保留：$nsiPath"
    if ($stdout) { Write-Host $stdout }
    if ($stderr) { Write-Host $stderr }
    exit 4
}

if (-not $keepNsi) { Remove-Item -LiteralPath $nsiPath -Force -ErrorAction SilentlyContinue }

Write-Host '------------------------------------------------' -ForegroundColor DarkGray
Write-Ok "生成成功：$outExe"
Write-Host ("  文件体积 : {0}" -f (Get-SizeText (Get-Item -LiteralPath $outExe).Length))
Write-Host ''
Write-Host '  双击运行该 exe 即可还原存档：' -ForegroundColor Gray
Write-Host '   · 默认还原到备份时的原始位置' -ForegroundColor Gray
Write-Host '   · 也可以选择「我选择的文件夹」导出到别处' -ForegroundColor Gray
Write-Host '   · 静默还原：GameSaveBackup.exe /S' -ForegroundColor Gray
Write-Host '   · 指定目录：GameSaveBackup.exe /D=D:\my\saves' -ForegroundColor Gray
Write-Host ''
exit 0
