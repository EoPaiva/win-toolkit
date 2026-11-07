# Aplica ou reverte as correcoes do Anti-crash MTA. Nunca edita arquivos do GTA nem a copia do gta_sa.exe.
# Nao ha trava do PC de origem: a rotina so mexe nas configuracoes do jogo e nos componentes dele.
param(
    [string]$Itens = '',
    [switch]$Reverter,
    [string]$RaizRegistro = 'HKLM:\SOFTWARE\WOW6432Node\Multi Theft Auto: San Andreas All',
    [string]$PastaDocs = [Environment]::GetFolderPath('MyDocuments'),
    [string]$ChaveGpu = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences',
    [string]$DadosPrograma = $env:ProgramData,
    [string]$Dono = ''
)
. "$PSScriptRoot\mta-comum.ps1"

$arqBackup = Join-Path $script:Dados 'mta-antes.json'
$arqEstado = Join-Path $script:Dados 'mta.json'
$pastaBackup = Join-Path $script:Dados 'mta-backup'

# Com outra conta no UAC, HKCU e Documentos seriam os dessa conta.
if (-not $Dono) { $Dono = Get-DonoSessao }
if (-not (Test-DonoSessao $env:USERNAME $Dono)) { Write-Log "policy.deny reason=other-user: confirme o aviso do Windows com a conta '$Dono'. Nada foi alterado." Red; exit 1 }
$mta = Find-Mta $RaizRegistro $DadosPrograma
if (-not $mta) { Write-Log 'policy.deny reason=mta-not-found: MTA nao encontrado neste PC. Nada foi alterado.' Red; exit 1 }
# O MTA grava a configuracao: o que for editado com ele aberto pode ser sobrescrito.
if (Test-MtaAberto) { Write-Log 'policy.deny reason=mta-open: feche o MTA e rode de novo. Nada foi alterado.' Red; exit 1 }
$arqConfig = Join-Path $mta.PastaMta 'MTA\config\coreconfig.xml'

function Ler-Backup {
    $saida = @{ config = @{}; gpu = @{}; mods = New-Object Collections.ArrayList; gtaset = $null }
    if (-not (Test-Path -LiteralPath $arqBackup)) { return $saida }
    $lido = (Read-Utf8 $arqBackup) | ConvertFrom-Json -ErrorAction Stop
    if (-not $lido) { throw 'mta-antes.json esta vazio' }
    if ($lido.config) { foreach ($p in $lido.config.PSObject.Properties) { $saida.config[$p.Name] = $p.Value } }
    if ($lido.gpu) { foreach ($p in $lido.gpu.PSObject.Properties) { $saida.gpu[$p.Name] = $p.Value } }
    foreach ($m in @($lido.mods)) { if ($m) { [void]$saida.mods.Add($m) } }
    $saida.gtaset = $lido.gtaset
    $saida
}
function Salvar-Backup { Write-Atomico $arqBackup ($copia | ConvertTo-Json -Depth 5) }
# Backup ilegivel nao e backup vazio: seguir apagaria os mods guardados e gravaria valores novos como originais.
try { $copia = Ler-Backup }
catch { Write-Log "policy.deny reason=backup-unreadable: $arqBackup nao pode ser lido e foi mantido, com os mods em $pastaBackup. Nada foi alterado." Red; exit 1 }

# O primeiro valor salvo e o que vale: aplicar de novo nao apaga o estado original.
function Aplicar-Config([hashtable]$Valores) {
    $anteriores = Set-ConfigMta $arqConfig $Valores
    foreach ($k in $anteriores.Keys) { if (-not $copia.config.ContainsKey($k)) { $copia.config[$k] = $anteriores[$k] } }
    Salvar-Backup
}

# Move-Item nao move pasta entre discos no PowerShell 5.1.
function Mover-Item([string]$De, [string]$Para) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Para) -ErrorAction Stop | Out-Null
    if ((Split-Path -Qualifier $De) -eq (Split-Path -Qualifier $Para) -or -not (Get-Item -LiteralPath $De -Force).PSIsContainer) {
        Move-Item -LiteralPath $De -Destination $Para -Force -ErrorAction Stop
    } else {
        Copy-Item -LiteralPath $De -Destination $Para -Recurse -Force -ErrorAction Stop
        try { Remove-Item -LiteralPath $De -Recurse -Force -ErrorAction Stop }
        catch { throw "copia completa em $Para, mas parte de $De nao saiu: $($_.Exception.Message)" }
    }
}

# Apaga so pastas vazias: o que nao esta no registro pode ser a unica copia de um mod.
function Limpar-PastaBackup {
    if (-not (Test-Path -LiteralPath $pastaBackup)) { return }
    # Da pasta mais funda para a mais rasa: esvaziar uma pode esvaziar a de cima.
    foreach ($d in @(Get-ChildItem -LiteralPath $pastaBackup -Directory -Force -Recurse | Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not @(Get-ChildItem -LiteralPath $d.FullName -Force).Count) { [IO.Directory]::Delete($d.FullName) }
    }
    if (-not @(Get-ChildItem -LiteralPath $pastaBackup -Force).Count) { [IO.Directory]::Delete($pastaBackup) }
}

function Ler-Estado { if (Test-Path -LiteralPath $arqEstado) { (Read-Utf8 $arqEstado) | ConvertFrom-Json } else { $null } }
$setAtual = Join-Path $PastaDocs 'GTA San Andreas User Files\gta_sa.set'

if ($Reverter) {
    Write-Log '@total 4'
    Write-Log 'mta.revert start' Cyan
    if (-not (Test-Path -LiteralPath $arqBackup)) { Write-Log 'mta.revert: nada a reverter' Green; exit 0 }
    Passo 'Configuracao do MTA' {
        if ($copia.config.Count) { [void](Set-ConfigMta $arqConfig $copia.config); $copia.config = @{}; Salvar-Backup }
    }
    Passo 'Preferencia de placa de video' {
        foreach ($k in @($copia.gpu.Keys)) {
            if ($null -eq $copia.gpu[$k]) { Remove-ItemProperty -LiteralPath $ChaveGpu -Name $k -ErrorAction SilentlyContinue }
            else { New-ItemProperty -LiteralPath $ChaveGpu -Name $k -Value $copia.gpu[$k] -PropertyType String -Force -ErrorAction Stop | Out-Null }
            $copia.gpu.Remove($k)
            Salvar-Backup
        }
    }
    Passo 'Mods da pasta do GTA' {
        $ocupados = 0; $falhas = 0
        foreach ($m in @($copia.mods)) {
            $temDestino = Test-Path -LiteralPath $m.de
            # O registro vem antes de mover: sem copia no backup e com o original no lugar, ele nunca saiu.
            # O PowerShell 5.1 pode deixar a pasta de destino vazia ao falhar: vazia tambem nao e copia.
            $semCopia = -not (Test-Path -LiteralPath $m.para) -or ((Get-Item -LiteralPath $m.para -Force).PSIsContainer -and -not @(Get-ChildItem -LiteralPath $m.para -Force -Recurse -File).Count)
            if ($temDestino -and $semCopia) { $copia.mods.Remove($m); Salvar-Backup; continue }
            # Nao sobrescreve: o que esta la agora pode ser uma copia nova do usuario.
            if ($temDestino) { $ocupados++; Write-Log "  | destino ocupado, mantido no backup: $($m.de) em $($m.para)"; continue }
            try { Mover-Item $m.para $m.de; $copia.mods.Remove($m); Salvar-Backup }
            catch { $falhas++; Write-Log "  | nao voltou: $($m.de): $($_.Exception.Message)" }
        }
        if ($ocupados -or $falhas) { throw "$($ocupados + $falhas) item(ns) continuam em $pastaBackup" }
    }
    Passo 'gta_sa.set' {
        if ($copia.gtaset) {
            if (Test-Path -LiteralPath $copia.gtaset.para) { Move-Item -LiteralPath $copia.gtaset.para -Destination $copia.gtaset.de -Force -ErrorAction Stop }
            $copia.gtaset = $null
            Salvar-Backup
        }
    }
    Write-Log 'Componentes instalados não são removidos: desinstalar um runtime pode quebrar outros programas.'
    if (-not $copia.config.Count -and -not $copia.gpu.Count -and -not $copia.mods.Count -and -not $copia.gtaset) {
        Remove-Item -LiteralPath $arqBackup -Force -ErrorAction SilentlyContinue
        Limpar-PastaBackup
    }
    Write-Log 'mta.revert done' Green
    exit 0
}

$pedidos = @($Itens -split ',' | Where-Object { $_ })
# Instalar pode levar muito tempo: fica por ultimo, para os ajustes nao dependerem de o MTA continuar fechado.
$pedidos = @($pedidos | Where-Object { $_ -ne 'componentes' }) + @($pedidos | Where-Object { $_ -eq 'componentes' })
Write-Log "@total $($pedidos.Count)"
Write-Log "mta.apply start items=$($pedidos -join ',')" Cyan

foreach ($item in $pedidos) {
    if (Test-MtaAberto) { Write-Log "policy.deny reason=mta-open: o MTA foi aberto durante a rotina. O item $item e os seguintes nao foram aplicados." Red; exit 1 }
    switch ($item) {
        'semborda' { Passo 'Modo sem borda' { Aplicar-Config @{ display_fullscreen_style = '1' } } }
        'prioridade' { Passo 'Prioridade acima do normal' { Aplicar-Config @{ process_priority = '1' } } }
        'leve' {
            Passo 'Perfil leve de graficos' {
                $valores = @{}
                foreach ($k in $script:ChavesLeve) { $valores[$k] = '0' }
                Aplicar-Config $valores
            }
        }
        'memoria' {
            Passo 'Modo pouca memoria' {
                $estadoLido = Ler-Estado
                $minimo = if ($estadoLido -and $estadoLido.streamingMinimo) { [int]$estadoLido.streamingMinimo } else { 128 }
                $atual = [int]"0$((Get-ConfigMta $arqConfig @('streaming_memory'))['streaming_memory'])"
                if ($atual -le $minimo) { Write-Log "  | streaming_memory=$atual ja esta no minimo ou abaixo: nada a mudar"; return }
                Aplicar-Config @{ streaming_memory = "$minimo" }
                Write-Log "  | streaming_memory $atual => $minimo"
            }
        }
        'gpu' {
            Passo 'Usar a placa dedicada' {
                Confirm-ChaveRegistro $ChaveGpu
                foreach ($exe in $mta.JogoExe, $mta.MtaExe) {
                    if (-not $copia.gpu.ContainsKey($exe)) { $copia.gpu[$exe] = (Get-Item -LiteralPath $ChaveGpu).GetValue($exe) }
                    New-ItemProperty -LiteralPath $ChaveGpu -Name $exe -Value 'GpuPreference=2;' -PropertyType String -Force -ErrorAction Stop | Out-Null
                    Salvar-Backup
                }
            }
        }
        'mods' {
            Passo 'Tirar mods da pasta do GTA' {
                $lote = Join-Path $pastaBackup (Get-Date -Format 'yyyyMMdd-HHmmss')
                foreach ($origem in @(Get-ModsGta $mta.PastaGta)) {
                    $destino = Join-Path $lote (Split-Path -Leaf $origem)
                    # Registra antes de mover: uma falha no meio nunca deixa copia sem registro.
                    [void]$copia.mods.Add([pscustomobject]@{ de = $origem; para = $destino })
                    Salvar-Backup
                    Mover-Item $origem $destino
                    Write-Log "  | movido: $origem"
                }
            }
        }
        'gtaset' {
            Passo 'Refazer gta_sa.set' {
                if (-not (Test-Path -LiteralPath $setAtual)) { Write-Log '  | gta_sa.set nao existe'; return }
                # O original fica guardado da primeira vez; o de agora foi recriado pelo proprio jogo.
                if ($copia.gtaset) { Remove-Item -LiteralPath $setAtual -Force -ErrorAction Stop; return }
                $copia.gtaset = [pscustomobject]@{ de = $setAtual; para = "$setAtual.bak" }
                Move-Item -LiteralPath $setAtual -Destination "$setAtual.bak" -Force -ErrorAction Stop
                Salvar-Backup
            }
        }
        'componentes' {
            Passo 'Instalar componentes que faltam' {
                $estadoLido = Ler-Estado
                if (-not $estadoLido) { throw 'rode a analise antes' }
                $programas = (Read-Utf8 (Join-Path $script:Raiz 'programas.json')) | ConvertFrom-Json
                Install-ComponentesMta @($estadoLido.componentes) $programas
            }
        }
        default { Write-Log "item.unknown $item" Red }
    }
}
Write-Log 'mta.apply done: abra o MTA para ver o resultado. O estado anterior ficou salvo para reverter.' Green
