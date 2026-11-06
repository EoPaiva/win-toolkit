# Parte que precisa de administrador. Roda uma vez por UAC, chamada por instalar.ps1.
. "$PSScriptRoot\comum.ps1"
if ($env:COMPUTERNAME -eq 'MARINETE') { Write-Log 'PC de origem: nada foi instalado.' Red; exit 1 }
$programas = (Read-Utf8 (Join-Path $script:Raiz 'programas.json')) | ConvertFrom-Json

# Drivers do proprio PC, copiados por 1-ANTES-DE-FORMATAR. Vem primeiro porque o Wi-Fi pode depender deles.
Invoke-Etapa 'Drivers de rede' {
    $pasta = Join-Path $script:Raiz 'drivers'
    if (-not (Get-ChildItem -LiteralPath $pasta -Recurse -Filter '*.inf' -ErrorAction SilentlyContinue | Select-Object -First 1)) { return 'OK' }
    & pnputil.exe /add-driver "$pasta\*.inf" /subdirs /install 2>&1 | Out-File -LiteralPath (Join-Path $script:Logs 'pnputil.log') -Encoding utf8
    'OK'
}

Invoke-Etapa 'Caminhos longos no Windows' {
    # Clones de plugins do Claude passam do limite de 260 caracteres.
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -Type DWord
    'OK'
}

Wait-Internet
Initialize-Winget

foreach ($p in $programas.maquina) {
    Invoke-Etapa "Programa $($p.id)" { Install-Pacote $p }
}

Invoke-Etapa 'NET Framework 3.5' {
    $c = Invoke-ComTempo 'dism.exe' '/Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart /Quiet' 30 'netfx3'
    if ($c -in 0, 3010) { 'OK' } else { "FALHA: codigo $c" }
}

Invoke-Etapa 'Limpeza do Windows' { & (Join-Path $PSScriptRoot 'limpeza.ps1') }
