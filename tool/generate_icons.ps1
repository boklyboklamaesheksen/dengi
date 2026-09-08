# NOYPON VPN — icon generator
#
# Produces two PNGs in assets/images/ that the flutter_launcher_icons tool
# then fans out into every mipmap density:
#
#   logo_noypon.png             1024x1024  full launcher icon with aurora N
#   logo_noypon_foreground.png  1024x1024  transparent-bg version for adaptive
#
# Usage (from project root):
#   pwsh ./tool/generate_icons.ps1
#
# Only the standard Windows GDI+ library is used — no extra deps required.

Add-Type -AssemblyName System.Drawing

$root = Resolve-Path "$PSScriptRoot/.."
$assets = Join-Path $root "assets/images"
New-Item -ItemType Directory -Force -Path $assets | Out-Null

function New-Icon {
    param(
        [int]$Size,
        [bool]$SolidBackground,
        [string]$OutPath
    )

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    if ($SolidBackground) {
        $base = [System.Drawing.Color]::FromArgb(255, 7, 8, 13)
        $radius = [int]($Size * 0.22)
        $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $d = $radius * 2
        $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
        $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
        $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
        $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
        $path.CloseFigure()
        $brush = New-Object System.Drawing.SolidBrush($base)
        $g.FillPath($brush, $path)
        $brush.Dispose()
        $path.Dispose()
    }

    # Aurora ring — rounded-square border with gradient
    $pad = [int]($Size * 0.12)
    $innerSize = $Size - 2 * $pad
    $innerRect = New-Object System.Drawing.Rectangle($pad, $pad, $innerSize, $innerSize)

    $indigo = [System.Drawing.Color]::FromArgb(255, 79, 70, 229)
    $magenta = [System.Drawing.Color]::FromArgb(255, 217, 70, 239)
    $coral = [System.Drawing.Color]::FromArgb(255, 249, 115, 22)

    $gradRect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
    $gradBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $gradRect, $indigo, $coral, 35.0)

    $colorBlend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
    $colorBlend.Colors = @($indigo, $magenta, $coral)
    $colorBlend.Positions = @(0.0, 0.55, 1.0)
    $gradBrush.InterpolationColors = $colorBlend

    # Draw aurora-filled "N" monogram
    $fontSize = [Single]($Size * 0.66)
    $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddString("N", $font.FontFamily, [int]$font.Style, $fontSize, $innerRect, $sf)
    $g.FillPath($gradBrush, $path)

    # Subtle highlight stroke on the top-left edge of the N to add depth
    $highlight = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 255, 255, 255), [Single]($Size * 0.004))
    $g.DrawPath($highlight, $path)

    $path.Dispose()
    $gradBrush.Dispose()
    $font.Dispose()
    $sf.Dispose()

    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Host "Saved $OutPath"
}

New-Icon -Size 1024 -SolidBackground $true -OutPath (Join-Path $assets "logo_noypon.png")
New-Icon -Size 1024 -SolidBackground $false -OutPath (Join-Path $assets "logo_noypon_foreground.png")

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "  flutter pub get"
Write-Host "  dart run flutter_launcher_icons"
