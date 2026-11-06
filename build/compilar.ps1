# Compila dist\upaiva.dev.exe com o csc que ja vem no Windows. Nao precisa de SDK.
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$app = Join-Path $raiz 'app'
$dist = Join-Path $raiz 'dist'
[void][IO.Directory]::CreateDirectory($dist)

Add-Type -AssemblyName System.Drawing
$bmp = New-Object Drawing.Bitmap 256, 256
$g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
$g.Clear([Drawing.Color]::FromArgb(2, 10, 6))
$g.DrawRectangle((New-Object Drawing.Pen([Drawing.Color]::FromArgb(0, 255, 102), 10)), 5, 5, 246, 246)
$g.DrawString('>_', (New-Object Drawing.Font('Consolas', 118, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)), (New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(0, 255, 102))), 26, 52)
$g.Dispose()
$ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $png = $ms.ToArray()
$ico = Join-Path $dist 'icone.ico'
$b = New-Object IO.BinaryWriter([IO.File]::Create($ico))
$b.Write([uint16]0); $b.Write([uint16]1); $b.Write([uint16]1); $b.Write([byte]0); $b.Write([byte]0); $b.Write([byte]0); $b.Write([byte]0); $b.Write([uint16]1); $b.Write([uint16]32); $b.Write([uint32]$png.Length); $b.Write([uint32]22); $b.Write($png); $b.Close()

$fx = "$env:windir\Microsoft.NET\Framework64\v4.0.30319"
$wpf = "$fx\WPF"
$saida = Join-Path $dist 'upaiva.dev.exe'
& "$fx\csc.exe" /nologo /target:winexe /optimize+ /platform:anycpu /utf8output /codepage:65001 "/out:$saida" "/win32icon:$ico" "/resource:$app\ui.xaml,ui.xaml" "/r:$wpf\PresentationFramework.dll" "/r:$wpf\PresentationCore.dll" "/r:$wpf\WindowsBase.dll" "/r:$fx\System.Xaml.dll" "/r:$fx\System.Web.Extensions.dll" "/r:$fx\System.Core.dll" "$app\app.cs"
if ($LASTEXITCODE -ne 0) { throw "csc terminou com codigo $LASTEXITCODE" }
"gerado: $saida ({0:N0} KB)" -f ((Get-Item -LiteralPath $saida).Length / 1KB)
"copie para a pasta INSTALADOR antes de usar: o app procura programas.json e scripts\ ao lado dele."
