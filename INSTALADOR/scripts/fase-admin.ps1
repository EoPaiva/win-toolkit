# Parte que precisa de administrador. Roda uma vez por UAC, chamada por instalar.ps1.
. "$PSScriptRoot\comum.ps1"
if ($env:COMPUTERNAME -eq 'MARINETE') { Write-Log 'PC de origem: nada foi instalado.' Red; exit 1 }
$programas = (Read-Utf8 (Join-Path $script:Raiz 'programas.json')) | ConvertFrom-Json

# Drivers do proprio PC, copiados por antes-de-formatar.ps1. Vem primeiro porque o Wi-Fi pode depender deles.
Invoke-Etapa 'Drivers de rede' {
    $pasta = Join-Path $script:Raiz 'drivers'
    if (-not (Get-ChildItem -LiteralPath $pasta -Recurse -Filter '*.inf' -ErrorAction SilentlyContinue | Select-Object -First 1)) { return 'OK' }
    & pnputil.exe /add-driver "$pasta\*.inf" /subdirs /install 2>&1 | Out-File -LiteralPath (Join-Path $script:Logs 'pnputil.log') -Encoding utf8
    'OK'
}

# Antes de esperar a internet: com a rede de volta, o instalador nao precisa pedir o Wi-Fi.
Invoke-Etapa 'Redes Wi-Fi' { Import-RedesWifi }

Invoke-Etapa 'Caminhos longos no Windows' {
    # Clones de plugins do Claude passam do limite de 260 caracteres.
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -Type DWord
    'OK'
}

Wait-Internet
Initialize-Winget

Invoke-Programas @(foreach ($p in $programas.maquina) { New-ItemPrograma "Programa $($p.id)" $p })

Invoke-Etapa 'NET Framework 3.5' { Enable-NetFx3 }

Invoke-Etapa 'Limpeza do Windows' { & (Join-Path $PSScriptRoot 'limpeza.ps1') }
