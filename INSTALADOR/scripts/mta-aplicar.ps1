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
    $lido = (Read-Utf8 $arqBackup) | ConvertFrom-Json
    if ($lido.config) { foreach ($p in $lido.config.PSObject.Properties) { $saida.config[$p.Name] = $p.Value } }
    if ($lido.gpu) { foreach ($p in $lido.gpu.PSObject.Properties) { $saida.gpu[$p.Name] = $p.Value } }
    foreach ($m in @($lido.mods)) { if ($m) { [void]$saida.mods.Add($m) } }
    $saida.gtaset = $lido.gtaset
    $saida
}
function Salvar-Backup { Write-Utf8 $arqBackup ($copia | ConvertTo-Json -Depth 5) }
$copia = Ler-Backup

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
        Remove-Item -LiteralPath $De -Recurse -Force -ErrorAction Stop
    }
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
        $ocupados = 0
        foreach ($m in @($copia.mods)) {
            # Nao sobrescreve: o que esta la agora pode ser uma copia nova do usuario.
            if (Test-Path -LiteralPath $m.de) { $ocupados++; Write-Log "  | destino ocupado, mantido no backup: $($m.de)"; continue }
            Mover-Item $m.para $m.de
            $copia.mods.Remove($m)
            Salvar-Backup
        }
        if ($ocupados) { throw "$ocupados item(ns) ficaram em $pastaBackup porque o destino ja existe" }
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
        if (Test-Path -LiteralPath $pastaBackup) { Remove-Item -LiteralPath $pastaBackup -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Log 'mta.revert done' Green
    exit 0
}

$pedidos = @($Itens -split ',' | Where-Object { $_ })
Write-Log "@total $($pedidos.Count)"
Write-Log "mta.apply start items=$($pedidos -join ',')" Cyan

foreach ($item in $pedidos) {
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
                    Mover-Item $origem $destino
                    [void]$copia.mods.Add([pscustomobject]@{ de = $origem; para = $destino })
                    Salvar-Backup
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
