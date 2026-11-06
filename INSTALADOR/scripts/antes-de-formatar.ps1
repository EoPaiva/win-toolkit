# Roda no PC QUE SERA FORMATADO, a partir do pendrive. Nao apaga nada e nao copia programas, logs nem arquivos pessoais.
# Leva somente: dados do hardware, NOMES de programas do catalogo do winget e o driver das placas de rede fisicas.
# Windows PowerShell 5.1: o PC pode nao ter o PowerShell 7.
$raiz = Split-Path -Parent $PSScriptRoot
$h = $env:USERPROFILE

if ($env:COMPUTERNAME -eq 'MARINETE') {
    Write-Host 'Este e o PC de origem das configs, nao o que sera formatado.' -ForegroundColor Red
    Write-Host 'Rode este passo no outro PC. Nada foi feito.' -ForegroundColor Red
    exit 1
}
$admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "`n=== 1. Dados deste PC ===" -ForegroundColor Cyan
$sistema = Get-CimInstance Win32_ComputerSystem
$linhas = New-Object System.Collections.ArrayList
[void]$linhas.Add("Modelo: $($sistema.Manufacturer) $($sistema.Model)")
[void]$linhas.Add("Processador: $((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)")
[void]$linhas.Add("Memoria: $([math]::Round($sistema.TotalPhysicalMemory / 1GB)) GB")
[void]$linhas.Add("Windows atual: $((Get-CimInstance Win32_OperatingSystem).Caption)")
try {
    $lic = (Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKeyDescription
    [void]$linhas.Add("Licenca gravada na placa-mae: $(if ($lic) { $lic } else { 'nenhuma' })")
} catch { [void]$linhas.Add('Licenca gravada na placa-mae: nao lida') }
foreach ($d in Get-Disk) { [void]$linhas.Add("Disco $($d.Number): $($d.FriendlyName), $([math]::Round($d.Size / 1GB)) GB, $($d.BusType)") }
foreach ($v in Get-CimInstance Win32_VideoController) { [void]$linhas.Add("Video: $($v.Name)") }
foreach ($n in Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=True') { [void]$linhas.Add("Rede: $($n.Name)") }
if ($admin) {
    try { [void]$linhas.Add("TPM pronto: $((Get-Tpm).TpmReady)") } catch { [void]$linhas.Add('TPM: nao lido') }
    try { [void]$linhas.Add("Secure Boot ligado: $(Confirm-SecureBootUEFI)") } catch { [void]$linhas.Add('Secure Boot: indisponivel (BIOS em modo legado?)') }
}
$linhas | ForEach-Object { Write-Host "  $_" }
$linhas | Out-File -LiteralPath (Join-Path $raiz 'pc-alvo.txt') -Encoding utf8

Write-Host "`n=== 2. Programas: so os nomes, do catalogo oficial do winget ===" -ForegroundColor Cyan
# O instalador baixa a versao mais nova de cada um. Fora do catalogo nao entra: nada deste PC e copiado.
# Ficam de fora componentes do Windows, o que a limpeza remove e utilitarios de fabricante.
$ignorar = '^(Microsoft\.(VCLibs|UI\.Xaml|WindowsAppRuntime|AppInstaller|Edge|EdgeWebView2Runtime|Office|Teams|OneDrive|GamingApp|Outlook|365Copilot|Copilot|DotNet\.Native|WindowsTerminal|PowerShell|VCRedist|DotNet|OpenCLGLVulkan|GameInput|DirectX)|Nvidia\.|AMD\.|Intel\.|Realtek\.|Acer\.|ASUS\.|Lenovo\.|Dell\.|HP\.|MSI\.|Gigabyte\.)'
$arquivoLista = Join-Path $raiz 'programas-do-pc.txt'
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if ($winget) {
    $temp = Join-Path $env:TEMP "winget-export-$PID.json"
    & winget.exe export -o $temp --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    if (Test-Path -LiteralPath $temp) {
        $e = (Get-Content -LiteralPath $temp -Raw) | ConvertFrom-Json
        $ids = @($e.Sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier } | Where-Object { $_ -and $_ -notmatch $ignorar } | Sort-Object -Unique)
        [IO.File]::Delete($temp)
        $cabecalho = '# Programas para instalar na versao mais nova. Apague a linha do que voce nao quiser.'
        [IO.File]::WriteAllLines($arquivoLista, [string[]](@($cabecalho) + $ids), [Text.Encoding]::ASCII)
        $ids | ForEach-Object { Write-Host "  $_" }
        Write-Host "  $($ids.Count) programas anotados em $arquivoLista" -ForegroundColor Green
        Write-Host '  Programas fora do catalogo nao entram: instale a mao os que quiser.'
    } else { Write-Host '  O winget nao gerou a lista. O instalador segue so com a lista padrao.' -ForegroundColor Yellow }
} else { Write-Host '  Este PC nao tem winget. O instalador segue so com a lista padrao.' -ForegroundColor Yellow }

Write-Host "`n=== 3. Driver das placas de rede fisicas (o resto vem pelo Windows Update) ===" -ForegroundColor Cyan
$drv = Join-Path $raiz 'drivers'
$redes = @(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" | Where-Object { $_.DeviceID -match '^(PCI|USB|SDIO)\\' -and $_.InfName -match '^oem\d+\.inf$' })
$infs = @($redes | Select-Object -ExpandProperty InfName -Unique)
$redes | ForEach-Object { Write-Host "  $($_.DeviceName)  ($($_.InfName))" }
if (-not $infs.Count) {
    Write-Host '  Nenhum driver de rede de terceiros: o proprio Windows cuida da rede deste PC.' -ForegroundColor Green
} elseif ($admin) {
    if (Test-Path -LiteralPath $drv) { Get-ChildItem -LiteralPath $drv -Force | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force } }
    New-Item -ItemType Directory -Force $drv | Out-Null
    $falhas = 0
    foreach ($i in $infs) {
        & pnputil.exe /export-driver $i $drv | Out-Null
        if ($LASTEXITCODE -ne 0) { $falhas++; Write-Host "  Falhou ao copiar $i (codigo $LASTEXITCODE)" -ForegroundColor Red }
    }
    if (-not $falhas) { Write-Host "  $($infs.Count) driver(s) de rede copiados." -ForegroundColor Green }
    else { Write-Host '  Tenha cabo de rede ou o celular roteando por USB, ou baixe o driver no site do fabricante.' -ForegroundColor Yellow }
} else {
    Write-Host '  Sem permissao de administrador: abra pelo 1-ANTES-DE-FORMATAR.cmd e clique em Sim.' -ForegroundColor Yellow
}

Write-Host "`n=== 4. Isto sera apagado e NAO e copiado: decida o que guardar ===" -ForegroundColor Cyan
foreach ($p in 'Desktop', 'Documents', 'Downloads', 'Pictures', 'Videos', 'Music', 'Saved Games') {
    $o = Join-Path $h $p
    if (Test-Path -LiteralPath $o) {
        $t = (Get-ChildItem -LiteralPath $o -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band 0x400000) } | Measure-Object Length -Sum).Sum
        Write-Host ("{0,8:N1} GB  {1}" -f ($t / 1GB), $o) -ForegroundColor Yellow
    }
}
Write-Host 'Esta lista nao e completa: confira tambem o OneDrive, outras particoes e pastas na raiz do C:.'

Write-Host "`n=== 5. Antes de formatar ===" -ForegroundColor Cyan
Write-Host @'
- Abra INSTALADOR\programas-do-pc.txt e apague o que voce nao quer de volta.
- Chave do Windows Pro em maos, se este PC nao tiver licenca Pro digital.
- Senhas e favoritos sincronizados no navegador, ou exportados.
- Se guardar arquivos, nao traga de volta AppData, pastas de jogo, executaveis ou arquivos que voce nao reconheca.
'@
Write-Host "`nPronto. Nada foi apagado." -ForegroundColor Green
