# Funcoes comuns. Tudo aqui precisa rodar no Windows PowerShell 5.1, o unico presente num Windows recem-instalado.
$ErrorActionPreference = 'Continue'
$script:Raiz = Split-Path -Parent $PSScriptRoot
if (-not $env:SETUP_DADOS) { $env:SETUP_DADOS = Join-Path $env:USERPROFILE 'SetupMateus' }
$script:Dados = $env:SETUP_DADOS
$script:Logs = Join-Path $script:Dados 'logs'
$script:Estado = Join-Path $script:Dados 'estado.txt'
$script:Relatorio = Join-Path $script:Dados 'relatorio.txt'
New-Item -ItemType Directory -Force $script:Logs | Out-Null

# UTF-8 sem BOM: o Claude Code e o Codex leem esses arquivos e um BOM quebra o JSON.
function Write-Utf8([string]$Caminho, [string]$Texto) {
    $pasta = Split-Path -Parent $Caminho
    if ($pasta) { New-Item -ItemType Directory -Force $pasta | Out-Null }
    [IO.File]::WriteAllText($Caminho, $Texto, (New-Object Text.UTF8Encoding($false)))
}

function Read-Utf8([string]$Caminho) { [IO.File]::ReadAllText($Caminho, [Text.Encoding]::UTF8) }

function Write-Log([string]$Mensagem, [ConsoleColor]$Cor = 'Gray') {
    Write-Host $Mensagem -ForegroundColor $Cor
    Add-Content -LiteralPath (Join-Path $script:Logs 'instalador.log') -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $Mensagem) -Encoding UTF8
}

function Update-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u"
}

function Add-UserPath([string]$Pasta) {
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $u) { $u = '' }
    $partes = @($u -split ';' | Where-Object { $_ })
    if ($partes -notcontains $Pasta) {
        [Environment]::SetEnvironmentVariable('Path', (($partes + $Pasta) -join ';'), 'User')
    }
    Update-Path
}

function Test-Feito([string]$Nome) {
    (Test-Path -LiteralPath $script:Estado) -and ((Get-Content -LiteralPath $script:Estado) -contains $Nome)
}

function Add-Resultado([string]$Situacao, [string]$Nome, [string]$Detalhe = '') {
    Add-Content -LiteralPath $script:Relatorio -Value ("{0,-6} {1}  {2}" -f $Situacao, $Nome, $Detalhe) -Encoding UTF8
}

# Uma etapa que falha fica registrada e as seguintes continuam. Rodar de novo refaz so as que nao terminaram.
function Invoke-Etapa([string]$Nome, [scriptblock]$Acao) {
    if (Test-Feito $Nome) { Write-Log "[pulado] $Nome (ja feito)" DarkGray; return }
    Write-Log "[....] $Nome" Cyan
    $ok = $false; $detalhe = ''
    try {
        $saida = & $Acao
        if ($saida -is [array]) { $saida = $saida[-1] }
        if ($saida -is [string] -and $saida.StartsWith('FALHA')) { $detalhe = $saida } else { $ok = $true }
    } catch { $detalhe = "FALHA: $($_.Exception.Message)" }
    if ($ok) {
        Add-Content -LiteralPath $script:Estado -Value $Nome -Encoding UTF8
        Add-Resultado 'OK' $Nome
        Write-Log "[ ok ] $Nome" Green
    } else {
        Add-Resultado 'FALHOU' $Nome $detalhe
        Write-Log "[FALHOU] $Nome - $detalhe" Red
    }
}

# Roda um comando com limite de tempo, para um instalador travado nao segurar o resto.
function Invoke-ComTempo([string]$Exe, [string]$Argumentos, [int]$Minutos, [string]$LogNome) {
    $seguro = $LogNome -replace '[^\w.+-]', '_'
    $out = Join-Path $script:Logs "$seguro.out.log"
    $err = Join-Path $script:Logs "$seguro.err.log"
    $resolvido = (Get-Command $Exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $resolvido) { $resolvido = $Exe }
    # .cmd e .ps1 nao executam diretamente com redirecionamento.
    if ($resolvido -match '\.(cmd|bat)$') { $Argumentos = "/c `"`"$resolvido`" $Argumentos`""; $resolvido = "$env:ComSpec" }
    elseif ($resolvido -match '\.ps1$') { $Argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$resolvido`" $Argumentos"; $resolvido = 'powershell.exe' }
    $p = Start-Process -FilePath $resolvido -ArgumentList $Argumentos -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle  # sem isso o ExitCode volta vazio no PowerShell 5.1
    if (-not $p.WaitForExit($Minutos * 60000)) {
        & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
        return 1460
    }
    return $p.ExitCode
}

function Test-Internet {
    try {
        $r = Invoke-WebRequest -Uri 'https://cdn.winget.microsoft.com/cache/source.msix' -Method Head -UseBasicParsing -TimeoutSec 10
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Wait-Internet {
    $avisou = $false
    while (-not (Test-Internet)) {
        if (-not $avisou) {
            Write-Log 'Sem internet. Conecte no Wi-Fi na janela que abriu: o instalador continua sozinho quando a conexao voltar.' Yellow
            Start-Process 'ms-settings:network-wifi' -ErrorAction SilentlyContinue
            $avisou = $true
        }
        Start-Sleep -Seconds 5
    }
}

# Num Windows recem-instalado o winget so aparece depois que o App Installer termina de registrar.
function Initialize-Winget {
    Update-Path
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    if ($env:Path -notlike "*$alias*") { $env:Path = "$env:Path;$alias" }
    foreach ($tentativa in 1..12) {
        if (Get-Command winget.exe -ErrorAction SilentlyContinue) { break }
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 10
    }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        $pacotes = Join-Path $script:Raiz 'pacotes'
        Get-ChildItem -LiteralPath $pacotes -Filter '*x64*.appx' -ErrorAction SilentlyContinue | ForEach-Object {
            Add-AppxPackage -Path $_.FullName -ErrorAction SilentlyContinue
        }
        Get-ChildItem -LiteralPath $pacotes -Filter '*.msixbundle' -ErrorAction SilentlyContinue | ForEach-Object {
            Add-AppxPackage -Path $_.FullName -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 10
    }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget indisponivel' }
    & winget.exe source update --disable-interactivity 2>&1 | Out-Null
}

function Test-PacoteInstalado($Pacote) {
    $fonte = if ($Pacote.fonte) { $Pacote.fonte } else { 'winget' }
    $saida = & winget.exe list --id $Pacote.id --exact --source $fonte --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    return ($saida -match [regex]::Escape($Pacote.id))
}

# O resultado vem do "winget list" depois da instalacao, nao do codigo de saida do instalador.
function Install-Pacote($Pacote) {
    if (Test-PacoteInstalado $Pacote) { return 'OK' }
    $fonte = if ($Pacote.fonte) { $Pacote.fonte } else { 'winget' }
    $minutos = if ($Pacote.minutos) { [int]$Pacote.minutos } else { 25 }
    $a = "install --id `"$($Pacote.id)`" --exact --source $fonte --accept-package-agreements --accept-source-agreements --disable-interactivity --silent"
    if ($Pacote.escopo) { $a += " --scope $($Pacote.escopo)" }
    if ($Pacote.override) { $a += " --override `"$($Pacote.override)`"" }
    $codigo = 0
    foreach ($tentativa in 1..2) {
        $codigo = Invoke-ComTempo 'winget.exe' $a $minutos "winget-$($Pacote.id)"
        Update-Path
        if (Test-PacoteInstalado $Pacote) { break }
        Start-Sleep -Seconds 15
    }
    if ($Pacote.comando -and -not (Get-Command $Pacote.comando -ErrorAction SilentlyContinue)) {
        return "FALHA: comando '$($Pacote.comando)' nao encontrado (codigo $codigo)"
    }
    if (-not (Test-PacoteInstalado $Pacote)) { return "FALHA: nao aparece no winget (codigo $codigo)" }
    return 'OK'
}
