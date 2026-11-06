# Drivers: busca no catalogo oficial do Windows Update e sugere a ferramenta do fabricante. A busca so le.
param([ValidateSet('buscar', 'instalar')][string]$Acao = 'buscar', [string]$Ids = '')
. "$PSScriptRoot\comum.ps1"
$arq = Join-Path $script:Dados 'drivers.json'

function Abrir-Busca {
    $sessao = New-Object -ComObject Microsoft.Update.Session
    $sessao.ClientApplicationID = 'upaiva.dev'
    $b = $sessao.CreateUpdateSearcher()
    $b.Online = $true
    $b.ServerSelection = 2   # ssWindowsUpdate: o catalogo da Microsoft, nao um WSUS local
    return @{ sessao = $sessao; busca = $b }
}
$Consulta = "IsInstalled=0 and Type='Driver' and IsHidden=0"

if ($Acao -eq 'buscar') {
    Write-Log '@total 4'
    Write-Log 'drivers.scan start source=Microsoft.Update.Session server=ssWindowsUpdate mode=read-only' Cyan

    Write-Log '[....] enum Win32_PnPSignedDriver'
    $sistema = Get-CimInstance Win32_ComputerSystem
    $todos = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DriverVersion -and $_.DriverProviderName -and $_.DriverProviderName -notmatch '^Microsoft' })
    $limite = (Get-Date).AddYears(-3)
    $antigos = @($todos | Where-Object { $_.DriverDate -and $_.DriverDate -lt $limite } | Sort-Object DriverDate | Select-Object -Unique DeviceName, DriverVersion, DriverDate, DriverProviderName)
    $gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object { [pscustomobject]@{ nome = $_.Name; versao = $_.DriverVersion; data = if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } else { '' } } })
    Write-Log "  | devices.thirdparty=$($todos.Count) older.than.3y=$($antigos.Count) gpu=$($gpu.Count) vendor=$($sistema.Manufacturer) model=$($sistema.Model)"
    Write-Log '[ ok ] enum Win32_PnPSignedDriver'

    Write-Log '[....] enum Get-PnpDevice status=Error'
    $problemas = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -in 'Error', 'Degraded' } | ForEach-Object { [pscustomobject]@{ nome = "$($_.FriendlyName)"; codigo = "$($_.Problem)"; classe = "$($_.Class)" } })
    Write-Log "  | devices.problem=$($problemas.Count)"
    Write-Log '[ ok ] enum Get-PnpDevice status=Error'

    Write-Log "[....] IUpdateSearcher.Search $Consulta"
    $lista = @(); $erroBusca = ''
    try {
        $x = Abrir-Busca
        $r = $x.busca.Search($Consulta)
        foreach ($u in $r.Updates) {
            $mb = [Math]::Round($u.MaxDownloadSize / 1MB, 1)
            $lista += [pscustomobject]@{ id = $u.Identity.UpdateID; titulo = $u.Title; classe = "$($u.DriverClass)"; fabricante = "$($u.DriverManufacturer)"; data = if ($u.DriverVerDate) { ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } else { '' }; mb = $mb }
            Write-Log "  | update class=$($u.DriverClass) date=$($lista[-1].data) size=${mb}MB :: $($u.Title)"
        }
        Write-Log "  | ResultCode=$($r.ResultCode) updates=$($lista.Count)"
    } catch { $erroBusca = $_.Exception.Message; Write-Log "  | search.error $erroBusca" }
    Write-Log "[ ok ] IUpdateSearcher.Search $Consulta"

    Write-Log '[....] map vendor tools'
    $mapa = @(
        @{ r = 'Intel'; id = 'Intel.IntelDriverAndSupportAssistant'; rotulo = 'Intel Driver & Support Assistant'; alvo = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer) $($gpu.nome -join ' ')" },
        @{ r = 'Dell'; id = 'Dell.CommandUpdate'; rotulo = 'Dell Command Update'; alvo = $sistema.Manufacturer },
        @{ r = 'Lenovo'; id = 'Lenovo.SystemUpdate'; rotulo = 'Lenovo System Update'; alvo = $sistema.Manufacturer }
    )
    $ferramentas = @($mapa | Where-Object { $_.alvo -match $_.r } | ForEach-Object { [pscustomobject]@{ id = $_.id; rotulo = $_.rotulo } })
    $pagina = @()
    if ($gpu.nome -match 'NVIDIA') { $pagina += [pscustomobject]@{ rotulo = 'NVIDIA App'; url = 'https://www.nvidia.com/pt-br/software/nvidia-app/' } }
    if ($gpu.nome -match 'AMD|Radeon') { $pagina += [pscustomobject]@{ rotulo = 'AMD Software'; url = 'https://www.amd.com/pt/support/download/drivers.html' } }
    Write-Log "  | vendor.tools=$($ferramentas.Count) vendor.pages=$($pagina.Count)"
    Write-Log '[ ok ] map vendor tools'

    $saida = [ordered]@{ atualizacoes = @($lista); problemas = @($problemas); antigos = $antigos.Count; gpu = @($gpu); ferramentas = @($ferramentas); paginas = @($pagina); fabricante = "$($sistema.Manufacturer) $($sistema.Model)"; erro = $erroBusca }
    Write-Utf8 $arq ($saida | ConvertTo-Json -Depth 4)
    Write-Log "drivers.scan done updates=$($lista.Count) problems=$($problemas.Count) old=$($antigos.Count)" Green
    exit 0
}

# ---------- instalar: precisa de administrador ----------
if ($env:COMPUTERNAME -eq 'MARINETE') { Write-Log 'policy.deny host=MARINETE reason=source-of-configs: nada foi alterado' Red; exit 1 }
$pedidos = @($Ids -split ',' | Where-Object { $_ })
Write-Log "@total $($pedidos.Count + 1)"
Write-Log "drivers.install start items=$($pedidos.Count)" Cyan
Write-Log '[....] Checkpoint-Computer -RestorePointType DEVICE_DRIVER_INSTALL'
try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop; Checkpoint-Computer -Description 'upaiva.dev drivers' -RestorePointType DEVICE_DRIVER_INSTALL -ErrorAction Stop }
catch { Write-Log "  | restore-point skipped: $($_.Exception.Message)" }
Write-Log '[ ok ] Checkpoint-Computer -RestorePointType DEVICE_DRIVER_INSTALL'

$ferr = @($pedidos | Where-Object { $_ -like 'winget:*' })
if ($ferr.Count) { Wait-Internet; Initialize-Winget }
foreach ($f in $ferr) {
    $id = $f.Substring(7)
    Write-Log "[....] Programa $id"
    $res = Install-Pacote ([pscustomobject]@{ id = $id })
    if ($res -eq 'OK') { Write-Log "[ ok ] Programa $id" } else { Write-Log "[FALHOU] Programa $id - $res" Red }
}

$guids = @($pedidos | Where-Object { $_ -notlike 'winget:*' })
if ($guids.Count) {
    $x = Abrir-Busca
    $r = $x.busca.Search($Consulta)
    $reiniciar = $false
    foreach ($g in $guids) {
        if (Test-Cancelado) { Write-Log "[cancelado] $g"; continue }
        $u = $null; foreach ($c in $r.Updates) { if ($c.Identity.UpdateID -eq $g) { $u = $c; break } }
        if (-not $u) { Write-Log "[FALHOU] $g - nao esta mais disponivel no catalogo" Red; continue }
        $nome = $u.Title
        Write-Log "[....] $nome"
        try {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            $col = New-Object -ComObject Microsoft.Update.UpdateColl
            [void]$col.Add($u)
            Write-Log "  | IUpdateDownloader.Download size=$([Math]::Round($u.MaxDownloadSize / 1MB, 1))MB"
            $d = $x.sessao.CreateUpdateDownloader(); $d.Updates = $col
            $rd = $d.Download()
            Write-Log "  | download.ResultCode=$($rd.ResultCode)"
            if ($rd.ResultCode -notin 2, 3) { throw "download ResultCode=$($rd.ResultCode)" }
            $i = $x.sessao.CreateUpdateInstaller(); $i.Updates = $col
            $ri = $i.Install()
            $hr = '0x{0:X8}' -f $ri.HResult
            Write-Log "  | install.ResultCode=$($ri.ResultCode) HResult=$hr RebootRequired=$($ri.RebootRequired)"
            if ($ri.RebootRequired) { $reiniciar = $true }
            if ($ri.ResultCode -notin 2, 3) { throw "install ResultCode=$($ri.ResultCode) HResult=$hr" }
            Write-Log "[ ok ] $nome"
        } catch { Write-Log "[FALHOU] $nome - $($_.Exception.Message)" Red }
    }
    if ($reiniciar) { Write-Log 'drivers.install reboot.required=True: reinicie o PC' Yellow }
}
Write-Log 'drivers.install done' Green
