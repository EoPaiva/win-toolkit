# Funcoes comuns. Tudo aqui precisa rodar no Windows PowerShell 5.1, o unico presente num Windows recem-instalado.
$ErrorActionPreference = 'Continue'
$script:Raiz = Split-Path -Parent $PSScriptRoot
if (-not $env:SETUP_DADOS) { $env:SETUP_DADOS = Join-Path $env:USERPROFILE 'SetupMateus' }
$script:Dados = $env:SETUP_DADOS
$script:Logs = Join-Path $script:Dados 'logs'
$script:Estado = Join-Path $script:Dados 'estado.txt'
$script:Relatorio = Join-Path $script:Dados 'relatorio.txt'
$script:PrefixoSaida = ''
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
    # O app le este arquivo enquanto ele cresce, e a parte elevada escreve nele em outro processo.
    $bytes = [Text.Encoding]::UTF8.GetBytes(("{0:HH:mm:ss} {1}`r`n" -f (Get-Date), $Mensagem))
    Add-Bytes (Join-Path $script:Logs 'instalador.log') $bytes
}

# Sem compartilhar a escrita: dois processos abrindo juntos sobrescreveriam linhas um do outro.
function Add-Bytes([string]$Caminho, [byte[]]$Bytes) {
    foreach ($tentativa in 1..200) {
        try {
            $f = New-Object IO.FileStream($Caminho, 'Append', 'Write', 'Read,Delete')
            try { $f.Write($Bytes, 0, $Bytes.Length) } finally { $f.Close() }
            break
        } catch { Start-Sleep -Milliseconds 15 }
    }
}

function Add-Linha([string]$Caminho, [string]$Texto) { Add-Bytes $Caminho ([Text.Encoding]::UTF8.GetBytes("$Texto`r`n")) }

# New-Item -Force numa chave de registro que ja existe apaga os valores e as subchaves dela. So cria o que falta.
function Confirm-ChaveRegistro([string]$Caminho) {
    if (-not (Test-Path -LiteralPath $Caminho)) { New-Item -Path $Caminho -Force -ErrorAction SilentlyContinue | Out-Null }
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
    (Test-Path -LiteralPath $script:Estado) -and ((Get-Content -LiteralPath $script:Estado -Encoding UTF8) -contains $Nome)
}

function Add-Resultado([string]$Situacao, [string]$Nome, [string]$Detalhe = '') {
    Add-Linha $script:Relatorio ("{0,-6} {1}  {2}" -f $Situacao, $Nome, $Detalhe)
}

# O app cria cancelar.flag no botao Cancelar. O arquivo vale entre o processo comum e o elevado.
function Test-Cancelado { Test-Path -LiteralPath (Join-Path $script:Dados 'cancelar.flag') }

function Test-Pular([string]$Nome) {
    $arq = Join-Path $script:Dados 'pular.txt'
    if (-not (Test-Path -LiteralPath $arq)) { return $false }
    foreach ($p in Get-Content -LiteralPath $arq -Encoding UTF8) { if ($p -and $Nome -like $p) { return $true } }
    return $false
}

# Uma etapa que falha fica registrada e as seguintes continuam. Rodar de novo refaz so as que nao terminaram.
# Uma etapa que falha fica registrada e as seguintes continuam. Rodar de novo refaz so as que nao terminaram.
function Invoke-Etapa([string]$Nome, [scriptblock]$Acao) {
    if (Test-Cancelado) { Write-Log "[cancelado] $Nome" DarkGray; Add-Resultado 'CANCELADO' $Nome; return }
    if (Test-Pular $Nome) { Write-Log "[ignorado] $Nome" DarkGray; Add-Resultado 'PULADO' $Nome; return }
    if (Test-Feito $Nome) { Write-Log "[pulado] $Nome (já feito)" DarkGray; return }
    Write-Log "[....] $Nome" Cyan
    $ok = $false; $detalhe = ''
    try {
        $saida = & $Acao
        if ($saida -is [array]) { $saida = $saida[-1] }
        if ($saida -is [string] -and $saida.StartsWith('FALHA')) { $detalhe = $saida } else { $ok = $true }
    } catch { $detalhe = "FALHA: $($_.Exception.Message)" }
    # Interrompida nao conta como feita: sem isso a etapa nunca seria refeita.
    if (Test-Cancelado) { Write-Log "[cancelado] $Nome" DarkGray; Add-Resultado 'CANCELADO' $Nome; return }
    # Interrompida nao conta como feita: sem isso a etapa nunca seria refeita.
    if (Test-Cancelado) { Write-Log "[cancelado] $Nome" DarkGray; Add-Resultado 'CANCELADO' $Nome; return }
    if ($ok) {
        Add-Linha $script:Estado $Nome
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
    Write-Log "`$ $([IO.Path]::GetFileName($resolvido)) $Argumentos"
    $p = Start-Process -FilePath $resolvido -ArgumentList $Argumentos -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle  # sem isso o ExitCode volta vazio no PowerShell 5.1
    Write-Log "proc.spawn pid=$($p.Id) timeout=${Minutos}m"
    $cron = [Diagnostics.Stopwatch]::StartNew()
    $pos = 0L
    while (-not $p.WaitForExit(700)) {
        $pos = Show-Saida $out $pos
        if (Test-Cancelado) {
            & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
            Write-Log "proc.kill pid=$($p.Id) reason=cancelled"
            return 1223
        }
        if ($cron.Elapsed.TotalMinutes -ge $Minutos) {
            & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
            Write-Log "proc.kill pid=$($p.Id) reason=timeout"
            return 1460
        }
    }
    $pos = Show-Saida $out $pos
    Write-Log ("proc.exit pid={0} code={1} elapsed={2:N1}s" -f $p.Id, $p.ExitCode, $cron.Elapsed.TotalSeconds)
    return $p.ExitCode
}

# Mostra no terminal o que o programa esta imprimindo, sem as barras de progresso.
function Show-Saida([string]$arq, [long]$pos) {
    try {
        $f = New-Object IO.FileStream($arq, 'Open', 'Read', 'ReadWrite,Delete')
        try {
            if ($f.Length -le $pos) { return $pos }
            [void]$f.Seek($pos, 'Begin')
            $b = New-Object byte[] ($f.Length - $pos)
            $n = $f.Read($b, 0, $b.Length)
            $pos += $n
            # winget escreve em UTF-8; ping, sfc e DISM escrevem na pagina OEM do console.
            $t = try { (New-Object Text.UTF8Encoding($false, $true)).GetString($b, 0, $n) } catch { [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage).GetString($b, 0, $n) }
            foreach ($l in ($t -split "[\r\n]+")) {
                $x = ($l -replace '[^\x20-\x7EÀ-ÿ]', '').Trim()
                if ($x.Length -ge 4 -and $x -match '[A-Za-z]{3}' -and $x -notmatch '^[-\\|/\s]+$') { Write-Log ("  | " + $script:PrefixoSaida + $x.Substring(0, [Math]::Min(130, $x.Length))) }
            }
        } finally { $f.Close() }
    } catch { }
    return $pos
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
        if (Test-Cancelado) { Write-Log 'net.wait cancelled'; return }
        if (-not $avisou) {
            Write-Log 'Sem internet. Conecte no Wi-Fi na janela que abriu: o instalador continua sozinho quando a conexão voltar.' Yellow
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
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget indisponível' }
    & winget.exe source update --disable-interactivity 2>&1 | Out-Null
}

# Sinal de que o componente esta aqui mesmo sem o winget saber: o DirectX legado, por exemplo, nao aparece no "winget list".
function Test-SinalPacote($Pacote) {
    [bool]($Pacote.detecta -and (Test-Path -Path ([Environment]::ExpandEnvironmentVariables($Pacote.detecta))))
}

function Test-PacoteInstalado($Pacote) {
    if (Test-SinalPacote $Pacote) { return $true }
    $fonte = if ($Pacote.fonte) { $Pacote.fonte } else { 'winget' }
    $saida = & winget.exe list --id $Pacote.id --exact --source $fonte --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    return ($saida -match [regex]::Escape($Pacote.id))
}

function Test-AtualizacaoPendente($Pacote) {
    $fonte = if ($Pacote.fonte) { $Pacote.fonte } else { 'winget' }
    $saida = & winget.exe list --id $Pacote.id --exact --source $fonte --upgrade-available --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    return ($saida -match [regex]::Escape($Pacote.id))
}

function Test-NetFx3 {
    (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' -Name Install -ErrorAction SilentlyContinue).Install -eq 1
}

function Enable-NetFx3 {
    $c = Invoke-ComTempo 'dism.exe' '/Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart /Quiet' 30 'netfx3'
    if ($c -in 0, 3010) { 'OK' } else { "FALHA: codigo $c" }
}

# Componentes de jogos que faltam ou estao defasados. A lista e a mesma de Dependencias (AIO) em programas.json.
# $Instalados e $Pendentes sao a saida inteira de "winget list": o ID so vale com espaco dos dois lados.
function Get-ComponentesJogos($Programas, [string]$Instalados, [string]$Pendentes) {
    foreach ($p in @($Programas.maquina | Where-Object { $_.grupo -eq 'Dependências (AIO)' })) {
        $rx = "(?<!\S)$([regex]::Escape($p.id))(?!\S)"
        if ($Pendentes -match $rx) { [pscustomobject]@{ rotulo = $p.rotulo; estado = 'atualizar'; pedido = "atualizar:$($p.id)" } }
        elseif (-not ($Instalados -match $rx) -and -not (Test-SinalPacote $p)) { [pscustomobject]@{ rotulo = $p.rotulo; estado = 'faltando'; pedido = "winget:$($p.id)" } }
    }
    if (-not (Test-NetFx3)) { [pscustomobject]@{ rotulo = '.NET Framework 3.5'; estado = 'faltando'; pedido = 'netfx3' } }
}

# O resultado vem do "winget list" depois da instalacao, nao do codigo de saida do instalador.
function Install-Pacote($Pacote, [switch]$Atualizar) {
    if (-not $Atualizar -and (Test-PacoteInstalado $Pacote)) { return 'OK' }
    $fonte = if ($Pacote.fonte) { $Pacote.fonte } else { 'winget' }
    $minutos = if ($Pacote.minutos) { [int]$Pacote.minutos } else { 25 }
    $verbo = if ($Atualizar) { 'upgrade' } else { 'install' }
    $a = "$verbo --id `"$($Pacote.id)`" --exact --source $fonte --accept-package-agreements --accept-source-agreements --disable-interactivity --silent"
    if ($Pacote.escopo) { $a += " --scope $($Pacote.escopo)" }
    if ($Pacote.override) { $a += " --override `"$($Pacote.override)`"" }
    $codigo = 0
    foreach ($tentativa in 1..2) {
        $codigo = Invoke-ComTempo 'winget.exe' $a $minutos "winget-$($Pacote.id)"
        # Windows Installer roda um por vez. Esperar a vez nao e falha nem gasta tentativa.
        # 1618 = MSI ocupado. -1978334974 = 0x8A150102 (INSTALL_IN_PROGRESS do winget) como int32, que e o que o ExitCode devolve.
        $vez = 0
        while (($codigo -in 1618, -1978334974) -and $vez -lt 60 -and -not (Test-Cancelado)) {
            Write-Log "  | $($script:PrefixoSaida)installer.busy code=$codigo wait=20s"
            Start-Sleep -Seconds 20
            $vez++
            $codigo = Invoke-ComTempo 'winget.exe' $a $minutos "winget-$($Pacote.id)"
        }
        if (Test-Cancelado) { return 'FALHA: cancelado' }
        Update-Path
        if ($Atualizar) { if (-not (Test-AtualizacaoPendente $Pacote)) { break } }
        elseif (Test-PacoteInstalado $Pacote) { break }
        # 1460 = Invoke-ComTempo encerrou por tempo. Repetir um instalador travado so dobraria a espera.
        if ($codigo -eq 1460) { break }
        Start-Sleep -Seconds 15
    }
    if ($Atualizar) {
        if (Test-AtualizacaoPendente $Pacote) { return "FALHA: a atualização não entrou (código $codigo)" }
        return 'OK'
    }
    if ($Pacote.comando -and -not (Get-Command $Pacote.comando -ErrorAction SilentlyContinue)) {
        return "FALHA: comando '$($Pacote.comando)' não encontrado (código $codigo)"
    }
    if (-not (Test-PacoteInstalado $Pacote)) { return "FALHA: não aparece no winget (código $codigo)" }
    return 'OK'
}

# Quantos instaladores cabem juntos neste PC. O teto de 4 existe porque disco e rede saturam antes da CPU.
function Get-VagasMaximas { [Math]::Max(1, [Math]::Min(4, [int][Math]::Floor([Environment]::ProcessorCount / 4))) }

function Get-Carga {
    $so = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        Cpu = [int](Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
        Ram = [int](100 - 100 * $so.FreePhysicalMemory / $so.TotalVisibleMemorySize)
        LivreGB = [math]::Round($so.FreePhysicalMemory / 1MB, 1)
    }
}

# Dependencias usam Windows Installer e rodariam em fila de qualquer jeito. Os pesados ocupam disco e rede sozinhos.
function New-ItemPrograma([string]$Nome, $Pacote) {
    [pscustomobject]@{ Nome = $Nome; Pacote = $Pacote; Sozinho = ($Pacote.grupo -eq 'Dependências (AIO)' -or [int]$Pacote.minutos -ge 30) }
}

function Close-Trabalhos($Rodando, [switch]$Todos) {
    foreach ($t in @($Rodando)) {
        if ($Todos) { $t.Processo.WaitForExit() }
        if (-not $t.Processo.HasExited) { continue }
        # O trabalho registra o proprio resultado. Codigo diferente de zero quer dizer que ele morreu antes disso.
        if ($t.Processo.ExitCode -ne 0) { Add-Resultado 'FALHOU' $t.Nome "processo saiu com $($t.Processo.ExitCode)"; Write-Log "[FALHOU] $($t.Nome) - processo saiu com $($t.Processo.ExitCode)" Red }
        [void]$Rodando.Remove($t)
    }
}

# Instala a lista, varios ao mesmo tempo quando a opcao esta ligada e CPU e RAM deixam. Sem a opcao, um por vez.
function Invoke-Programas($Itens) {
    $vagas = Get-VagasMaximas
    if ($vagas -le 1 -or -not (Test-Path -LiteralPath (Join-Path $script:Dados 'paralelo.txt'))) {
        foreach ($i in $Itens) { Invoke-Etapa $i.Nome { Install-Pacote $i.Pacote } }
        return
    }
    Write-Log "sched.start itens=$(@($Itens).Count) vagas=$vagas nucleos=$([Environment]::ProcessorCount) limite=cpu<75 ram<85 livre>=1.5GB"
    $rodando = New-Object Collections.ArrayList
    $motivo = ''
    foreach ($i in $Itens) {
        if ((Test-Cancelado) -or (Test-Pular $i.Nome) -or (Test-Feito $i.Nome)) { Invoke-Etapa $i.Nome { Install-Pacote $i.Pacote }; continue }
        if ($i.Sozinho) {
            Close-Trabalhos $rodando -Todos
            Invoke-Etapa $i.Nome { Install-Pacote $i.Pacote }
            continue
        }
        while ($true) {
            Close-Trabalhos $rodando
            if ($rodando.Count -eq 0 -or (Test-Cancelado)) { break }
            if ($rodando.Count -lt $vagas) {
                $c = Get-Carga
                if ($c.Cpu -lt 75 -and $c.Ram -lt 85 -and $c.LivreGB -ge 1.5) { break }
                $agora = "cpu=$($c.Cpu)% ram=$($c.Ram)% livre=$($c.LivreGB)GB"
                if ($motivo -ne $agora) { Write-Log "sched.wait rodando=$($rodando.Count) $agora"; $motivo = $agora }
            }
            Start-Sleep -Seconds 2
        }
        if (Test-Cancelado) { Invoke-Etapa $i.Nome { Install-Pacote $i.Pacote }; continue }
        $item64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(([pscustomobject]@{ Nome = $i.Nome; Pacote = $i.Pacote } | ConvertTo-Json -Depth 4 -Compress)))
        $p = Start-Process powershell.exe -NoNewWindow -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\instalar-um.ps1`" -Item64 $item64"
        $null = $p.Handle  # sem isso o ExitCode volta vazio no PowerShell 5.1
        [void]$rodando.Add([pscustomobject]@{ Nome = $i.Nome; Processo = $p })
        Write-Log "sched.slot pid=$($p.Id) rodando=$($rodando.Count)/$vagas $($i.Nome)"
        # A carga do novo instalador leva alguns segundos para aparecer na medicao.
        Start-Sleep -Seconds 3
    }
    Close-Trabalhos $rodando -Todos
    Update-Path
    Write-Log 'sched.done'
}
