<#
.SYNOPSIS
Generates a multi-resolution Windows .ico file from a high-resolution PNG image.

.DESCRIPTION
This script reads a PNG image and generates multiple scaled versions (16, 32, 48, 64, 128, 256px) 
using HighQualityBicubic interpolation. It then manually constructs the binary structure of an 
ICO file, embedding each generated PNG as a frame within the icon.
#>
param (
    [string]$InputPath,
    [string]$OutputPath
)
Add-Type -AssemblyName System.Drawing

$img = [System.Drawing.Image]::FromFile($InputPath)
$sizes = @(16, 32, 48, 64, 128, 256)

$ms = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($ms)

# --- ICO FILE HEADER (6 bytes) ---
# 2 bytes: Reserved (must be 0)
$writer.Write([int16]0)
# 2 bytes: Image Type (1 = ICO, 2 = CUR)
$writer.Write([int16]1) 
# 2 bytes: Number of images
$writer.Write([int16]$sizes.Length)

# Offset to the raw image data. The header is 6 bytes.
# Each directory entry (one per image) is 16 bytes.
$offset = 6 + (16 * $sizes.Length)
$pngStreams = @()

foreach ($s in $sizes) {
    # Generate the scaled image frame
    if ($s -eq 256 -and $img.Width -eq 256) {
        # Fast path: Use original image if it's exactly 256x256 to avoid re-compression artifacts
        $bmp = new-object System.Drawing.Bitmap($img)
    } else {
        # Create a new resized bitmap using high-quality rendering
        $bmp = New-Object System.Drawing.Bitmap($s, $s)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($img, 0, 0, $s, $s)
    }

    # Save the frame to a temporary memory stream as a raw PNG.
    # Windows natively supports completely standard PNG files inside the .ico container
    # for rendering large (256x256) and standard crisp icons with alpha channels.
    $pngMs = New-Object System.IO.MemoryStream
    $bmp.Save($pngMs, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngStreams += $pngMs
    $pngBytes = $pngMs.ToArray()

    # --- ICO DIRECTORY ENTRY (16 bytes per image) ---
    
    # In ICO files, width/height of 256 is represented by 0 (since it fits in a single byte)
    $w = if ($s -eq 256) { 0 } else { $s }
    $h = if ($s -eq 256) { 0 } else { $s }

    $writer.Write([byte]$w) # 1 byte: Width (0 = 256)
    $writer.Write([byte]$h) # 1 byte: Height (0 = 256)
    $writer.Write([byte]0)  # 1 byte: Color palette count (0 if no palette)
    $writer.Write([byte]0)  # 1 byte: Reserved (must be 0)
    $writer.Write([int16]1) # 2 bytes: Color planes
    $writer.Write([int16]32)# 2 bytes: Bits per pixel (32 for PNG with alpha)
    $writer.Write([int]$pngBytes.Length) # 4 bytes: Size of the image data in bytes
    $writer.Write([int]$offset)          # 4 bytes: Offset from start of file to the image data

    # Update offset for the next image frame
    $offset += $pngBytes.Length

    if ($g) { $g.Dispose(); $g = $null }
    $bmp.Dispose()
}

foreach ($pngMs in $pngStreams) {
    $writer.Write($pngMs.ToArray())
    $pngMs.Dispose()
}

$writer.Flush()
$bytes = $ms.ToArray()
[System.IO.File]::WriteAllBytes($OutputPath, $bytes)

$writer.Dispose()
$ms.Dispose()
$img.Dispose()
