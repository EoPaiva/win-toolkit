# Desfaz a limpeza: religa os servicos e apaga as politicas. Apps removidos voltam pela Microsoft Store.
. "$PSScriptRoot\comum.ps1"

$copia = Join-Path $script:Dados 'servicos-antes.json'
if (Test-Path -LiteralPath $copia) {
    $antes = (Read-Utf8 $copia) | ConvertFrom-Json
    foreach ($p in $antes.PSObject.Properties) {
        Set-Service -Name $p.Name -StartupType $p.Value -ErrorAction SilentlyContinue
        if ($p.Value -eq 'Automatic') { Start-Service -Name $p.Name -ErrorAction SilentlyContinue }
        Write-Log "Servico $($p.Name) => $($p.Value)"
    }
} else {
    Write-Log "Nao achei $copia. Os servicos nao foram alterados." Yellow
}

foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search',
    'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer') {
    Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'PublishUserActivities' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -ErrorAction SilentlyContinue
foreach ($n in 'ShowCopilotButton', 'TaskbarDa', 'Start_IrisRecommendations', 'Start_TrackProgs') {
    Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name $n -ErrorAction SilentlyContinue
}
Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue
Remove-Item -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Recurse -Force -ErrorAction SilentlyContinue
Write-Log 'Limpeza revertida. Reinicie o PC. Para reinstalar apps removidos, use a Microsoft Store.' Green
