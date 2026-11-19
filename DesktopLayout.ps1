# DesktopLayout.ps1
# Layout (grid columns, row-major):
#   cols 0-1 : Apps (grouped)
#   col 2    : empty
#   cols 3-4 : Files (folders and other items)
#   col 5    : empty
#   cols 6-7 : Games (launchers first, then game shortcuts)
# Run: powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Documents\DesktopLayout.ps1"

param([switch]$Watch)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

if ($Watch) {
    # Background mode: re-apply the layout each time the screen returns to 2560x1440 (e.g. after a game changes resolution)
    $last = ''
    while ($true) {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $key = "$($b.Width)x$($b.Height)"
        if ($key -ne $last -and $key -eq '2560x1440') {
            Start-Sleep -Seconds 5
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        }
        $last = $key
        Start-Sleep -Seconds 2
    }
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class DeskLV {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string w);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a, bool i, uint pid);
    [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr addr, uint size, uint type, uint prot);
    [DllImport("kernel32.dll")] public static extern bool VirtualFreeEx(IntPtr p, IntPtr addr, uint size, uint type);
    [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr p, IntPtr addr, byte[] buf, uint size, out IntPtr written);
    [DllImport("kernel32.dll")] public static extern bool ReadProcessMemory(IntPtr p, IntPtr addr, byte[] buf, uint size, out IntPtr read);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);

    // Scan every top-level window for the one hosting SHELLDLL_DefView, return its SysListView32
    public static IntPtr FindListView() {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            IntPtr d = FindWindowEx(h, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (d != IntPtr.Zero) {
                found = FindWindowEx(d, IntPtr.Zero, "SysListView32", null);
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@

# ---- Group definitions (wildcards match the displayed name, extension hidden) ----
$appGroups  = @(
    @('Bu Bilgisayar', 'Denetim*'),
    @('GitHub Copilot', 'OpenCode'),
    @('Discord', 'Wispr Flow'),
    @('Steam', 'EA', 'Epic Games Launcher', 'Hone', 'NVIDIA App', 'OBS Studio', 'Voicemod*', 'Themia', 'Windhawk', 'Wise Memory*')
)
$launchPats = @('TLauncher', 'Paradox Launcher*', 'Rockstar Games Launcher', 'Ubisoft Connect')

# ---- Find the desktop ListView ----
$lv = [DeskLV]::FindListView()
if ($lv -eq [IntPtr]::Zero) { throw 'Desktop ListView not found. Is the desktop icon display turned on (right-click desktop > View > Show desktop icons)?' }

[uint32]$ownerPid = 0
[void][DeskLV]::GetWindowThreadProcessId($lv, [ref]$ownerPid)
$hp = [DeskLV]::OpenProcess(0x1F0FFF, $false, $ownerPid)
if ($hp -eq [IntPtr]::Zero) { throw 'Cannot open explorer.exe process.' }

# Auto-arrange (bit 0) and align-to-grid (bit 1) must be off or positions will snap back
$flags = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop' -Name FFlags -ErrorAction SilentlyContinue).FFlags
if ($flags -band 3) {
    Write-Warning 'Auto arrange or align to grid is ON. Turn both off (desktop right-click > View) and run again.'
}

$count = ([DeskLV]::SendMessage($lv, 0x1004, [IntPtr]::Zero, [IntPtr]::Zero)).ToInt64()
$sp    = ([DeskLV]::SendMessage($lv, 0x1033, [IntPtr]::Zero, [IntPtr]::Zero)).ToInt64()
$cx = $sp -band 0xFFFF
$cy = ($sp -shr 16) -band 0xFFFF
Write-Host "Desktop items: $count  cell: $cx x $cy"

# ---- Read display names of every ListView item (remote memory buffer) ----
$buf = [DeskLV]::VirtualAllocEx($hp, [IntPtr]::Zero, 4096, 0x3000, 0x04)
$idx = @{}
for ($i = 0; $i -lt $count; $i++) {
    $item = New-Object byte[] 64
    [BitConverter]::GetBytes([uint32]1).CopyTo($item, 0)                       # LVIF_TEXT
    [BitConverter]::GetBytes([int32]$i).CopyTo($item, 4)                       # iItem
    [BitConverter]::GetBytes([int64]($buf.ToInt64() + 512)).CopyTo($item, 24)  # pszText
    [BitConverter]::GetBytes([int32]256).CopyTo($item, 32)                     # cchTextMax
    $wr = [IntPtr]::Zero
    [void][DeskLV]::WriteProcessMemory($hp, $buf, $item, 64, [ref]$wr)
    [void][DeskLV]::SendMessage($lv, 0x1073, [IntPtr]$i, $buf)                 # LVM_GETITEMTEXTW
    $out = New-Object byte[] 512
    [void][DeskLV]::ReadProcessMemory($hp, [IntPtr]($buf.ToInt64() + 512), $out, 512, [ref]$wr)
    $n = [Text.Encoding]::Unicode.GetString($out).Split([char]0)[0]
    if (-not $idx.ContainsKey($n)) { $idx[$n] = $i }
}

# ---- Classify real desktop items ----
$info = @{}
foreach ($it in (Get-ChildItem -LiteralPath ([Environment]::GetFolderPath('Desktop')) | Where-Object { $_.Name -notlike '.*' })) {
    $disp = if ($it.PSIsContainer) { $it.Name } else { $it.BaseName }
    $info[$disp] = $it
}
# Use every ListView item (includes public-desktop and system shortcuts), but leave the Recycle Bin in place
$script:pool = @($idx.Keys | Where-Object { $_ -notlike 'Geri D*' })

function Take([string[]]$pats) {
    $out = New-Object System.Collections.ArrayList
    foreach ($p in $pats) {
        foreach ($n in @($script:pool | Where-Object { $_ -like $p } | Sort-Object)) {
            if (-not $out.Contains($n)) { [void]$out.Add($n) }
        }
    }
    $script:pool = @($script:pool | Where-Object { -not $out.Contains($_) })
    return ,@($out)
}

$appRows = @()
foreach ($pats in $appGroups) { $g = Take $pats; if ($g.Count -gt 0) { $appRows += ,$g } }

$gameLaunch = Take $launchPats
$urlGames   = @($script:pool | Where-Object { $info[$_].Extension -eq '.url' } | Sort-Object)
$script:pool = @($script:pool | Where-Object { $urlGames -notcontains $_ })
$gameRows = @($gameLaunch) + @($urlGames)

$fileRows = @($script:pool | Sort-Object)   # folders and everything unclassified

# ---- Build the placement plan ----
$plan = New-Object System.Collections.ArrayList
function Add-Block([object[]]$names, [int]$baseCol, [int]$startRow) {
    $i = 0
    foreach ($n in $names) {
        [void]$plan.Add([pscustomobject]@{ Name = $n; Col = $baseCol + ($i % 2); Row = $startRow + [math]::Floor($i / 2) })
        $i++
    }
    return $startRow + [math]::Ceiling($names.Count / 2)
}

# Apps: groups separated by one empty row
$r = 0
foreach ($g in $appRows) { $r = Add-Block $g 0 $r; $r++ }
# Files: two columns, going down
[void](Add-Block $fileRows 3 0)
# Games: two columns, going down
[void](Add-Block $gameRows 6 0)

# Recycle Bin moves first to the empty gap column (col 2, row 0) so it no longer blocks cell 0,0
foreach ($rbName in @($idx.Keys | Where-Object { $_ -like 'Geri D*' })) {
    $plan.Insert(0, [pscustomobject]@{ Name = $rbName; Col = 2; Row = 0 })
}

# ---- Capacity check ----
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$maxRow = [math]::Floor(($wa.Height - 20) / $cy) - 1
$over = @($plan | Where-Object { $_.Row -gt $maxRow })
if ($over.Count -gt 0) {
    Write-Warning ("Rows beyond screen height (max row $maxRow): " + (($over | ForEach-Object { $_.Name }) -join ', '))
}

# ---- Apply positions ----
$applied = 0
$missing = @()
foreach ($p in $plan) {
    if (-not $idx.ContainsKey($p.Name)) { $missing += $p.Name; continue }
    $x = 10 + $p.Col * $cx
    $y = 10 + $p.Row * $cy
    $lp = [IntPtr]($x -bor ($y -shl 16))
    $res = [DeskLV]::SendMessage($lv, 0x100F, [IntPtr]$idx[$p.Name], $lp)  # LVM_SETITEMPOSITION
    if ($res.ToInt64() -ne 0) { $applied++ }
}

[void][DeskLV]::VirtualFreeEx($hp, $buf, 0, 0x8000)
[void][DeskLV]::CloseHandle($hp)

$plan | Sort-Object Col, Row | Format-Table Col, Row, Name -AutoSize
Write-Host "Placed: $applied of $($plan.Count)"
if ($missing.Count -gt 0) { Write-Warning ("Not found on desktop listview: " + ($missing -join ', ')) }
