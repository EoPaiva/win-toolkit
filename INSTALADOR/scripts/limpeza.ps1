# Limpeza agressiva. Precisa de administrador.
# Nunca mexe em Defender, firewall, SmartScreen, UAC, Windows Update, TPM, Secure Boot ou VBS: o Vanguard depende dos tres ultimos.
param([switch]$Simular)
. "$PSScriptRoot\comum.ps1"

$AppsRemovidos = @(
    'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingSearch', 'Microsoft.BingWeather', 'Microsoft.Copilot',
    'Microsoft.GamingApp', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.OutlookForWindows', 'Microsoft.People', 'Microsoft.PowerAutomateDesktop',
    'Microsoft.Todos', 'Microsoft.Windows.DevHome', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
    'Microsoft.WindowsSoundRecorder', 'Microsoft.XboxApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.YourPhone', 'Microsoft.ZuneVideo', 'MicrosoftCorporationII.QuickAssist', 'MicrosoftTeams', 'MSTeams',
    'MicrosoftWindows.Client.WebExperience'
)

$ServicosDesligados = @(
    'DiagTrack', 'dmwappushservice', 'Fax', 'MapsBroker', 'PrintNotify', 'RemoteRegistry', 'RetailDemo', 'Spooler',
    'SysMain', 'WerSvc', 'WSearch', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc'
)

# Caminho, nome, valor. A reversao apaga as politicas e devolve os padroes em reverter-limpeza.ps1.
$Registro = @(
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry', 1),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableAIDataAnalysis', 1),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh', 'AllowNewsAndInterests', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent', 'DisableWindowsConsumerFeatures', 1),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo', 'DisabledByGroupPolicy', 1),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'PublishUserActivities', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR', 'AllowGameDVR', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search', 'AllowCortana', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search', 'DisableWebSearch', 1),
    @('HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers', 'HwSchMode', 2),
    @('HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer', 'DisableSearchBoxSuggestions', 1),
    @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled', 0),
    @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ShowCopilotButton', 0),
    @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarDa', 0),
    @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Start_IrisRecommendations', 0),
    @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Start_TrackProgs', 0),
    @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search', 'BingSearchEnabled', 0)
)
foreach ($v in 'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'SilentInstalledAppsEnabled',
    'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
    'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') {
    $Registro += , @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', $v, 0)
}

if ($Simular) {
    "APPS=$($AppsRemovidos -join ',')"
    "SERVICOS=$($ServicosDesligados -join ',')"
    "REGISTRO=$($Registro.Count)"
    return
}

$antes = @{}
foreach ($s in $ServicosDesligados) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($svc) { $antes[$s] = "$($svc.StartType)" }
}
$copiaServicos = Join-Path $script:Dados 'servicos-antes.json'
if (-not (Test-Path -LiteralPath $copiaServicos)) { Write-Utf8 $copiaServicos ($antes | ConvertTo-Json) }

$provisionados = Get-AppxProvisionedPackage -Online
foreach ($a in $AppsRemovidos) {
    Get-AppxPackage -AllUsers -Name $a -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    $provisionados | Where-Object DisplayName -eq $a | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
}

foreach ($s in $antes.Keys) {
    Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
}

foreach ($r in $Registro) {
    Confirm-ChaveRegistro $r[0]
    Set-ItemProperty -Path $r[0] -Name $r[1] -Value $r[2] -Type DWord -ErrorAction SilentlyContinue
}
'OK'
