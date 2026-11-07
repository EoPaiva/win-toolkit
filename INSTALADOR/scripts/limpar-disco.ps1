# Limpa espaco em disco e caches. So arquivos descartaveis e dados do proprio usuario.
# Nao mexe no registro de execucao do sistema (Amcache, Shimcache, BAM, USN Journal, Event Log): isso nao e limpeza de disco.
param([switch]$Simular)
. "$PSScriptRoot\comum.ps1"

function Soma($paths) {
    $b = 0L
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            try { $s = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; if ($s) { $b += $s } } catch { }
        }
    }
    [long]$b
}
function Esvaziar($paths) {
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { }
        }
    }
}

$script:TotalMB = 0.0
function Categoria([string]$nome, $paths) {
    if (Test-Cancelado) { Write-Log "[cancelado] $nome"; return }
    Write-Log "[....] $nome"
    $mb = [math]::Round((Soma $paths) / 1MB, 1)
    if (-not $Simular) { Esvaziar $paths }
    $script:TotalMB += $mb
    $rotulo = if ($Simular) { 'estimado' } else { 'liberado' }
    Write-Log ("[ ok ] {0} - {1} ~{2} MB" -f $nome, $rotulo, $mb)
}
function Acao([string]$nome, [scriptblock]$a) {
    if (Test-Cancelado) { Write-Log "[cancelado] $nome"; return }
    Write-Log "[....] $nome"
    if (-not $Simular) { try { & $a } catch { Write-Log "  | $($_.Exception.Message)" } }
    Write-Log "[ ok ] $nome"
}

# So o cache dos navegadores, nunca cookies, senhas ou historico.
$navegadores = @()
foreach ($base in "$env:LOCALAPPDATA\Google\Chrome\User Data", "$env:LOCALAPPDATA\Microsoft\Edge\User Data", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data") {
    if (Test-Path -LiteralPath $base) {
        Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } | ForEach-Object {
            $navegadores += Join-Path $_.FullName 'Cache'
            $navegadores += Join-Path $_.FullName 'Code Cache'
            $navegadores += Join-Path $_.FullName 'GPUCache'
            $navegadores += Join-Path $_.FullName 'Service Worker\CacheStorage'
        }
    }
}

Write-Log '@total 9'
$livreAntes = (Get-PSDrive C).Free

Categoria 'Temporarios' @($env:TEMP, "$env:windir\Temp", "$env:LOCALAPPDATA\Temp")
Categoria 'Logs antigos' @("$env:windir\Logs\CBS", "$env:windir\Logs\DISM", "$env:windir\Panther", "$env:windir\Minidump", "$env:windir\LiveKernelReports", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:LOCALAPPDATA\Microsoft\Windows\WER")
Categoria 'Miniaturas e icones' @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer")
Categoria 'Cache dos navegadores' $navegadores

# Cache do Windows Update: parar o servico antes de limpar, religar depois.
$pastaWU = "$env:windir\SoftwareDistribution\Download"
$mbWU = [math]::Round((Soma @($pastaWU)) / 1MB, 1)
Acao ("Cache do Windows Update (~$mbWU MB)") {
    $svc = @('wuauserv', 'bits') | ForEach-Object { Get-Service $_ -ErrorAction SilentlyContinue }
    $rodando = @($svc | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.Name })
    foreach ($s in $rodando) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
    Esvaziar @($pastaWU)
    foreach ($s in $rodando) { Start-Service $s -ErrorAction SilentlyContinue }
}
if (-not $Simular) { $script:TotalMB += $mbWU }

Acao 'Cache de distribuicao (Delivery Optimization)' { Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue }
Acao 'Componentes antigos (DISM StartComponentCleanup)' { & dism.exe /Online /Cleanup-Image /StartComponentCleanup /NoRestart | Out-Null }
Acao 'Lixeira' { Clear-RecycleBin -Force -ErrorAction SilentlyContinue }
Acao 'Cache de DNS' { & ipconfig.exe /flushdns | Out-Null }

$ganho = [math]::Round(((Get-PSDrive C).Free - $livreAntes) / 1MB, 0)
if ($Simular) { Write-Log ("cleanup.done mode=dry-run: ~{0:N0} MB estimados em arquivos, nada foi apagado" -f $script:TotalMB) Green }
else { Write-Log ("cleanup.done: espaco livre subiu {0:N0} MB (DISM, Lixeira e distribuicao tambem contam)" -f $ganho) Green }
