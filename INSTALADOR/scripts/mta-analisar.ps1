# Diagnostico do Anti-crash MTA: SOMENTE LEITURA. Grava so mta.json na pasta de dados do app.
param(
    [string]$RaizRegistro = 'HKLM:\SOFTWARE\WOW6432Node\Multi Theft Auto: San Andreas All',
    [string]$PastaDocs = [Environment]::GetFolderPath('MyDocuments')
)
. "$PSScriptRoot\mta-comum.ps1"

$ChavesConfig = $script:ChavesLeve + 'display_fullscreen_style', 'streaming_memory', 'process_priority'

Write-Log '@total 5'
Write-Log 'mta.scan start mode=read-only' Cyan

$estado = [ordered]@{
    instalado = $false; versao = ''; pastaMta = ''; pastaGta = ''; jogoExe = ''; mtaExe = ''
    crash = $null; redefinicoes = 0; placa = ''; temIntegrada = $false; temDedicada = $false; sessaoNaIntegrada = $false; tela = 0
    mods = @(); sobreposicoes = @(); ramTotalGB = 0; ramUsoPct = 0; driverAnos = 0
    componentes = @(); gtaSet = $false; streamingMinimo = 128; config = @{}; avisos = @(); correcoes = @()
}
$mta = $null

Passo 'Localizar o MTA' {
    $script:mtaLocal = Find-Mta $RaizRegistro
    if (-not $script:mtaLocal) { Write-Log '  | MTA nao encontrado neste PC'; return }
    $estado.instalado = $true
    $estado.versao = $script:mtaLocal.Versao
    $estado.pastaMta = $script:mtaLocal.PastaMta
    $estado.pastaGta = $script:mtaLocal.PastaGta
    $estado.jogoExe = $script:mtaLocal.JogoExe
    $estado.mtaExe = $script:mtaLocal.MtaExe
    Write-Log "  | versao=$($estado.versao) pasta=$($estado.pastaMta)"
}
$mta = $script:mtaLocal

Passo 'Ultimo crash' {
    if (-not $mta) { return }
    $c = Get-UltimoCrash (Join-Path $mta.PastaMta 'MTA\core.log')
    if (-not $c) { Write-Log '  | nenhum crash registrado'; return }
    $cat = Get-CategoriaOffset $c.Offset $c.Modulo $c.Codigo
    $estado.crash = [ordered]@{ hora = $c.Hora.ToString('s'); modulo = $(if ($c.Modulo) { Split-Path -Leaf $c.Modulo } else { 'fora de qualquer módulo' }); codigo = $c.Codigo; offset = $c.Offset; categoria = $cat.Categoria; mensagem = $cat.Mensagem }
    Write-Log "  | crash offset=$($c.Offset) code=$($c.Codigo) category=$($cat.Categoria)"
}

Passo 'Video e memoria' {
    $placas = @(Get-CimInstance Win32_VideoController)
    $ehIntegrada = { param($nome) $nome -match 'Intel|Radeon\(TM\) Graphics|Vega' }
    $estado.temIntegrada = [bool]@($placas | Where-Object { & $ehIntegrada $_.Name }).Count
    $estado.temDedicada = [bool]@($placas | Where-Object { -not (& $ehIntegrada $_.Name) }).Count
    $so = Get-CimInstance Win32_OperatingSystem
    $ramMB = [int]($so.TotalVisibleMemorySize / 1024)
    $estado.ramTotalGB = [math]::Round($ramMB / 1024)
    $estado.ramUsoPct = [int](100 - 100 * $so.FreePhysicalMemory / $so.TotalVisibleMemorySize)
    if ($mta) {
        $sessao = Get-SessaoGrafica (Join-Path $mta.PastaMta 'MTA\logs\logfile.txt')
        $estado.redefinicoes = $sessao.Redefinicoes
        $estado.placa = $sessao.Placa
        $estado.sessaoNaIntegrada = [bool]($sessao.Placa -and (& $ehIntegrada $sessao.Placa))
    }
    $emUso = @($placas | Where-Object { $_.Name -eq $estado.placa })[0]
    $vram = 0
    if ($emUso -and $emUso.AdapterRAM -gt 0) { $vram = [int]($emUso.AdapterRAM / 1MB) }
    $estado.streamingMinimo = Get-StreamingMinimo $ramMB $vram
    if ($emUso -and $emUso.DriverDate) {
        $estado.driverAnos = [math]::Round(((Get-Date) - $emUso.DriverDate).TotalDays / 365, 1)
        if ($estado.driverAnos -gt 2) { $estado.avisos += "O driver da placa em uso tem $($estado.driverAnos) anos. Veja a aba Drivers." }
    }
    if ($estado.ramUsoPct -ge 85) { $estado.avisos += "RAM em $($estado.ramUsoPct)% de uso agora. Feche o que não precisar antes de jogar." }
    Write-Log "  | restores=$($estado.redefinicoes) gpu=$($estado.placa) ram=$($estado.ramTotalGB)GB used=$($estado.ramUsoPct)%"
}

Passo 'Mods, sobreposicoes e configuracao' {
    if ($mta -and $mta.PastaGta -and (Test-Path -LiteralPath $mta.PastaGta)) {
        $estado.mods = @(Get-ModsGta $mta.PastaGta)
    }
    $estado.sobreposicoes = @(Get-Process -Name Discord, RTSS, MSIAfterburner, Overwolf, Fraps, obs64 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique)
    if ($estado.sobreposicoes.Count) { $estado.avisos += "Sobreposições abertas: $($estado.sobreposicoes -join ', '). Elas podem interferir no vídeo; teste sem elas." }
    $estado.gtaSet = Test-Path -LiteralPath (Join-Path $PastaDocs 'GTA San Andreas User Files\gta_sa.set')
    if ($mta) {
        $cfg = Join-Path $mta.PastaMta 'MTA\config\coreconfig.xml'
        if (Test-Path -LiteralPath $cfg) {
            $estado.config = Get-ConfigMta $cfg $ChavesConfig
            $estado.tela = [int]"0$($estado.config['display_fullscreen_style'])"
        } else { Write-Log '  | coreconfig.xml ainda nao existe: abra o MTA uma vez' }
    }
    Write-Log "  | mods=$(@($estado.mods).Count) overlays=$(@($estado.sobreposicoes).Count)"
}

Passo 'Componentes do MTA' {
    if (-not $mta) { return }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { $estado.avisos += 'winget indisponível: não deu para conferir os componentes.'; return }
    $instalados = & winget.exe list --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    $pendentes = & winget.exe list --source winget --upgrade-available --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    $programas = (Read-Utf8 (Join-Path $script:Raiz 'programas.json')) | ConvertFrom-Json
    $pedidos = @(Get-ComponentesJogos $programas $instalados $pendentes | ForEach-Object { $_.pedido })
    $estado.componentes = @($pedidos | Where-Object { $script:PacotesMta -contains ($_ -split ':', 2)[-1] })
    Write-Log "  | components=$($estado.componentes.Count)"
}

if ($mta) { $estado.correcoes = @(Get-CorrecoesMta ([pscustomobject]$estado)) }
Write-Utf8 (Join-Path $script:Dados 'mta.json') (([pscustomobject]$estado) | ConvertTo-Json -Depth 5)
Write-Log "mta.scan done corrections=$(@($estado.correcoes).Count)" Green
