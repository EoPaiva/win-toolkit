# Otimizacao em 4 niveis cumulativos, com plano simulado, backup e reversao.
# Nenhum nivel toca em Defender, Firewall, UAC, SmartScreen, Windows Update, TPM ou Secure Boot.
param(
    [ValidateSet('leve', 'media', 'alta', 'altissima')][string]$Nivel = 'leve',
    [switch]$Simular,
    [switch]$Reverter,
    [switch]$DesligarVBS
)
. "$PSScriptRoot\comum.ps1"
if (-not $Simular -and $env:COMPUTERNAME -eq 'MARINETE') { Write-Log 'policy.deny host=MARINETE reason=source-of-configs: nada foi alterado' Red; exit 1 }
$copia = Join-Path $script:Dados 'otimizacao-antes.json'
$CDM = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$ADV = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$POL = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
$MM = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'

function PlanoReg($n, $c, $nome, $v) { [pscustomobject]@{ n = $n; t = 'reg'; c = $c; a = $nome; v = $v } }
function PlanoSvc($n, $s) { [pscustomobject]@{ n = $n; t = 'svc'; a = $s } }
function PlanoApp($n, $s) { [pscustomobject]@{ n = $n; t = 'appx'; a = $s } }
function PlanoCmd($n, $d, $x) { [pscustomobject]@{ n = $n; t = 'cmd'; a = $d; x = $x } }

$Plano = @()
foreach ($v in 'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') { $Plano += PlanoReg 1 $CDM $v 0 }
$Plano += PlanoReg 1 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
$Plano += PlanoReg 1 $ADV 'Start_IrisRecommendations' 0
$Plano += PlanoReg 1 $ADV 'ShowCopilotButton' 0
$Plano += PlanoReg 1 $ADV 'TaskbarDa' 0
$Plano += PlanoReg 1 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
$Plano += PlanoReg 1 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
$Plano += PlanoReg 1 "$POL\DataCollection" 'AllowTelemetry' 1
$Plano += PlanoReg 1 "$POL\AdvertisingInfo" 'DisabledByGroupPolicy' 1
$Plano += PlanoReg 1 'HKCU:\SOFTWARE\Microsoft\GameBar' 'AutoGameModeEnabled' 1
$Plano += PlanoReg 1 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
$Plano += PlanoReg 1 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1

foreach ($a in 'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingSearch', 'Microsoft.BingWeather', 'Microsoft.Copilot', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.OutlookForWindows', 'Microsoft.People', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.Windows.DevHome', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.WindowsSoundRecorder', 'Microsoft.ZuneVideo', 'MicrosoftTeams', 'MSTeams', 'MicrosoftWindows.Client.WebExperience') { $Plano += PlanoApp 2 $a }
$Plano += PlanoReg 2 "$POL\WindowsCopilot" 'TurnOffWindowsCopilot' 1
$Plano += PlanoReg 2 "$POL\WindowsAI" 'DisableAIDataAnalysis' 1
$Plano += PlanoReg 2 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
$Plano += PlanoReg 2 "$POL\CloudContent" 'DisableWindowsConsumerFeatures' 1
$Plano += PlanoReg 2 "$POL\System" 'PublishUserActivities' 0
$Plano += PlanoReg 2 "$POL\Windows Search" 'DisableWebSearch' 1
$Plano += PlanoReg 2 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
foreach ($s in 'DiagTrack', 'dmwappushservice', 'RetailDemo', 'MapsBroker', 'Fax') { $Plano += PlanoSvc 2 $s }
$Plano += PlanoCmd 2 'powercfg /setactive SCHEME_MIN' { & powercfg.exe /setactive SCHEME_MIN }

foreach ($a in 'Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.YourPhone', 'MicrosoftCorporationII.QuickAssist') { $Plano += PlanoApp 3 $a }
foreach ($s in 'SysMain', 'WSearch', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'Spooler', 'PrintNotify', 'WerSvc', 'RemoteRegistry') { $Plano += PlanoSvc 3 $s }
$Plano += PlanoReg 3 "$POL\GameDVR" 'AllowGameDVR' 0
$Plano += PlanoReg 3 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
$Plano += PlanoCmd 3 'powercfg /hibernate off' { & powercfg.exe /hibernate off }
$Plano += PlanoCmd 3 'powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 (Ultimate Performance)' {
    $s = & powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
    if ($s -match '([0-9a-fA-F-]{36})') { & powercfg.exe /setactive $Matches[1] }
}

foreach ($s in 'PhoneSvc', 'wisvc', 'stisvc', 'SSDPSRV', 'upnphost', 'lmhosts', 'TrkWks', 'PcaSvc', 'WpcMonSvc', 'RemoteAccess', 'lfsvc', 'WalletService', 'SEMgrSvc') { $Plano += PlanoSvc 4 $s }
$Plano += PlanoReg 4 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
$Plano += PlanoReg 4 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
$Plano += PlanoReg 4 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
$Plano += PlanoReg 4 $MM 'SystemResponsiveness' 10
$Plano += PlanoReg 4 $MM 'NetworkThrottlingIndex' 0xFFFFFFFF
$Plano += PlanoReg 4 $ADV 'TaskbarAnimations' 0
$Plano += PlanoCmd 4 'DISM /Online /Set-ReservedStorageState /State:Disabled' { & dism.exe /Online /Set-ReservedStorageState /State:Disabled /NoRestart /Quiet | Out-Null }
if (([Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)) -ge 16) {
    $Plano += PlanoCmd 4 'Disable-MMAgent -MemoryCompression (RAM >= 16 GB)' { Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue }
}

$nivelNum = @{ leve = 1; media = 2; alta = 3; altissima = 4 }[$Nivel]
$acoes = @($Plano | Where-Object { $_.n -le $nivelNum })
if ($DesligarVBS) { $acoes += PlanoReg 5 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0 }

function Salvar-Copia($c) { Write-Utf8 $copia ($c | ConvertTo-Json -Depth 4) }
function Ler-Copia {
    if (Test-Path -LiteralPath $copia) {
        $o = (Read-Utf8 $copia) | ConvertFrom-Json
        $reg = @{}; foreach ($p in $o.reg.PSObject.Properties) { $reg[$p.Name] = $p.Value }
        $svc = @{}; foreach ($p in $o.svc.PSObject.Properties) { $svc[$p.Name] = $p.Value }
        return @{ reg = $reg; svc = $svc }
    }
    return @{ reg = @{}; svc = @{} }
}

if ($Reverter) {
    $c = Ler-Copia
    Write-Log "@total $($c.reg.Count + $c.svc.Count + 2)"
    Write-Log "backup.load path=$copia reg=$($c.reg.Count) svc=$($c.svc.Count)" Cyan
    foreach ($k in $c.reg.Keys) {
        $p = $k -split '\|', 2
        $nome = "reg.restore $($p[0])\$($p[1])"
        Write-Log "[....] $nome"
        if ($null -eq $c.reg[$k]) { Remove-ItemProperty -Path $p[0] -Name $p[1] -ErrorAction SilentlyContinue }
        else {
            $valor = $c.reg[$k]
            if ($valor -is [ValueType] -and [double]$valor -gt [int]::MaxValue) { $valor = [int]([double]$valor - 4294967296) }
            Set-ItemProperty -Path $p[0] -Name $p[1] -Value $valor -ErrorAction SilentlyContinue
        }
        Write-Log "[ ok ] $nome"
    }
    foreach ($k in $c.svc.Keys) {
        $nome = "svc.restore $k start=$($c.svc[$k])"
        Write-Log "[....] $nome"
        Set-Service -Name $k -StartupType $c.svc[$k] -ErrorAction SilentlyContinue
        if ($c.svc[$k] -eq 'Automatic') { Start-Service -Name $k -ErrorAction SilentlyContinue }
        Write-Log "[ ok ] $nome"
    }
    Write-Log '[....] powercfg /setactive SCHEME_BALANCED + /hibernate on'
    & powercfg.exe /setactive SCHEME_BALANCED; & powercfg.exe /hibernate on
    Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
    & dism.exe /Online /Set-ReservedStorageState /State:Enabled /NoRestart /Quiet | Out-Null
    Write-Log '[ ok ] powercfg /setactive SCHEME_BALANCED + /hibernate on'
    $rl = Join-Path $PSScriptRoot 'reverter-limpeza.ps1'
    Write-Log "[....] exec $rl"
    if (Test-Path -LiteralPath $rl) { & $rl }
    Write-Log "[ ok ] exec $rl"
    Write-Log 'revert.done apps removidos voltam pela Microsoft Store; reinicie o PC' Green
    exit 0
}

$modo = if ($Simular) { 'dry-run' } else { 'apply' }
Write-Log "@total $($acoes.Count + 1)"
Write-Log "optimizer.start profile=$Nivel mode=$modo actions=$($acoes.Count) reg=$(@($acoes | Where-Object t -eq 'reg').Count) svc=$(@($acoes | Where-Object t -eq 'svc').Count) appx=$(@($acoes | Where-Object t -eq 'appx').Count) cmd=$(@($acoes | Where-Object t -eq 'cmd').Count)" Cyan

Write-Log '[....] Checkpoint-Computer -RestorePointType MODIFY_SETTINGS'
if (-not $Simular) {
    try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop; Checkpoint-Computer -Description 'upaiva.dev' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop }
    catch { Write-Log "  | restore-point skipped: $($_.Exception.Message)" }
}
Write-Log '[ ok ] Checkpoint-Computer -RestorePointType MODIFY_SETTINGS'

$copiaAtual = Ler-Copia
foreach ($x in $acoes) {
    if (Test-Cancelado) { Write-Log 'optimizer.cancelled: o que ja foi aplicado continua salvo no backup'; break }
    switch ($x.t) {
        'reg' {
            $prev = $null
            try { $prev = (Get-ItemProperty -Path $x.c -Name $x.a -ErrorAction Stop).($x.a) } catch { }
            $mostrar = if ($null -eq $prev) { '<absent>' } else { $prev }
            $nome = "reg.set $($x.c)\$($x.a)=$($x.v) REG_DWORD prev=$mostrar"
            Write-Log "[....] $nome"
            if (-not $Simular) {
                $k = "$($x.c)|$($x.a)"
                if (-not $copiaAtual.reg.ContainsKey($k)) { $copiaAtual.reg[$k] = $prev }
                New-Item -Path $x.c -Force -ErrorAction SilentlyContinue | Out-Null
                $valor = if ($x.v -is [long] -or $x.v -gt [int]::MaxValue) { [int]-1 } else { [int]$x.v }
                Set-ItemProperty -Path $x.c -Name $x.a -Value $valor -Type DWord -ErrorAction SilentlyContinue
            }
            Write-Log "[ ok ] $nome"
        }
        'svc' {
            $svc = Get-Service -Name $x.a -ErrorAction SilentlyContinue
            if (-not $svc) { Write-Log "  | svc $($x.a) not present on this build"; continue }
            $nome = "svc.config $($x.a) start=Disabled prev=$($svc.StartType) state=$($svc.Status)"
            Write-Log "[....] $nome"
            if (-not $Simular) {
                if (-not $copiaAtual.svc.ContainsKey($x.a)) { $copiaAtual.svc[$x.a] = "$($svc.StartType)" }
                Stop-Service -Name $x.a -Force -ErrorAction SilentlyContinue
                Set-Service -Name $x.a -StartupType Disabled -ErrorAction SilentlyContinue
            }
            Write-Log "[ ok ] $nome"
        }
        'appx' {
            $nome = "appx.remove $($x.a)"
            Write-Log "[....] $nome"
            if (-not $Simular) {
                Get-AppxPackage -AllUsers -Name $x.a -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $x.a | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
            }
            Write-Log "[ ok ] $nome"
        }
        'cmd' {
            $nome = "exec $($x.a)"
            Write-Log "[....] $nome"
            if (-not $Simular) { try { & $x.x } catch { Write-Log "  | $($_.Exception.Message)" } }
            Write-Log "[ ok ] $nome"
        }
    }
    if (-not $Simular) { Salvar-Copia $copiaAtual }
}
if ($Simular) { Write-Log 'optimizer.done mode=dry-run: nada foi alterado' Green }
else { Write-Log "optimizer.done profile=${Nivel}: reinicie o PC. Backup em $copia" Green }
