# Backup de drivers: guarda o driver que uma atualizacao vai substituir e tenta voltar a ele.
# So define funcoes: quem chama e drivers.ps1, depois de carregar comum.ps1.

# Um erro nestas classes pode impedir o Windows de iniciar: o Voltar nunca mexe nelas.
$script:ClassesCriticas = 'DiskDrive', 'HDC', 'SCSIAdapter', 'System', 'Computer', 'Processor', 'Volume', 'VolumeSnapshot', 'Firmware', 'SecurityDevices'

function Test-ClasseCritica([string]$Classe) { $script:ClassesCriticas -contains $Classe }

function Get-DispositivosPnp {
    $assinados = @{}
    # Stop: uma leitura vazia por erro faria a instalacao seguir sem backup.
    foreach ($s in Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop) { if ($s.DeviceID) { $assinados[$s.DeviceID] = $s } }
    foreach ($e in Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object DeviceID) {
        $a = $assinados[$e.DeviceID]
        [pscustomobject]@{
            DeviceId = $e.DeviceID; Nome = "$($e.Name)"; Classe = "$($e.PNPClass)"
            Ids = @(@($e.HardwareID) + @($e.CompatibleID) | Where-Object { $_ })
            Inf = "$($a.InfName)"; Versao = "$($a.DriverVersion)"
            Data = $(if ($a -and $a.DriverDate) { $a.DriverDate.ToString('yyyy-MM-dd') } else { '' })
        }
    }
}

function Find-DispositivosAlvo([string]$HardwareId, $Dispositivos) {
    if (-not $HardwareId) { return }
    @($Dispositivos) | Where-Object { $_ -and @($_.Ids) -contains $HardwareId }
}

# $Registrado e uma linha do backup.json; $Atual e o dispositivo agora, ou $null; $Todos e a lista completa.
function Test-PodeVoltar($Registrado, $Atual, $Todos) {
    $nao = { param($motivo) [pscustomobject]@{ Pode = $false; Motivo = $motivo } }
    if (Test-ClasseCritica $Registrado.classe) { return & $nao 'Dispositivo essencial ao sistema: use o Gerenciador de Dispositivos.' }
    if (-not $Atual) { return & $nao 'Dispositivo não conectado.' }
    if (Test-ClasseCritica $Atual.Classe) { return & $nao 'Dispositivo essencial ao sistema: use o Gerenciador de Dispositivos.' }
    # O numero oem pode mudar ao reinstalar: so comparar o numero removeria o driver recem-restaurado.
    if ($Atual.Inf -eq $Registrado.infAntes -or $Atual.Versao -eq $Registrado.versaoAntes) { return & $nao 'Já está nessa versão.' }
    if ($Atual.Inf -notmatch '^oem\d+\.inf$') { return & $nao 'O driver atual é do Windows e não pode ser removido.' }
    # /delete-driver /uninstall tira o pacote de todos os dispositivos que o usam.
    $criticos = @(@($Todos) | Where-Object { $_.Inf -eq $Atual.Inf -and (Test-ClasseCritica $_.Classe) })
    if ($criticos.Count) { return & $nao "O pacote também é usado por $($criticos[0].Nome), essencial ao sistema." }
    [pscustomobject]@{ Pode = $true; Motivo = '' }
}

# Todo pnputil passa por aqui: os testes trocam o executavel, e /force nunca e usado.
$script:PnputilExe = "$env:windir\System32\pnputil.exe"

function Invoke-Pnputil([string[]]$Argumentos) {
    Write-Log "  | pnputil $($Argumentos -join ' ')"
    $saida = & $script:PnputilExe @Argumentos 2>&1 | Out-String
    $codigo = $LASTEXITCODE
    foreach ($l in @($saida -split "`r?`n" | Where-Object { $_.Trim() })) { Write-Log "  |   $($l.Trim())" }
    Write-Log "  | pnputil.exit=$codigo"
    $codigo
}

# Guarda o driver atual de cada dispositivo. Cada pacote oem vai para uma subpasta propria,
# para dois pacotes com arquivos de mesmo nome nao se sobrescreverem. Lanca em qualquer falha.
function New-BackupDriver($Titulo, [string]$UpdateId, $Dispositivos, [string]$Pasta) {
    $sufixo = ($UpdateId -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
    if ($sufixo.Length -lt 8) { throw "UpdateID inválido: $UpdateId" }
    $id = '{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), $sufixo.Substring(0, 8)
    $destino = Join-Path $Pasta $id
    if (Test-Path -LiteralPath $destino) { throw "backup $id já existe" }
    [void][IO.Directory]::CreateDirectory($destino)
    try {
        $lista = @($Dispositivos | Where-Object { $_ })
        foreach ($inf in @($lista | Where-Object { $_.Inf -match '^oem\d+\.inf$' } | ForEach-Object { $_.Inf.ToLowerInvariant() } | Select-Object -Unique)) {
            $sub = Join-Path $destino ([IO.Path]::GetFileNameWithoutExtension($inf))
            [void][IO.Directory]::CreateDirectory($sub)
            $codigo = Invoke-Pnputil @('/export-driver', $inf, $sub)
            if ($codigo -ne 0) { throw "pnputil /export-driver $inf saiu com $codigo" }
            if (-not @(Get-ChildItem -LiteralPath $sub -Filter *.inf -ErrorAction Stop).Count) { throw "a exportação de $inf não gerou nenhum .inf" }
        }
        $linhas = @($lista | ForEach-Object {
            [ordered]@{ deviceId = $_.DeviceId; nome = $_.Nome; classe = $_.Classe; infAntes = $_.Inf; versaoAntes = $_.Versao; dataAntes = $_.Data; exportado = ($_.Inf -match '^oem\d+\.inf$') }
        })
        $registro = [ordered]@{ id = $id; criado = (Get-Date).ToString('s'); titulo = "$Titulo"; dispositivos = $linhas }
        Write-Atomico (Join-Path $destino 'backup.json') ($registro | ConvertTo-Json -Depth 4)
    } catch {
        # Um backup pela metade nao e backup: so esta pasta, criada agora, sai.
        [IO.Directory]::Delete($destino, $true)
        throw
    }
    [pscustomobject]@{ Id = $id; Pasta = $destino; Dispositivos = $linhas }
}

# Instala so depois de o backup existir. Falha no backup: registra e devolve $false, sem instalar.
# Erro dentro de $Instalar sobe para quem chamou.
function Invoke-ComBackup($Titulo, $UpdateId, $Dispositivos, [scriptblock]$Instalar, [string]$Pasta) {
    try { $b = New-BackupDriver $Titulo $UpdateId $Dispositivos $Pasta }
    catch { Write-Log "[FALHOU] $Titulo - backup falhou: $($_.Exception.Message)" Red; return $false }
    Write-Log "  | backup id=$($b.Id) devices=$(@($b.Dispositivos).Count) exported=$(@($b.Dispositivos | Where-Object { $_.exportado }).Count)"
    $null = & $Instalar
    $true
}
