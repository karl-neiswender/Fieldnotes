Add-Type -AssemblyName System.Drawing
$root = $PSScriptRoot
$names = @('skinning','mining','herbalism','fishing','cloth','play','pause','stop','statistics','share','warning','book','treasure')
$labels = @('Skinning','Mining','Herbalism','Fishing','Cloth','Play','Pause','Stop','Statistics','Share','Warning','Book','Treasure')

function New-Icon($name) {
    $source = [System.Drawing.Bitmap]::new((Join-Path $root ($name + '.png')))
    $left = $source.Width; $top = $source.Height; $right = 0; $bottom = 0
    for ($y = 0; $y -lt $source.Height; $y++) {
        for ($x = 0; $x -lt $source.Width; $x++) {
            $c = $source.GetPixel($x, $y)
            if ($c.A -ge 20) {
                if ($x -lt $left) { $left = $x }
                if ($x -gt $right) { $right = $x }
                if ($y -lt $top) { $top = $y }
                if ($y -gt $bottom) { $bottom = $y }
            } elseif ($c.A -gt 0) {
                $source.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
            }
        }
    }
    $width = $right - $left + 1; $height = $bottom - $top + 1
    $scale = [Math]::Min(56.0 / $width, 56.0 / $height)
    $w = [int][Math]::Round($width * $scale); $h = [int][Math]::Round($height * $scale)
    $icon = [System.Drawing.Bitmap]::new(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($icon)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $dest = [System.Drawing.Rectangle]::new([int][Math]::Floor((64-$w)/2), [int][Math]::Floor((64-$h)/2), $w, $h)
    $crop = [System.Drawing.Rectangle]::new($left, $top, $width, $height)
    $g.DrawImage($source, $dest, $crop, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose(); $source.Dispose()
    $icon.Save((Join-Path $root ($name + '-64.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    return $icon
}

$sheet = [System.Drawing.Bitmap]::new(1080, 830, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$canvas = [System.Drawing.Graphics]::FromImage($sheet)
$canvas.Clear([System.Drawing.Color]::FromArgb(255, 20, 19, 17))
$canvas.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$head = [System.Drawing.Font]::new('Georgia', 19)
$body = [System.Drawing.Font]::new('Arial', 11)
$small = [System.Drawing.Font]::new('Arial', 9)
$gold = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 255, 215, 94))
$pale = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 224, 220, 210))
$sub = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 154, 150, 141))
$panel = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 43, 37, 30))
$edge = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 91, 77, 49), 1)
$canvas.DrawString('Fieldnotes icons  |  painted relief pass', $head, $gold, 26, 20)
$canvas.DrawString('Forever Goal Tracker references', $body, $pale, 27, 68)
$refs = @('gear-reference.png','ref-note-white.png','ref-pin-white.png','ref-plus-white.png')
for ($j = 0; $j -lt $refs.Count; $j++) {
    $refPath = Join-Path $root $refs[$j]
    $ref = [System.Drawing.Bitmap]::new($refPath)
    $canvas.DrawImage($ref, [System.Drawing.Rectangle]::new(350 + 50*$j, 63, 36, 36))
    $ref.Dispose()
}
$canvas.DrawString('64 px asset', $small, $sub, 73, 110)
$canvas.DrawString('18 px in dock', $small, $sub, 172, 110)
for ($i = 0; $i -lt $names.Count; $i++) {
    $col = $i % 3; $row = [int][Math]::Floor($i / 3)
    $x = 26 + 350*$col; $y = 135 + 135*$row
    $rect = [System.Drawing.Rectangle]::new($x, $y, 330, 116)
    $canvas.FillRectangle($panel, $rect); $canvas.DrawRectangle($edge, $rect)
    $icon = New-Icon $names[$i]
    $canvas.DrawImage($icon, [System.Drawing.Rectangle]::new($x+20, $y+18, 64, 64))
    $canvas.DrawImage($icon, [System.Drawing.Rectangle]::new($x+139, $y+42, 18, 18))
    $canvas.DrawString($labels[$i], $body, $gold, $x+20, $y+88)
    $icon.Dispose()
}
$sheet.Save((Join-Path $root 'Icon-sheet.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Dispose(); $sheet.Dispose()
$head.Dispose(); $body.Dispose(); $small.Dispose(); $gold.Dispose(); $pale.Dispose(); $sub.Dispose(); $panel.Dispose(); $edge.Dispose()
