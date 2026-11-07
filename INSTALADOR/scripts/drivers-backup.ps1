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
    # Critico = a recusa vale para o registro inteiro no Voltar, nao so para este dispositivo.
    $nao = { param($motivo, $critico = $false) [pscustomobject]@{ Pode = $false; Motivo = $motivo; Critico = $critico } }
    if (Test-ClasseCritica $Registrado.classe) { return & $nao 'Dispositivo essencial ao sistema: use o Gerenciador de Dispositivos.' $true }
    if (-not $Atual) { return & $nao 'Dispositivo não conectado.' }
    if (Test-ClasseCritica $Atual.Classe) { return & $nao 'Dispositivo essencial ao sistema: use o Gerenciador de Dispositivos.' $true }
    # O numero oem pode mudar ao reinstalar: so comparar o numero removeria o driver recem-restaurado.
    if ($Atual.Inf -eq $Registrado.infAntes -or $Atual.Versao -eq $Registrado.versaoAntes) { return & $nao 'Já está nessa versão.' }
    if ($Atual.Inf -notmatch '^oem\d+\.inf$') { return & $nao 'O driver atual é do Windows e não pode ser removido.' }
    # /delete-driver /uninstall tira o pacote de todos os dispositivos que o usam.
    $criticos = @(@($Todos) | Where-Object { $_.Inf -eq $Atual.Inf -and (Test-ClasseCritica $_.Classe) })
    if ($criticos.Count) { return & $nao "O pacote também é usado por $($criticos[0].Nome), essencial ao sistema." $true }
    [pscustomobject]@{ Pode = $true; Motivo = ''; Critico = $false }
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

# \z, e nao $: o $ do .NET aceita uma quebra de linha no fim, e o id vira parte de um caminho.
function Test-IdBackup([string]$Id) { $Id -cmatch '^\d{8}-\d{6}-[0-9a-f]{8}\z' }

function Get-PastaPacote([string]$Pasta, $Registrado) { Join-Path $Pasta ([IO.Path]::GetFileNameWithoutExtension("$($Registrado.infAntes)")) }

function Test-PacoteSalvo([string]$Pasta, $Registrado) {
    if (-not $Registrado.exportado) { return $true }
    $sub = Get-PastaPacote $Pasta $Registrado
    (Test-Path -LiteralPath $sub -PathType Container) -and @(Get-ChildItem -LiteralPath $sub -Filter *.inf -Recurse -ErrorAction SilentlyContinue).Count -gt 0
}

# Decide cada dispositivo do registro com os dados de agora; a tela e o Voltar usam a mesma conta.
function Get-PlanoVolta([string]$Pasta, $Registro, $Todos) {
    $plano = @(foreach ($reg in @($Registro.dispositivos | Where-Object { $_ })) {
        $atual = @(@($Todos) | Where-Object { $_ -and $_.DeviceId -eq $reg.deviceId })[0]
        $dec = Test-PodeVoltar $reg $atual $Todos
        if ($dec.Pode -and -not (Test-PacoteSalvo $Pasta $reg)) {
            $dec = [pscustomobject]@{ Pode = $false; Motivo = 'O pacote salvo não está mais na pasta do backup.'; Critico = $true }
        }
        [pscustomobject]@{ Registrado = $reg; Atual = $atual; Pode = $dec.Pode; Motivo = $dec.Motivo; Critico = $dec.Critico }
    })
    # /delete-driver /uninstall atinge todos os dispositivos do pacote: um item critico recusa o registro inteiro.
    $bloqueio = @($plano | Where-Object { $_.Critico })
    if ($bloqueio.Count) { foreach ($p in @($plano | Where-Object { -not $_.Critico })) { $p.Pode = $false; $p.Motivo = "Recusado: $($bloqueio[0].Motivo)" } }
    $plano
}

function Get-AvisoClasse([string]$Classe) { if ($Classe -eq 'Display') { 'tela' } elseif ($Classe -eq 'Net') { 'internet' } else { '' } }

# Dispositivos fora do registro que usam um pacote que o Voltar vai remover: o /uninstall tira o driver deles tambem.
function Get-AfetadosVolta($Plano, $Todos) {
    $infs = @($Plano | Where-Object { $_.Pode } | ForEach-Object { "$($_.Atual.Inf)".ToLowerInvariant() } | Select-Object -Unique)
    $ids = @($Plano | ForEach-Object { "$($_.Registrado.deviceId)" })
    @(@($Todos) | Where-Object { $_ -and $infs -contains "$($_.Inf)".ToLowerInvariant() -and $ids -notcontains "$($_.DeviceId)" })
}

# Um registro com erro aparece como ilegivel e nunca e apagado aqui.
function Get-BackupsDrivers([string]$Pasta, $Dispositivos) {
    if (-not (Test-Path -LiteralPath $Pasta -PathType Container)) { return }
    $pastas = @(Get-ChildItem -LiteralPath $Pasta -Directory -ErrorAction SilentlyContinue | Where-Object { Test-IdBackup $_.Name } | Sort-Object Name -Descending)
    foreach ($dir in $pastas) {
        $arq = Join-Path $dir.FullName 'backup.json'
        if (-not (Test-Path -LiteralPath $arq -PathType Leaf)) { continue }
        $bytes = [double](@(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue) | Measure-Object Length -Sum).Sum
        $mb = if ($bytes -gt 0) { [Math]::Max(0.01, [Math]::Round($bytes / 1MB, 2)) } else { 0 }
        try {
            $j = Read-Utf8 $arq | ConvertFrom-Json -ErrorAction Stop
            if (-not $j -or $null -eq $j.PSObject.Properties['dispositivos']) { throw 'registro sem dispositivos' }
            $plano = @(Get-PlanoVolta $dir.FullName $j $Dispositivos)
            $linhas = @($plano | ForEach-Object {
                $classe = "$($_.Registrado.classe)"
                [ordered]@{
                    deviceId = "$($_.Registrado.deviceId)"; nome = "$($_.Registrado.nome)"; classe = $classe
                    versaoAntes = "$($_.Registrado.versaoAntes)"; versaoAgora = "$($_.Atual.Versao)"; infAgora = "$($_.Atual.Inf)"
                    presente = [bool]$_.Atual; podeVoltar = [bool]$_.Pode; motivo = "$($_.Motivo)"; aviso = Get-AvisoClasse $classe
                }
            })
            $afetados = @(Get-AfetadosVolta $plano $Dispositivos | ForEach-Object { [ordered]@{ nome = "$($_.Nome)"; classe = "$($_.Classe)"; aviso = Get-AvisoClasse "$($_.Classe)" } })
            [pscustomobject][ordered]@{ id = $dir.Name; criado = "$($j.criado)"; titulo = "$($j.titulo)"; mb = $mb; legivel = $true; dispositivos = $linhas; afetados = $afetados }
        } catch {
            [pscustomobject][ordered]@{ id = $dir.Name; criado = ''; titulo = 'Backup ilegível'; mb = $mb; legivel = $false; dispositivos = @(); afetados = @() }
        }
    }
}

# Tenta voltar todos os dispositivos do registro e confere a versao real depois.
# $LerDispositivos devolve a lista de agora; $AntesDeRemover roda uma vez, antes do primeiro /delete-driver.
function Invoke-VoltarDriver([string]$Id, [string]$Pasta, [scriptblock]$LerDispositivos, [scriptblock]$AntesDeRemover = {}) {
    if (-not (Test-IdBackup $Id)) { throw "id de backup inválido: $Id" }
    $dir = Join-Path $Pasta $Id
    $registro = Read-Utf8 (Join-Path $dir 'backup.json') | ConvertFrom-Json -ErrorAction Stop
    $todos = @(& $LerDispositivos)
    $plano = @(Get-PlanoVolta $dir $registro $todos)
    $ids = @($plano | ForEach-Object { "$($_.Registrado.deviceId)" })
    Write-Log "@total $($plano.Count + 1)"
    $res = @{}
    $fim = {
        param($Item, [string]$Resultado, [string]$Motivo)
        $nome = "$($Item.Registrado.nome)"
        $res[$Item.Registrado.deviceId] = [pscustomobject]@{ deviceId = "$($Item.Registrado.deviceId)"; nome = $nome; resultado = $Resultado; motivo = $Motivo }
        $sufixo = if ($Motivo) { " - $Motivo" } else { '' }
        if ($Resultado -eq 'nao-voltou') { Write-Log "[FALHOU] Voltar $nome$sufixo" Red } else { Write-Log "[ ok ] Voltar $nome$sufixo" }
    }
    $naoVoltou = "Não voltou. Tente Reverter driver no Gerenciador de Dispositivos. O backup continua em $dir."
    # Um item critico ja recusou o registro inteiro em Get-PlanoVolta: nenhum grupo sobra para remover.
    foreach ($p in @($plano | Where-Object { -not $_.Pode })) {
        if ($p.Atual -and $p.Motivo -like 'Já está nessa versão*') { & $fim $p 'voltou' 'já estava na versão salva' } else { & $fim $p 'nao-voltou' $p.Motivo }
    }
    $preparado = $false
    foreach ($grupo in @($plano | Where-Object { $_.Pode } | Group-Object { "$($_.Atual.Inf)".ToLowerInvariant() })) {
        $itens = @($grupo.Group); $inf = $grupo.Name
        if (Test-Cancelado) { foreach ($p in $itens) { & $fim $p 'nao-voltou' 'Cancelado antes de começar.' }; continue }
        if (-not $preparado) {
            $null = & $AntesDeRemover; $preparado = $true
            # O ponto de restauracao pode levar um minuto: um Cancelar nesse meio ainda chega antes de remover.
            if (Test-Cancelado) { foreach ($p in $itens) { & $fim $p 'nao-voltou' 'Cancelado antes de começar.' }; continue }
        }
        foreach ($p in $itens) { Write-Log "[....] Voltar $($p.Registrado.nome)" }
        $outros = @(@($todos) | Where-Object { $_ -and "$($_.Inf)".ToLowerInvariant() -eq $inf -and $ids -notcontains "$($_.DeviceId)" })
        if ($outros.Count) { Write-Log "  | $inf também atende, e perde este driver: $(($outros | ForEach-Object { $_.Nome }) -join ', ')" }
        # Daqui em diante o pacote termina: parar no meio deixaria o dispositivo sem driver.
        $codigo = Invoke-Pnputil @('/delete-driver', $inf, '/uninstall')
        if ($codigo -notin 0, 3010) { foreach ($p in $itens) { & $fim $p 'nao-voltou' "pnputil /delete-driver $inf saiu com $codigo. Nada foi trocado." }; continue }
        $reinicio = $codigo -eq 3010
        $salvos = @($itens | Where-Object { $_.Registrado.exportado })
        foreach ($sub in @($salvos | ForEach-Object { Get-PastaPacote $dir $_.Registrado } | Select-Object -Unique)) {
            $c2 = Invoke-Pnputil @('/add-driver', (Join-Path $sub '*.inf'), '/subdirs', '/install')
            if ($c2 -eq 3010) { $reinicio = $true }
        }
        if ($salvos.Count -lt $itens.Count) {
            $c3 = Invoke-Pnputil @('/scan-devices')
            if ($c3 -eq 3010) { $reinicio = $true }
        }
        $agora = @(& $LerDispositivos)
        foreach ($p in $itens) {
            $d = @($agora | Where-Object { $_ -and $_.DeviceId -eq $p.Registrado.deviceId })[0]
            if ($d -and $d.Versao -eq $p.Registrado.versaoAntes) { & $fim $p 'voltou' '' }
            elseif ($reinicio -or ($d -and $d.Versao -eq $p.Atual.Versao)) { & $fim $p 'reiniciar' 'reinicie o PC para terminar' }
            else { & $fim $p 'nao-voltou' $naoVoltou }
        }
    }
    foreach ($p in $plano) { $res[$p.Registrado.deviceId] }
}

# Apaga so a pasta do registro pedido, depois de conferir que ela fica dentro de $Pasta.
function Remove-BackupDriver([string]$Id, [string]$Pasta) {
    if (-not (Test-IdBackup $Id)) { throw "id de backup inválido: $Id" }
    $raiz = [IO.Path]::GetFullPath($Pasta).TrimEnd('\')
    $alvo = [IO.Path]::GetFullPath((Join-Path $raiz $Id))
    if ([IO.Path]::GetDirectoryName($alvo) -ne $raiz) { throw "caminho fora da pasta de backups: $alvo" }
    if (-not (Test-Path -LiteralPath $alvo -PathType Container)) { throw "backup $Id não existe" }
    [IO.Directory]::Delete($alvo, $true)
}
