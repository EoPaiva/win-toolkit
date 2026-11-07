# Drivers: busca no catalogo oficial do Windows Update e sugere a ferramenta do fabricante. A busca so le.
param([ValidateSet('buscar', 'instalar')][string]$Acao = 'buscar', [string]$Ids = '')
. "$PSScriptRoot\comum.ps1"
. "$PSScriptRoot\drivers-backup.ps1"
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
    Write-Log '@total 5'
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

    Write-Log '[....] enum game components'
    $componentes = @(); $erroComp = ''
    try {
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget indisponível' }
        $instalados = & winget.exe list --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "winget list saiu com $LASTEXITCODE" }
        # -1978335212 = nenhum pacote com atualizacao: nao e erro.
        $pendentes = & winget.exe list --source winget --upgrade-available --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        if ($LASTEXITCODE -notin 0, -1978335212) { throw "winget list --upgrade-available saiu com $LASTEXITCODE" }
        $componentes = @(Get-ComponentesJogos ((Read-Utf8 (Join-Path $script:Raiz 'programas.json')) | ConvertFrom-Json) $instalados $pendentes)
        foreach ($k in $componentes) { Write-Log "  | component state=$($k.estado) :: $($k.rotulo)" }
    } catch { $erroComp = $_.Exception.Message; Write-Log "  | components.error $erroComp" }
    Write-Log "  | components.found=$($componentes.Count)"
    Write-Log '[ ok ] enum game components'

    $saida = [ordered]@{ atualizacoes = @($lista); componentes = @($componentes); erroComponentes = $erroComp; problemas = @($problemas); antigos = $antigos.Count; gpu = @($gpu); ferramentas = @($ferramentas); paginas = @($pagina); fabricante = "$($sistema.Manufacturer) $($sistema.Model)"; erro = $erroBusca }
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

$ferr = @($pedidos | Where-Object { $_ -match '^(winget|atualizar):' })
if ($ferr.Count) {
    Wait-Internet; Initialize-Winget
    $conhecidos = @(((Read-Utf8 (Join-Path $script:Raiz 'programas.json')) | ConvertFrom-Json).maquina)
}
foreach ($f in $ferr) {
    $id = ($f -split ':', 2)[1]
    if (Test-Cancelado) { Write-Log "[cancelado] Programa $id"; continue }
    Write-Log "[....] Programa $id"
    # O pacote da lista traz o "detecta": sem ele, o DirectX instalado pareceria falha.
    $pacote = @($conhecidos | Where-Object { $_.id -eq $id })[0]
    if (-not $pacote) { $pacote = [pscustomobject]@{ id = $id } }
    $res = Install-Pacote $pacote -Atualizar:($f -like 'atualizar:*')
    if ($res -eq 'OK') { Write-Log "[ ok ] Programa $id" } else { Write-Log "[FALHOU] Programa $id - $res" Red }
}

if ($pedidos -contains 'netfx3') {
    if (Test-Cancelado) { Write-Log '[cancelado] NET Framework 3.5' }
    else {
        Write-Log '[....] NET Framework 3.5'
        $res = Enable-NetFx3
        if ($res -eq 'OK') { Write-Log '[ ok ] NET Framework 3.5' } else { Write-Log "[FALHOU] NET Framework 3.5 - $res" Red }
    }
}

$guids = @($pedidos | Where-Object { $_ -notmatch '^(winget|atualizar):' -and $_ -ne 'netfx3' })
if ($guids.Count) {
    $x = Abrir-Busca
    $r = $x.busca.Search($Consulta)
    $script:reiniciar = $false
    $pastaBackups = Join-Path $script:Dados 'drivers-backup'
    foreach ($g in $guids) {
        if (Test-Cancelado) { Write-Log "[cancelado] $g"; continue }
        $u = $null; foreach ($c in $r.Updates) { if ($c.Identity.UpdateID -eq $g) { $u = $c; break } }
        if (-not $u) { Write-Log "[FALHOU] $g - nao esta mais disponivel no catalogo" Red; continue }
        $nome = $u.Title
        Write-Log "[....] $nome"
        try {
            # Le de novo a cada atualizacao: a anterior pode ter trocado o driver do mesmo dispositivo.
            $alvos = @(Find-DispositivosAlvo "$($u.DriverHardwareID)" @(Get-DispositivosPnp))
            Write-Log "  | backup.targets=$($alvos.Count) hwid=$($u.DriverHardwareID)"
            $feito = Invoke-ComBackup $nome $g $alvos {
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
                # O bloco roda em escopo filho: sem script:, a marca de reinicio se perderia.
                if ($ri.RebootRequired) { $script:reiniciar = $true }
                if ($ri.ResultCode -notin 2, 3) { throw "install ResultCode=$($ri.ResultCode) HResult=$hr" }
            } $pastaBackups
            if ($feito) { Write-Log "[ ok ] $nome" }
        } catch { Write-Log "[FALHOU] $nome - $($_.Exception.Message)" Red }
    }
    if ($script:reiniciar) { Write-Log 'drivers.install reboot.required=True: reinicie o PC' Yellow }
}
Write-Log 'drivers.install done' Green
