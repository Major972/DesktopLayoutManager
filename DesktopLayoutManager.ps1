# DesktopLayoutManager.ps1
# Desktop icon layout manager: save named layouts, restore them, auto-restore after resolution changes.
# Run: powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Documents\DesktopLayoutManager.ps1"

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DeskApi {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string w);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint a, bool i, uint pid);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr addr, uint size, uint type, uint prot);
    [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr p, IntPtr addr, uint size, uint type);
    [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr addr, byte[] buf, uint size, out IntPtr written);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr addr, byte[] buf, uint size, out IntPtr read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    public static IntPtr FindListView() {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            IntPtr d = FindWindowEx(h, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (d != IntPtr.Zero) { found = FindWindowEx(d, IntPtr.Zero, "SysListView32", null); return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static string[] GetNames(IntPtr lv) {
        uint pid; GetWindowThreadProcessId(lv, out pid);
        IntPtr hp = OpenProcess(0x1F0FFF, false, pid);
        int count = (int)SendMessage(lv, 0x1004, IntPtr.Zero, IntPtr.Zero).ToInt64();
        IntPtr buf = VirtualAllocEx(hp, IntPtr.Zero, 4096, 0x3000, 0x04);
        string[] names = new string[count];
        IntPtr w;
        for (int i = 0; i < count; i++) {
            byte[] item = new byte[64];
            BitConverter.GetBytes((uint)1).CopyTo(item, 0);
            BitConverter.GetBytes(i).CopyTo(item, 4);
            BitConverter.GetBytes((long)(buf.ToInt64() + 512)).CopyTo(item, 24);
            BitConverter.GetBytes(256).CopyTo(item, 32);
            WriteProcessMemory(hp, buf, item, 64, out w);
            SendMessage(lv, 0x1073, (IntPtr)i, buf);
            byte[] txt = new byte[512];
            ReadProcessMemory(hp, (IntPtr)(buf.ToInt64() + 512), txt, 512, out w);
            names[i] = Encoding.Unicode.GetString(txt).Split('\0')[0];
        }
        VirtualFreeEx(hp, buf, 0, 0x8000);
        CloseHandle(hp);
        return names;
    }

    public static int[] GetPositions(IntPtr lv) {
        uint pid; GetWindowThreadProcessId(lv, out pid);
        IntPtr hp = OpenProcess(0x1F0FFF, false, pid);
        int count = (int)SendMessage(lv, 0x1004, IntPtr.Zero, IntPtr.Zero).ToInt64();
        IntPtr buf = VirtualAllocEx(hp, IntPtr.Zero, 4096, 0x3000, 0x04);
        int[] res = new int[count * 2];
        IntPtr w;
        for (int i = 0; i < count; i++) {
            SendMessage(lv, 0x1010, (IntPtr)i, buf);
            byte[] pt = new byte[8];
            ReadProcessMemory(hp, buf, pt, 8, out w);
            res[2 * i] = BitConverter.ToInt32(pt, 0);
            res[2 * i + 1] = BitConverter.ToInt32(pt, 4);
        }
        VirtualFreeEx(hp, buf, 0, 0x8000);
        CloseHandle(hp);
        return res;
    }

    public static void SetPosition(IntPtr lv, int index, int x, int y) {
        long lp = (long)(y & 0xFFFF) * 65536L + (long)(x & 0xFFFF);
        SendMessage(lv, 0x100F, (IntPtr)index, (IntPtr)lp);
    }
}
"@

$layoutDir  = Join-Path $env:USERPROFILE 'Documents\DesktopLayouts'
New-Item -ItemType Directory -Path $layoutDir -Force | Out-Null
$ruleScript = Join-Path (Split-Path -Parent $PSCommandPath) 'DesktopLayout.ps1'

function Get-DesktopLv {
    $lv = [DeskApi]::FindListView()
    if ($lv -eq [IntPtr]::Zero) { throw 'Desktop ListView not found.' }
    return $lv
}

function Save-Layout([string]$name) {
    $lv = Get-DesktopLv
    $names = [DeskApi]::GetNames($lv)
    $pos = [DeskApi]::GetPositions($lv)
    $items = for ($i = 0; $i -lt $names.Length; $i++) {
        [pscustomobject]@{ Name = $names[$i]; X = $pos[2 * $i]; Y = $pos[2 * $i + 1] }
    }
    $scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $data = [pscustomobject]@{
        SavedAt = (Get-Date).ToString('s')
        Screen  = "$($scr.Width)x$($scr.Height)"
        Items   = @($items)
    }
    $path = Join-Path $layoutDir ($name + '.json')
    $data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Restore-Layout([string]$path) {
    $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $lv = Get-DesktopLv
    $names = [DeskApi]::GetNames($lv)
    $idx = @{}
    for ($i = 0; $i -lt $names.Length; $i++) {
        if (-not $idx.ContainsKey($names[$i])) { $idx[$names[$i]] = $i }
    }
    $n = 0
    foreach ($it in @($data.Items)) {
        if ($idx.ContainsKey($it.Name)) {
            [DeskApi]::SetPosition($lv, $idx[$it.Name], [int]$it.X, [int]$it.Y)
            $n++
        }
    }
    return $n
}

# ---------- Desktop icon cache (real icons of the desktop items) ----------
$script:iconCache   = @{}
$script:iconSources = @{}

function Get-IconFileFromUrl([string]$path) {
    try {
        foreach ($line in [System.IO.File]::ReadAllLines($path)) {
            if ($line -like 'IconFile=*') { return $line.Substring(9).Trim() }
        }
    } catch {}
    return $null
}

function Build-IconSources {
    $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'))
    foreach ($d in $dirs) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
        foreach ($it in (Get-ChildItem -LiteralPath $d -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '.*' })) {
            $disp = $it.BaseName
            if ($it.PSIsContainer) { $disp = $it.Name }
            if (-not $script:iconSources.ContainsKey($disp)) { $script:iconSources[$disp] = $it }
        }
    }
}
Build-IconSources

# Fallback icon: yellow folder, or a colored tile with the item's first letter
function New-FallbackIcon([string]$name, [bool]$folder) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    if ($folder) {
        $b1 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 190, 60))
        $g.FillRectangle($b1, 2, 8, 28, 20)
        $g.FillRectangle($b1, 2, 5, 12, 5)
        $b1.Dispose()
    } else {
        $palette = @(
            [System.Drawing.Color]::FromArgb(0, 120, 212), [System.Drawing.Color]::FromArgb(22, 139, 60),
            [System.Drawing.Color]::FromArgb(214, 106, 0), [System.Drawing.Color]::FromArgb(136, 23, 152),
            [System.Drawing.Color]::FromArgb(200, 52, 40), [System.Drawing.Color]::FromArgb(0, 130, 130)
        )
        $h = 0
        foreach ($ch in $name.ToCharArray()) { $h = ($h * 31 + [int]$ch) % 1000003 }
        $b1 = New-Object System.Drawing.SolidBrush $palette[$h % 6]
        $g.FillRectangle($b1, 1, 1, 30, 30)
        $b1.Dispose()
        $initial = '?'
        if ($name.Length -gt 0) { $initial = $name.Substring(0, 1).ToUpper() }
        $font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $g.DrawString($initial, $font, [System.Drawing.Brushes]::White, [System.Drawing.RectangleF]::new(0, 0, 32, 32), $sf)
        $font.Dispose(); $sf.Dispose()
    }
    $g.Dispose()
    return $bmp
}

function Get-IconBitmap([string]$name) {
    if ($script:iconCache.ContainsKey($name)) { return $script:iconCache[$name] }
    $bmp = $null
    $isFolder = $false
    if ($script:iconSources.ContainsKey($name)) {
        $it = $script:iconSources[$name]
        if ($it.PSIsContainer) {
            $isFolder = $true
        } else {
            try {
                $icon = $null
                if ($it.Extension -eq '.url') {
                    $iconFile = Get-IconFileFromUrl $it.FullName
                    if ($iconFile -and (Test-Path -LiteralPath $iconFile)) {
                        if ($iconFile -like '*.ico') { $icon = [System.Drawing.Icon]::new($iconFile, 32, 32) }
                        else { $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconFile) }
                    }
                }
                if (-not $icon) { $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($it.FullName) }
                if ($icon) { $bmp = $icon.ToBitmap() }
            } catch { $bmp = $null }
        }
    }
    if (-not $bmp) { $bmp = New-FallbackIcon $name $isFolder }
    $script:iconCache[$name] = $bmp
    return $bmp
}

# ---------- Theme ----------
$cBg     = [System.Drawing.Color]::FromArgb(18, 18, 24)
$cHead   = [System.Drawing.Color]::FromArgb(28, 28, 36)
$cCard   = [System.Drawing.Color]::FromArgb(32, 32, 42)
$cField  = [System.Drawing.Color]::FromArgb(44, 44, 56)
$cBorder = [System.Drawing.Color]::FromArgb(58, 58, 74)
$cText   = [System.Drawing.Color]::FromArgb(242, 242, 247)
$cMuted  = [System.Drawing.Color]::FromArgb(143, 143, 163)
$cBlue   = [System.Drawing.Color]::FromArgb(0, 120, 212)
$cGreen  = [System.Drawing.Color]::FromArgb(22, 139, 60)
$cRed    = [System.Drawing.Color]::FromArgb(200, 52, 40)
$cGray   = [System.Drawing.Color]::FromArgb(66, 66, 84)
$cOk     = [System.Drawing.Color]::FromArgb(40, 190, 90)
$cErr    = [System.Drawing.Color]::FromArgb(230, 70, 60)
$script:dotColor = $cBlue

function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [float]$size, [bool]$bold, $color, $parent) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $style = [System.Drawing.FontStyle]::Regular
    if ($bold) { $style = [System.Drawing.FontStyle]::Bold }
    $l.Font = New-Object System.Drawing.Font('Segoe UI', $size, $style)
    $l.ForeColor = $color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $parent.Controls.Add($l)
    return $l
}

# Flat panel; $border draws a 1px outline (used for cards)
function New-Panel([int]$x, [int]$y, [int]$w, [int]$h, $color, $parent, [bool]$border = $false) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $color
    if ($border) {
        $p.Add_Paint({
            param($s, $e)
            $pen = New-Object System.Drawing.Pen($cBorder)
            $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1)
            $pen.Dispose()
        })
    }
    $parent.Controls.Add($p)
    return $p
}

# Small vector glyphs drawn at runtime (no external image files needed)
function New-Glyph([string]$kind, $color) {
    $bmp = New-Object System.Drawing.Bitmap 20, 20
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $pen = New-Object System.Drawing.Pen($color, 2)
    $brush = New-Object System.Drawing.SolidBrush($color)
    switch ($kind) {
        'save' {
            $g.DrawRectangle($pen, 3, 3, 14, 14)
            $g.FillRectangle($brush, 6, 3, 8, 5)
            $g.FillRectangle($brush, 6, 12, 8, 5)
        }
        'restore' {
            $g.DrawLine($pen, 10, 3, 10, 12)
            $g.FillPolygon($brush, [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new(4, 10), [System.Drawing.Point]::new(16, 10), [System.Drawing.Point]::new(10, 16)))
            $g.DrawLine($pen, 4, 18, 16, 18)
        }
        'delete' {
            $g.DrawLine($pen, 5, 5, 15, 15)
            $g.DrawLine($pen, 15, 5, 5, 15)
        }
        'grid' {
            $g.FillRectangle($brush, 3, 3, 6, 6)
            $g.FillRectangle($brush, 11, 3, 6, 6)
            $g.FillRectangle($brush, 3, 11, 6, 6)
            $g.FillRectangle($brush, 11, 11, 6, 6)
        }
        'folder' {
            $g.FillRectangle($brush, 2, 6, 16, 11)
            $g.FillRectangle($brush, 2, 4, 7, 3)
        }
    }
    $pen.Dispose(); $brush.Dispose(); $g.Dispose()
    return $bmp
}

# Header app icon: four colored tiles
function New-AppIcon {
    $bmp = New-Object System.Drawing.Bitmap 48, 48
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $colors = @(
        [System.Drawing.Color]::FromArgb(0, 120, 212),
        [System.Drawing.Color]::FromArgb(22, 139, 60),
        [System.Drawing.Color]::FromArgb(255, 140, 0),
        [System.Drawing.Color]::FromArgb(136, 23, 152)
    )
    for ($r = 0; $r -lt 2; $r++) {
        for ($c = 0; $c -lt 2; $c++) {
            $b = New-Object System.Drawing.SolidBrush $colors[$r * 2 + $c]
            $g.FillRectangle($b, 4 + $c * 22, 4 + $r * 22, 20, 20)
            $b.Dispose()
        }
    }
    $g.Dispose()
    return $bmp
}

function New-Btn([string]$text, [string]$glyph, [int]$x, [int]$y, [int]$w, [int]$h, $color, $parent) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = "   $text"
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $b.TextAlign = 'MiddleLeft'
    $b.ImageAlign = 'MiddleLeft'
    $b.Image = New-Glyph $glyph ([System.Drawing.Color]::White)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.FlatAppearance.MouseOverBackColor = [System.Windows.Forms.ControlPaint]::Light($color, 0.12)
    $b.FlatAppearance.MouseDownBackColor = [System.Windows.Forms.ControlPaint]::Dark($color, 0.1)
    $parent.Controls.Add($b)
    return $b
}

# ---------- Window ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Desktop Layout Manager'
$form.ClientSize = New-Object System.Drawing.Size(1216, 560)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $cBg
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

# Header
$header = New-Panel 0 0 1216 88 $cHead $form
$iconBox = New-Object System.Windows.Forms.PictureBox
$iconBox.Image = New-AppIcon
$iconBox.Location = New-Object System.Drawing.Point(24, 20)
$iconBox.Size = New-Object System.Drawing.Size(48, 48)
$header.Controls.Add($iconBox)
[void](New-Label 'Desktop Layout Manager' 88 16 560 34 18 $true $cText $header)
[void](New-Label 'Save, restore and auto-restore your desktop icon positions' 90 50 560 22 9.5 $false $cMuted $header)
[void](New-Panel 0 88 1216 2 $cBlue $form)

# Left card: saved layouts
$leftCard = New-Panel 24 110 300 340 $cCard $form $true
[void](New-Label 'SAVED LAYOUTS' 18 16 260 18 8.5 $true $cMuted $leftCard)
$countLbl = New-Label '' 18 34 270 18 9 $false $cMuted $leftCard

$list = New-Object System.Windows.Forms.ListBox
$list.Location = New-Object System.Drawing.Point(18, 60)
$list.Size = New-Object System.Drawing.Size(264, 220)
$list.BackColor = $cField
$list.ForeColor = $cText
$list.BorderStyle = 'None'
$list.DrawMode = 'OwnerDrawFixed'
$list.ItemHeight = 34
$list.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
$list.Add_DrawItem({
    param($s, $e)
    if ($e.Index -lt 0) { return }
    $selected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $bgColor = $cField
    if ($selected) { $bgColor = $cBlue }
    $bgBrush = New-Object System.Drawing.SolidBrush $bgColor
    $e.Graphics.FillRectangle($bgBrush, $e.Bounds)
    $bgBrush.Dispose()
    $txtBrush = New-Object System.Drawing.SolidBrush $cText
    $y = $e.Bounds.Y + 8
    $e.Graphics.DrawString([string]$s.Items[$e.Index], $e.Font, $txtBrush, [single]($e.Bounds.X + 12), [single]$y)
    $txtBrush.Dispose()
})
$leftCard.Controls.Add($list)

[void](New-Label 'Double-click a layout to restore it.' 18 292 270 36 8.5 $false $cMuted $leftCard)

# Middle card: desktop preview drawn with the real desktop icons
$previewCard = New-Panel 340 110 520 340 $cCard $form $true
[void](New-Label 'DESKTOP PREVIEW' 18 16 200 18 8.5 $true $cMuted $previewCard)
$previewTitle = New-Label '' 18 34 320 18 9 $false $cMuted $previewCard

$canvas = New-Object System.Windows.Forms.Panel
$canvas.Location = New-Object System.Drawing.Point(16, 58)
$canvas.Size = New-Object System.Drawing.Size(488, 264)
$canvas.BackColor = [System.Drawing.Color]::FromArgb(14, 14, 20)
$dbProp = [System.Windows.Forms.Panel].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance')
$dbProp.SetValue($canvas, $true, $null)
$previewCard.Controls.Add($canvas)

$script:pvItems = @()
$script:pvW = 2560
$script:pvH = 1440
$script:pvScale = 0.18

$canvas.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sc = [math]::Min($s.Width / $script:pvW, $s.Height / $script:pvH)
    $script:pvScale = $sc
    $pen = New-Object System.Drawing.Pen $cBorder
    $g.DrawRectangle($pen, 0, 0, [int]($script:pvW * $sc) - 1, [int]($script:pvH * $sc) - 1)
    $pen.Dispose()
    $size = [math]::Max(12, 75 * $sc)
    foreach ($it in $script:pvItems) {
        $bmp = Get-IconBitmap ([string]$it.Name)
        $g.DrawImage($bmp, [single]($it.X * $sc), [single]($it.Y * $sc), [single]$size, [single]$size)
    }
})

$tip = New-Object System.Windows.Forms.ToolTip
$script:hoverName = ''
$canvas.Add_MouseMove({
    param($s, $e)
    $sc = $script:pvScale
    $size = [math]::Max(12, 75 * $sc)
    $hit = ''
    foreach ($it in $script:pvItems) {
        $x = $it.X * $sc
        $y = $it.Y * $sc
        if ($e.X -ge $x -and $e.X -le ($x + $size) -and $e.Y -ge $y -and $e.Y -le ($y + $size)) { $hit = [string]$it.Name }
    }
    if ($hit -ne $script:hoverName) {
        $script:hoverName = $hit
        $tip.SetToolTip($s, $hit)
    }
})

function Set-Preview($items, [string]$screen, [string]$title) {
    $w = 2560
    $h = 1440
    if ($screen -match '^(\d+)x(\d+)$') { $w = [int]$Matches[1]; $h = [int]$Matches[2] }
    $script:pvItems = @($items)
    $script:pvW = $w
    $script:pvH = $h
    $previewTitle.Text = $title
    $canvas.Invalidate()
}

function Show-CurrentDesktopPreview {
    try {
        $lv = Get-DesktopLv
        $names = [DeskApi]::GetNames($lv)
        $pos = [DeskApi]::GetPositions($lv)
        $items = for ($i = 0; $i -lt $names.Length; $i++) {
            [pscustomobject]@{ Name = $names[$i]; X = $pos[2 * $i]; Y = $pos[2 * $i + 1] }
        }
        $scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        Set-Preview $items "$($scr.Width)x$($scr.Height)" 'Current desktop'
    } catch { $previewTitle.Text = "Preview unavailable: $($_.Exception.Message)" }
}

$btnCurrent = New-Btn 'Show current' 'grid' 346 8 158 30 $cGray $previewCard
$btnCurrent.Add_Click({
    $list.ClearSelected()
    Show-CurrentDesktopPreview
})

# Right card: actions
$rightCard = New-Panel 876 110 316 340 $cCard $form $true
[void](New-Label 'LAYOUT NAME' 18 16 280 18 8.5 $true $cMuted $rightCard)
$nameBox = New-Object System.Windows.Forms.TextBox
$nameBox.Location = New-Object System.Drawing.Point(18, 38)
$nameBox.Size = New-Object System.Drawing.Size(280, 28)
$nameBox.BackColor = $cField
$nameBox.ForeColor = $cText
$nameBox.BorderStyle = 'FixedSingle'
$nameBox.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
$nameBox.Text = 'My layout'
$rightCard.Controls.Add($nameBox)

$btnSave    = New-Btn 'Save current layout'    'save'    18  80 280 42 $cBlue  $rightCard
$btnRestore = New-Btn 'Restore selected'       'restore' 18 132 280 42 $cGreen $rightCard
$btnDelete  = New-Btn 'Delete selected'        'delete'  18 184 280 42 $cRed   $rightCard
[void](New-Label 'TOOLS' 18 242 280 18 8.5 $true $cMuted $rightCard)
$btnRule    = New-Btn 'Apply rule layout (2K)' 'grid'    18 264 280 38 $cGray  $rightCard
$btnOpen    = New-Btn 'Open layouts folder'    'folder'  18 310 280 36 $cField $rightCard

# Footer: status + auto-restore option
$footer = New-Panel 0 486 1216 74 $cHead $form
$dot = New-Object System.Windows.Forms.Panel
$dot.Location = New-Object System.Drawing.Point(24, 22)
$dot.Size = New-Object System.Drawing.Size(10, 10)
$dot.BackColor = $cHead
$dot.Add_Paint({
    param($s, $e)
    $b = New-Object System.Drawing.SolidBrush $script:dotColor
    $e.Graphics.FillEllipse($b, 0, 0, 9, 9)
    $b.Dispose()
})
$footer.Controls.Add($dot)

$status = New-Label 'Ready.' 42 16 620 22 9.5 $false $cText $footer

$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text = 'Auto-switch: when the screen resolution changes, restore the layout saved for it'
$chkAuto.Location = New-Object System.Drawing.Point(42, 42)
$chkAuto.Size = New-Object System.Drawing.Size(620, 22)
$chkAuto.ForeColor = $cMuted
$chkAuto.BackColor = $cHead
$chkAuto.FlatStyle = 'Flat'
$footer.Controls.Add($chkAuto)

function Set-Status([string]$msg, [string]$kind = 'info') {
    $status.Text = $msg
    switch ($kind) {
        'ok'    { $script:dotColor = $cOk }
        'error' { $script:dotColor = $cErr }
        default { $script:dotColor = $cBlue }
    }
    $dot.Invalidate()
}

function Refresh-List {
    $list.Items.Clear()
    Get-ChildItem -LiteralPath $layoutDir -Filter '*.json' | Sort-Object LastWriteTime -Descending | ForEach-Object {
        [void]$list.Items.Add($_.BaseName)
    }
    $scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $countLbl.Text = "$($list.Items.Count) saved  |  screen $($scr.Width)x$($scr.Height)"
}

function Get-SelectedPath {
    if (-not $list.SelectedItem) { return $null }
    return Join-Path $layoutDir ($list.SelectedItem.ToString() + '.json')
}

$btnSave.Add_Click({
    try {
        $n = $nameBox.Text.Trim()
        if (-not $n) { $n = 'layout-' + (Get-Date -Format 'yyyyMMdd-HHmm') }
        [void](Save-Layout $n)
        Refresh-List
        $newIndex = $list.Items.IndexOf($n)
        if ($newIndex -ge 0) { $list.SelectedIndex = $newIndex }
        Set-Status "Saved layout: $n" 'ok'
    } catch { Set-Status "Error: $($_.Exception.Message)" 'error' }
})

$btnRestore.Add_Click({
    try {
        $p = Get-SelectedPath
        if (-not $p) { Set-Status 'Select a layout first.' 'error'; return }
        $n = Restore-Layout $p
        Set-Status "Restored $n icons from $($list.SelectedItem)." 'ok'
    } catch { Set-Status "Error: $($_.Exception.Message)" 'error' }
})

$btnDelete.Add_Click({
    $p = Get-SelectedPath
    if (-not $p) { Set-Status 'Select a layout first.' 'error'; return }
    $answer = [System.Windows.Forms.MessageBox]::Show("Delete '$($list.SelectedItem)'?", 'Confirm', 'YesNo')
    if ($answer -eq 'Yes') {
        Remove-Item -LiteralPath $p
        Refresh-List
        Set-Status 'Layout deleted.' 'ok'
    }
})

$btnRule.Add_Click({
    try {
        Set-Status 'Applying rule layout...'
        $form.Refresh()
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ruleScript
        Set-Status 'Rule layout applied.' 'ok'
    } catch { Set-Status "Error: $($_.Exception.Message)" 'error' }
})

$btnOpen.Add_Click({
    Start-Process explorer.exe -ArgumentList "`"$layoutDir`""
})

$list.Add_DoubleClick({ $btnRestore.PerformClick() })

$list.Add_SelectedIndexChanged({
    $p = Get-SelectedPath
    if (-not $p) { return }
    try {
        $d = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $count = @($d.Items).Count
        Set-Preview $d.Items ([string]$d.Screen) ([string]$list.SelectedItem)
        Set-Status "$($list.SelectedItem)  |  saved $($d.SavedAt)  |  $count icons  |  screen $($d.Screen)"
    } catch { Set-Status "Cannot read layout: $($_.Exception.Message)" 'error' }
})

# Find the saved layout that belongs to a screen resolution (e.g. "2560x1440").
# The selected layout wins if it matches; otherwise the most recently saved matching layout is used.
function Find-LayoutForScreen([string]$key) {
    $files = @(Get-ChildItem -LiteralPath $layoutDir -Filter '*.json' | Sort-Object LastWriteTime -Descending)
    $selected = Get-SelectedPath
    if ($selected) {
        $files = @($files | Where-Object { $_.FullName -eq $selected }) + @($files | Where-Object { $_.FullName -ne $selected })
    }
    foreach ($f in $files) {
        try {
            $d = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$d.Screen -eq $key) { return $f.FullName }
        } catch {}
    }
    return $null
}

# Auto-switch: whenever the screen resolution changes, wait 5 s (Windows needs a moment to finish
# rearranging the icons) and restore the saved layout that matches the new resolution.
$script:lastKey = ''
$script:pendingAt = $null
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $key = "$($b.Width)x$($b.Height)"
    if ($script:lastKey -ne '' -and $key -ne $script:lastKey -and $chkAuto.Checked) {
        $script:pendingAt = (Get-Date).AddSeconds(5)
    }
    $script:lastKey = $key
    if ($script:pendingAt -and (Get-Date) -ge $script:pendingAt) {
        $script:pendingAt = $null
        try {
            $now = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $nowKey = "$($now.Width)x$($now.Height)"
            $p = Find-LayoutForScreen $nowKey
            if ($p) {
                $n = Restore-Layout $p
                Set-Status "Resolution ${nowKey}: switched to '$([System.IO.Path]::GetFileNameWithoutExtension($p))' ($n icons)." 'ok'
            } else {
                Set-Status "Resolution ${nowKey}: no saved layout for this resolution." 'error'
            }
        } catch { Set-Status "Auto-switch failed: $($_.Exception.Message)" 'error' }
    }
})
$timer.Start()

$form.Add_FormClosing({ $timer.Stop() })
Refresh-List
Show-CurrentDesktopPreview
[void]$form.ShowDialog()
