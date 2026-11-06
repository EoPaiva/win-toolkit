# Correcoes marcadas na analise e ferramentas de manutencao. Precisa de administrador.
param([string]$Acao, [string[]]$Ids)
. "$PSScriptRoot\comum.ps1"
if ($env:COMPUTERNAME -eq 'MARINETE') { Write-Log 'policy.deny host=MARINETE reason=source-of-configs: nada foi alterado' Red; exit 1 }

function Passo([string]$nome, [scriptblock]$a) {
    Write-Log "[....] $nome"
    try {
        & $a
        Write-Log "[ ok ] $nome"
    } catch { Write-Log "[FALHOU] $nome - $($_.Exception.Message)" Red }
}
function Tamanho($p) { (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
function Exec([string]$exe, [string]$a, [int]$min) {
    $c = Invoke-ComTempo $exe $a $min ($exe -replace '\W', '_')
    if ($c -notin 0, 3010, 1641) { throw "exit=$c" }
}

$Correcoes = @{
    'defender-rtp' = @('Set-MpPreference -DisableRealtimeMonitoring $false', { Set-MpPreference -DisableRealtimeMonitoring $false })
    'firewall'     = @('Set-NetFirewallProfile -All -Enabled True', { Set-NetFirewallProfile -All -Enabled True })
    'uac'          = @('reg.set HKLM\..\Policies\System\EnableLUA=1', { Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1 -Type DWord })
    'lsa'          = @('reg.set HKLM\..\Lsa\RunAsPPL=1', { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RunAsPPL -Value 1 -Type DWord })
    'smb1'         = @('Disable-WindowsOptionalFeature SMB1Protocol', { Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null })
    'rdp-nla'      = @('reg.set HKLM\..\RDP-Tcp\UserAuthentication=1', { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1 -Type DWord })
    'guest'        = @('Disable-LocalUser SID *-501', { Get-LocalUser | Where-Object { $_.SID -like '*-501' } | Disable-LocalUser })
    'autorun'      = @('reg.set HKLM\..\Explorer\NoDriveTypeAutoRun=0xFF', { New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Force | Out-Null; Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoDriveTypeAutoRun -Value 255 -Type DWord })
    'ps2'          = @('Disable-WindowsOptionalFeature MicrosoftWindowsPowerShellV2', { Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart | Out-Null })
}

switch ($Acao) {
    'corrigir' {
        $lista = @($Ids | ForEach-Object { $_ -split ',' } | Where-Object { $Correcoes.ContainsKey($_) })
        Write-Log "@total $($lista.Count)"
        foreach ($i in $lista) { Passo $Correcoes[$i][0] $Correcoes[$i][1] }
    }
    'atualizar' {
        Write-Log '@total 1'
        Initialize-Winget
        Passo 'winget upgrade --all --include-unknown' { Exec 'winget.exe' 'upgrade --all --include-unknown --silent --accept-package-agreements --accept-source-agreements --disable-interactivity' 120 }
    }
    'limpar' {
        Write-Log '@total 3'
        foreach ($p in $env:TEMP, "$env:windir\Temp") {
            Passo "purge $p" {
                $antes = Tamanho $p
                Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log ("  | freed={0:N0} MB" -f (($antes - (Tamanho $p)) / 1MB))
            }
        }
        Passo 'DISM /Online /Cleanup-Image /StartComponentCleanup' { Exec 'dism.exe' '/Online /Cleanup-Image /StartComponentCleanup' 60 }
    }
    'reparar' {
        Write-Log '@total 2'
        Passo 'DISM /Online /Cleanup-Image /RestoreHealth' { Exec 'dism.exe' '/Online /Cleanup-Image /RestoreHealth' 60 }
        Passo 'sfc /scannow' { Exec 'sfc.exe' '/scannow' 60 }
    }
    'rede' {
        Write-Log '@total 3'
        Passo 'ipconfig /flushdns' { Exec 'ipconfig.exe' '/flushdns' 2 }
        Passo 'netsh winsock reset' { Exec 'netsh.exe' 'winsock reset' 2 }
        Passo 'netsh int ip reset' { Exec 'netsh.exe' 'int ip reset' 2 }
        Write-Log 'net.reset done: reinicie o PC' Green
    }
    'restauracao' {
        Write-Log '@total 1'
        Passo 'Checkpoint-Computer -RestorePointType MODIFY_SETTINGS' {
            Enable-ComputerRestore -Drive "$env:SystemDrive\"
            Checkpoint-Computer -Description 'upaiva.dev manual' -RestorePointType MODIFY_SETTINGS
        }
    }
    default { Write-Log "action.unknown $Acao" Red; exit 1 }
}
