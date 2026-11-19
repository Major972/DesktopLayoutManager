# Create-Shortcut.ps1
# Makes an icon and a desktop shortcut for Desktop Layout Manager.
# Run: powershell -ExecutionPolicy Bypass -File .\Create-Shortcut.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$here    = Split-Path -Parent $PSCommandPath
$appPath = Join-Path $here 'DesktopLayoutManager.ps1'
$icoPath = Join-Path $here 'DesktopLayoutManager.ico'
$desktop = [Environment]::GetFolderPath('Desktop')

function New-IconBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $s = $size / 256.0
    $r = 96 * $s
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(8 * $s, 8 * $s, $r, $r, 180, 90)
    $path.AddArc(248 * $s - $r, 8 * $s, $r, $r, 270, 90)
    $path.AddArc(248 * $s - $r, 248 * $s - $r, $r, $r, 0, 90)
    $path.AddArc(8 * $s, 248 * $s - $r, $r, $r, 90, 90)
    $path.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(30, 30, 38))), $path)
    $colors = @(
        [System.Drawing.Color]::FromArgb(0, 120, 212), [System.Drawing.Color]::FromArgb(22, 139, 60),
        [System.Drawing.Color]::FromArgb(255, 140, 0), [System.Drawing.Color]::FromArgb(136, 23, 152)
    )
    for ($row = 0; $row -lt 2; $row++) {
        for ($col = 0; $col -lt 2; $col++) {
            $b = New-Object System.Drawing.SolidBrush $colors[$row * 2 + $col]
            $g.FillRectangle($b, [single]((36 + $col * 104) * $s), [single]((36 + $row * 104) * $s), [single](92 * $s), [single](92 * $s))
        }
    }
    $g.Dispose()
    return $bmp
}

# Build a multi-size .ico (PNG-compressed entries)
$sizes = @(16, 32, 48, 256)
$pngs = @()
foreach ($sz in $sizes) {
    $bmp = New-IconBitmap $sz
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngs += ,($ms.ToArray())
}
$ico = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ico)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dim = $sizes[$i]; if ($dim -ge 256) { $dim = 0 }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($icoPath, $ico.ToArray())

# Desktop shortcut that starts the app without a console window
$lnkPath = Join-Path $desktop 'Desktop Layout Manager.lnk'
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
$lnk.TargetPath = 'powershell.exe'
$lnk.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $appPath + '"'
$lnk.WorkingDirectory = $here
$lnk.IconLocation = $icoPath + ',0'
$lnk.Description = 'Desktop Layout Manager'
$lnk.Save()
Write-Host "Shortcut created: $lnkPath"
