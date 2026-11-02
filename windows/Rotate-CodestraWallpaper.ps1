param(
    [string]$ConfigPath = "$env:USERPROFILE\Pictures\Codestra-Wallpaper\config.json"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CodestraWallpaperNative {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern bool SystemParametersInfo(int action, int param, string value, int flags);
}
"@

if (-not (Test-Path $ConfigPath)) { exit 0 }
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$outDir = Split-Path $ConfigPath
$out = Join-Path $outDir "wallpaper.jpg"
$statePath = Join-Path $outDir "state.json"
$exclude = @($config.exclude_patterns)

$files = @()
foreach ($source in @($config.photo_sources)) {
    if (-not (Test-Path $source)) { continue }
    $files += Get-ChildItem $source -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $photo = $_
            $photo.Extension -match '^\.(jpg|jpeg|png|bmp)$' -and
            -not ($exclude | Where-Object { $_ -and $photo.FullName -like "*$_*" })
        }
}
$files = @($files | Sort-Object FullName -Unique)
if ($files.Count -eq 0) { exit 0 }

$index = 0
if (Test-Path $statePath) {
    try { $index = [int](Get-Content $statePath -Raw | ConvertFrom-Json).index } catch {}
}
$index = $index % $files.Count
$chosen = $files[$index]
$next = ($index + 7) % $files.Count

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$w = [Math]::Max(1024, $screen.Width)
$h = [Math]::Max(768, $screen.Height)
$canvas = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::FromArgb(20,22,25))

try {
    $img = [System.Drawing.Image]::FromFile($chosen.FullName)
    $maxW = [int]($w * 0.70)
    $maxH = [int]($h * 0.70)
    $scale = [Math]::Min($maxW / $img.Width, $maxH / $img.Height)
    $drawW = [Math]::Max(1, [int]($img.Width * $scale))
    $drawH = [Math]::Max(1, [int]($img.Height * $scale))
    $x = [int](($w - $drawW) / 2)
    $y = [int](($h - $drawH) / 2)

    $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(100,0,0,0))
    $g.FillRectangle($shadowBrush, $x + 12, $y + 12, $drawW, $drawH)
    $shadowBrush.Dispose()

    $g.DrawImage($img, $x, $y, $drawW, $drawH)
    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150,220,220,220), 1)
    $g.DrawRectangle($borderPen, $x, $y, $drawW - 1, $drawH - 1)
    $borderPen.Dispose()
    $img.Dispose()

    $canvas.Save($out, [System.Drawing.Imaging.ImageFormat]::Jpeg)
}
finally {
    $g.Dispose()
    $canvas.Dispose()
}

@{
    index = $next
    selected = $chosen.FullName
    updated = (Get-Date).ToString("o")
    presentation = "medium-contained-centered-framed"
} | ConvertTo-Json | Set-Content -Encoding UTF8 $statePath

Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "0"
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0"
[CodestraWallpaperNative]::SystemParametersInfo(20,0,$out,3) | Out-Null
