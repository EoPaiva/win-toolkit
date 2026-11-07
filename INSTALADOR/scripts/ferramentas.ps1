# Correcoes marcadas na analise e ferramentas de manutencao. Precisa de administrador.
param([string]$Acao, [string[]]$Ids)
. "$PSScriptRoot\comum.ps1"
if ($env:COMPUTERNAME -eq 'MARINETE') { Write-Log 'policy.deny host=MARINETE reason=source-of-configs: nada foi alterado' Red; exit 1 }

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
    'autorun'      = @('reg.set HKLM\..\Explorer\NoDriveTypeAutoRun=0xFF', { Confirm-ChaveRegistro 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoDriveTypeAutoRun -Value 255 -Type DWord })
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
    'limpar' { & "$PSScriptRoot\limpar-disco.ps1" }
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
    'reinstalar-apps' {
        # Os IDs foram conferidos na Microsoft Store. Dicas, Pacencia e Mapas nao estao la.
        $loja = [ordered]@{
            'Clipchamp.Clipchamp' = '9P1J8S7CCWWT'; 'Microsoft.BingNews' = '9WZDNCRFHVFW'; 'Microsoft.BingWeather' = '9WZDNCRFJ3Q2'; 'Microsoft.Copilot' = '9NHT9RB2F4HD'
            'Microsoft.GamingApp' = '9MV0B5HZVK9Z'; 'Microsoft.GetHelp' = '9PKDZBMV1H3T'; 'Microsoft.MicrosoftOfficeHub' = '9WZDNCRD29V9'; 'Microsoft.OutlookForWindows' = '9NRX63209R7B'
            'Microsoft.PowerAutomateDesktop' = '9NFTCH6J7FHV'; 'Microsoft.Todos' = '9NBLGGH5R558'; 'Microsoft.WindowsFeedbackHub' = '9NBLGGH4R32N'; 'Microsoft.WindowsSoundRecorder' = '9WZDNCRFHWKN'
            'Microsoft.XboxGamingOverlay' = '9NZKPSTSNW4P'; 'Microsoft.YourPhone' = '9NMPJ99VJBWV'; 'MicrosoftCorporationII.QuickAssist' = '9P7BP5VNWKX5'; 'MSTeams' = 'XP8BT8DW290MPQ'
            'MicrosoftWindows.Client.WebExperience' = '9MSSGKG348SP'; 'Microsoft.ZuneVideo' = '9WZDNCRFJ3P2'
        }
        $faltam = @($loja.Keys | Where-Object { -not (Get-AppxPackage -Name $_ -ErrorAction SilentlyContinue) })
        Write-Log "@total $($faltam.Count)"
        Write-Log "appx.scan known=$($loja.Count) missing=$($faltam.Count)"
        if ($faltam.Count) { Wait-Internet; Initialize-Winget }
        foreach ($a in $faltam) {
            if (Test-Cancelado) { Write-Log "[cancelado] $a"; continue }
            Write-Log "[....] $a"
            $r = Install-Pacote ([pscustomobject]@{ id = $loja[$a]; fonte = 'msstore' })
            if ($r -eq 'OK') { Write-Log "[ ok ] $a" } else { Write-Log "[FALHOU] $a - $r" Red }
        }
    }
    default { Write-Log "action.unknown $Acao" Red; exit 1 }
}
