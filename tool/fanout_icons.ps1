# Resize the master NOYPON icon into Android mipmap-* buckets.
# Runs without flutter_launcher_icons so that a plain `flutter build` works
# immediately after cloning.

Add-Type -AssemblyName System.Drawing

$root = Resolve-Path "$PSScriptRoot/.."
$src = Join-Path $root "assets/images/logo_noypon.png"
$srcFg = Join-Path $root "assets/images/logo_noypon_foreground.png"
if (-not (Test-Path $src)) {
    throw "Run generate_icons.ps1 first."
}

$targets = @(
    @{ Folder = "mipmap-mdpi";    Size = 48 },
    @{ Folder = "mipmap-hdpi";    Size = 72 },
    @{ Folder = "mipmap-xhdpi";   Size = 96 },
    @{ Folder = "mipmap-xxhdpi";  Size = 144 },
    @{ Folder = "mipmap-xxxhdpi"; Size = 192 }
)

$fgTargets = @(
    @{ Folder = "drawable-mdpi";    Size = 108 },
    @{ Folder = "drawable-hdpi";    Size = 162 },
    @{ Folder = "drawable-xhdpi";   Size = 216 },
    @{ Folder = "drawable-xxhdpi";  Size = 324 },
    @{ Folder = "drawable-xxxhdpi"; Size = 432 },
    @{ Folder = "drawable";         Size = 432 }
)

$resRoot = Join-Path $root "android/app/src/main/res"
$master = [System.Drawing.Image]::FromFile($src)
$masterFg = [System.Drawing.Image]::FromFile($srcFg)

function Save-Resized {
    param($Image, $OutPath, $Size)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($Image, 0, 0, $Size, $Size)
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

foreach ($t in $targets) {
    $dir = Join-Path $resRoot $t.Folder
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Save-Resized $master (Join-Path $dir "ic_launcher.png") $t.Size
    Write-Host "  Wrote $($t.Folder)/ic_launcher.png  ($($t.Size)px)"
}

foreach ($t in $fgTargets) {
    $dir = Join-Path $resRoot $t.Folder
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Save-Resized $masterFg (Join-Path $dir "ic_launcher_foreground.png") $t.Size
    Write-Host "  Wrote $($t.Folder)/ic_launcher_foreground.png  ($($t.Size)px)"
}

$master.Dispose()
$masterFg.Dispose()

Write-Host "Done."
