# Funcoes do Anti-crash MTA. Nada aqui altera o jogo, exceto Set-ConfigMta no coreconfig.xml pedido.
. "$PSScriptRoot\comum.ps1"

$script:ChavesLeve = 'grass', 'heat_haze', 'tyre_smoke_enabled', 'volumetric_shadows'
$script:UrlOffsets = 'https://wiki.multitheftauto.com/wiki/Famous_crash_offsets_and_their_meaning'
$script:PadroesMods = 'd3d9.dll', '*.asi', 'modloader', 'cleo', 'scripts'
$script:PacotesMta = 'Microsoft.DirectX', 'Microsoft.VCRedist.2008.x86', 'Microsoft.VCRedist.2015+.x86'

# Causas conhecidas segundo a wiki do MTA. O offset e uma pista, nao uma certeza: a mensagem precisa dizer isso.
$script:OffsetsMta = @{
    memoria  = @{ Mensagem = 'Provavelmente faltou memória, em geral por servidor pesado. Tente o modo pouca memória.'; Lista = '003C91CC', '003C920C', '00357DEC', '003F5A3A', '004A1ED4', '00137D6E', '0014F406', '001D6E6A', '000CFCD6' }
    modelo   = @{ Mensagem = 'Provavelmente um modelo ruim do servidor ou um arquivo do GTA alterado.'; Lista = '00134134', '003F0C37', '003F0BF7', '011630F8', '011630FE', '01162FE3', '011630F2', '00171A10', '000C9F98', '00349B7B', '00165096', '003F18CF', '003F190F', '0019BD39', '000C9691' }
    sombras  = @{ Mensagem = 'Provavelmente um modelo sem suporte a sombras volumétricas. Tente o perfil leve.'; Lista = '0000F67C', '0000F663' }
    audio    = @{ Mensagem = 'Provavelmente um mod de som, o driver de áudio ou um arquivo de áudio.'; Lista = '000DFE92', '000DFF90' }
    arquivos = @{ Mensagem = 'Provavelmente um arquivo do GTA alterado ou corrompido. Verifique os arquivos na Steam.'; Lista = '00771848', '001B6B2F', '003EC9DA', '00423FD0', '000A2CF3', '001A49D4' }
    d3d9     = @{ Mensagem = 'Esse offset costuma aparecer com um d3d9.dll na pasta do GTA.'; Lista = @('00348CF4') }
}

function Find-Mta([string]$RaizRegistro = 'HKLM:\SOFTWARE\WOW6432Node\Multi Theft Auto: San Andreas All', [string]$DadosPrograma = $env:ProgramData) {
    if (-not (Test-Path -LiteralPath $RaizRegistro)) { return $null }
    $versoes = @(Get-ChildItem -LiteralPath $RaizRegistro | Where-Object { $_.PSChildName -match '^\d+\.\d+$' } | Sort-Object { [version]$_.PSChildName } -Descending)
    foreach ($v in $versoes) {
        $pasta = (Get-ItemProperty -LiteralPath $v.PSPath -Name 'Last Install Location' -ErrorAction SilentlyContinue).'Last Install Location'
        if (-not $pasta -or -not (Test-Path -LiteralPath (Join-Path $pasta 'Multi Theft Auto.exe'))) { continue }
        $gta = (Get-ItemProperty -LiteralPath (Join-Path $RaizRegistro 'Common') -Name 'GTA:SA Path' -ErrorAction SilentlyContinue).'GTA:SA Path'
        return [pscustomobject]@{
            Versao   = $v.PSChildName
            PastaMta = $pasta
            PastaGta = "$gta"
            # O jogo roda desta copia, nao da pasta do GTA.
            JogoExe  = Join-Path $DadosPrograma "MTA San Andreas All\$($v.PSChildName)\GTA San Andreas\gta_sa.exe"
            MtaExe   = Join-Path $pasta 'Multi Theft Auto.exe'
        }
    }
    return $null
}

# Os registros sao acrescentados ao fim do arquivo: vale o ultimo Offset e o que veio antes dele.
function Get-UltimoCrash([string]$Arquivo) {
    if (-not (Test-Path -LiteralPath $Arquivo)) { return $null }
    $linhas = @(Get-Content -LiteralPath $Arquivo)
    $fim = -1
    for ($i = $linhas.Count - 1; $i -ge 0; $i--) { if ($linhas[$i] -match '^Offset = 0x[0-9A-Fa-f]+') { $fim = $i; break } }
    if ($fim -lt 0) { return $null }
    $campos = @{}
    # Para no comeco do registro: Module vem vazio em crash fora de qualquer modulo, e nao pode herdar o do crash anterior.
    for ($i = $fim; $i -ge 0 -and $campos.Count -lt 4; $i--) {
        if ($i -lt $fim -and $linhas[$i] -match '^(Offset = |\*\* -- )') { break }
        if ($linhas[$i] -match '^(Time|Module|Code|Offset) =\s?(.*)$' -and -not $campos.ContainsKey($Matches[1])) { $campos[$Matches[1]] = $Matches[2].Trim() }
    }
    $hora = $null
    if ($campos['Time']) {
        # ctime usa dois espacos em dias de um digito.
        $texto = $campos['Time'] -replace '\s+', ' '
        try { $hora = [datetime]::ParseExact($texto, 'ddd MMM d HH:mm:ss yyyy', [Globalization.CultureInfo]::InvariantCulture) } catch { }
    }
    if (-not $hora) { $hora = (Get-Item -LiteralPath $Arquivo).LastWriteTime }
    [pscustomobject]@{ Hora = $hora; Modulo = "$($campos['Module'])"; Codigo = ("$($campos['Code'])" -replace '^0x', '').ToUpper(); Offset = ($campos['Offset'] -replace '^0x', '').ToUpper() }
}

function Get-CategoriaOffset([string]$Offset, [string]$Modulo, [string]$Codigo) {
    $valor = ($Offset -replace '^0[xX]', '').ToUpper()
    $doJogo = $Modulo -and (Split-Path -Leaf $Modulo) -match '^(gta_sa|proxy_sa)\.exe$'
    if ($doJogo) {
        foreach ($cat in $script:OffsetsMta.Keys) {
            if ($script:OffsetsMta[$cat].Lista -contains $valor) { return [pscustomobject]@{ Categoria = $cat; Mensagem = $script:OffsetsMta[$cat].Mensagem } }
        }
    } elseif ($Modulo -and $Codigo -match 'E06D7363') {
        return [pscustomobject]@{ Categoria = 'memoria'; Mensagem = $script:OffsetsMta['memoria'].Mensagem }
    }
    [pscustomobject]@{ Categoria = 'desconhecida'; Mensagem = "Causa desconhecida para o Offset $valor. Consulte $($script:UrlOffsets)" }
}

function Get-SessaoGrafica([string]$Log) {
    if (-not (Test-Path -LiteralPath $Log)) { return [pscustomobject]@{ Redefinicoes = 0; Placa = '' } }
    $linhas = @(Get-Content -LiteralPath $Log)
    $placa = ''; $jogoAberto = $false
    foreach ($l in $linhas) {
        if ($l -match 'ModuleFileName.*gta_sa\.exe') { $jogoAberto = $true }
        # O lancador tambem lista placas antes de o jogo abrir: so vale a que veio depois.
        elseif ($jogoAberto -and $l -match 'Description:(.+)$') { $placa = $Matches[1].Trim() }
    }
    [pscustomobject]@{ Redefinicoes = @($linhas | Where-Object { $_ -match 'CDirect3DEvents9::OnRestore' }).Count; Placa = $placa }
}

function Get-InterpolacaoRam([int]$RamMB, [int[]]$Pontos, [int[]]$Valores) {
    if ($RamMB -le $Pontos[0]) { return [double]$Valores[0] }
    for ($i = 1; $i -lt $Pontos.Count; $i++) {
        if ($RamMB -le $Pontos[$i]) {
            return [double]($Valores[$i - 1] + ($Valores[$i] - $Valores[$i - 1]) * ($RamMB - $Pontos[$i - 1]) / ($Pontos[$i] - $Pontos[$i - 1]))
        }
    }
    [double]$Valores[-1]
}

# Mesma conta de CalculateStreamingMemoryRange no CCore.cpp do MTA, que nao valida o valor gravado.
function Get-StreamingMinimo([int]$RamMB, [int]$VramMB) {
    if ($VramMB -le 0) { return 128 }
    $minimo = Get-InterpolacaoRam $RamMB @(512, 1024, 2048) @(64, 96, 128)
    $maximo = Get-InterpolacaoRam $RamMB @(512, 1024, 2048) @(96, 128, 256)
    $maximo = [Math]::Max([Math]::Min($maximo, $VramMB * 2), 96)
    $minimo = [Math]::Min($minimo, $VramMB)
    [int]($maximo - [Math]::Max($maximo - $minimo, 32))
}

# O MTA pode gravar o texto de um atalho em ANSI sem declarar a codificacao, e o XmlDocument supoe UTF-8 e recusa o arquivo.
# Le como UTF-8 quando o arquivo e UTF-8 valido; senao, byte a byte (Latin-1). Quem grava usa a mesma codificacao,
# para nenhum byte fora das chaves alteradas mudar.
function Read-XmlMta([string]$Arquivo, [bool]$Preservar = $false) {
    $bytes = [IO.File]::ReadAllBytes($Arquivo)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $inicio = if ($bom) { 3 } else { 0 }
    try {
        $texto = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes, $inicio, $bytes.Length - $inicio)
        $codificacao = New-Object Text.UTF8Encoding($bom)
    } catch {
        $codificacao = [Text.Encoding]::GetEncoding(28591)
        $texto = $codificacao.GetString($bytes)
    }
    $doc = New-Object Xml.XmlDocument
    $doc.PreserveWhitespace = $Preservar
    $doc.LoadXml($texto)
    [pscustomobject]@{ Doc = $doc; Codificacao = $codificacao }
}

function Get-ConfigMta([string]$Arquivo, [string[]]$Chaves) {
    $doc = (Read-XmlMta $Arquivo).Doc
    $saida = @{}
    foreach ($c in $Chaves) {
        $no = $doc.SelectSingleNode("/mainconfig/settings/$c")
        $saida[$c] = if ($no) { $no.InnerText } else { $null }
    }
    $saida
}

# Altera so as chaves pedidas e devolve os valores anteriores. Valor $null remove a chave.
# Grava em temporario e troca no fim: um erro nunca deixa o arquivo pela metade.
function Set-ConfigMta([string]$Arquivo, [hashtable]$Valores) {
    if ((Get-Item -LiteralPath $Arquivo).IsReadOnly) { throw "$Arquivo esta como somente leitura" }
    $lido = Read-XmlMta $Arquivo $true
    $doc = $lido.Doc
    $settings = $doc.SelectSingleNode('/mainconfig/settings')
    if (-not $settings) { throw "$Arquivo nao tem mainconfig/settings" }
    $anteriores = @{}
    foreach ($c in $Valores.Keys) {
        $no = $settings.SelectSingleNode($c)
        $anteriores[$c] = if ($no) { $no.InnerText } else { $null }
        if ($null -eq $Valores[$c]) { if ($no) { [void]$settings.RemoveChild($no) } }
        elseif ($no) { $no.InnerText = "$($Valores[$c])" }
        else { $novo = $doc.CreateElement($c); $novo.InnerText = "$($Valores[$c])"; [void]$settings.AppendChild($novo) }
    }
    $temp = "$Arquivo.tmp"
    try {
        # Sem isto, o Save acrescenta uma declaracao <?xml?> que o arquivo do MTA nao tem.
        $ajustes = New-Object Xml.XmlWriterSettings
        $ajustes.OmitXmlDeclaration = -not ($doc.FirstChild -is [Xml.XmlDeclaration])
        $escritor = New-Object IO.StreamWriter($temp, $false, $lido.Codificacao)
        try {
            $xml = [Xml.XmlWriter]::Create($escritor, $ajustes)
            try { $doc.Save($xml) } finally { $xml.Close() }
        } finally { $escritor.Close() }
        Set-ArquivoFinal $temp $Arquivo
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    $anteriores
}

function Test-MtaAberto([string[]]$Nomes = @('Multi Theft Auto', 'gta_sa', 'proxy_sa')) {
    [bool]@(Get-Process -Name $Nomes -ErrorAction SilentlyContinue).Count
}

function Test-DonoSessao([string]$Usuario, [string]$Dono) {
    [bool]($Usuario -and $Dono -and $Usuario -eq $Dono)
}

function Get-DonoSessao {
    $e = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
    if (-not $e) { return '' }
    "$((Invoke-CimMethod -InputObject $e -MethodName GetOwner).User)"
}

function Get-ModsGta([string]$PastaGta) {
    if (-not $PastaGta -or -not (Test-Path -LiteralPath $PastaGta)) { return }
    foreach ($p in $script:PadroesMods) { Get-ChildItem -LiteralPath $PastaGta -Filter $p -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } }
}

# So os tres pacotes que o MTA usa, mesmo que mta.json traga outra coisa.
function Install-ComponentesMta($Pedidos, $Programas) {
    $validos = @($Pedidos | Where-Object { $_ -match '^(winget|atualizar):' -and $script:PacotesMta -contains ($_ -split ':', 2)[1] })
    if (-not $validos.Count) { return }
    Wait-Internet
    Initialize-Winget
    $falhas = 0
    foreach ($pedido in $validos) {
        if (Test-Cancelado) { break }
        $id = ($pedido -split ':', 2)[1]
        $pacote = @($Programas.maquina | Where-Object { $_.id -eq $id })[0]
        if (-not $pacote) { $pacote = [pscustomobject]@{ id = $id } }
        $res = Install-Pacote $pacote -Atualizar:($pedido -like 'atualizar:*')
        Write-Log "  | $id => $res"
        if ($res -ne 'OK') { $falhas++ }
    }
    if ($falhas) { throw "$falhas de $($validos.Count) componentes nao entraram" }
}

# Regras de "Aparece" e "Marcada". $Estado tem o formato de mta.json.
function Get-CorrecoesMta($Estado) {
    $cfg = $Estado.config
    $valor = { param($chave) if ($cfg -is [hashtable]) { $cfg[$chave] } else { $cfg.$chave } }
    function Linha($Id, $Rotulo, $Detalhe, $Marcada) { [pscustomobject]@{ Id = $Id; Rotulo = $Rotulo; Detalhe = $Detalhe; Marcada = [bool]$Marcada } }

    if ([int]$Estado.tela -eq 0) {
        Linha 'semborda' 'Modo sem borda' "Tela cheia exclusiva redefine o vídeo ao trocar de janela. Última sessão: $($Estado.redefinicoes) redefinições." ([int]$Estado.redefinicoes -ge 5)
    }
    if ($Estado.temIntegrada -and $Estado.temDedicada) {
        Linha 'gpu' 'Usar a placa dedicada' 'Preferência do Windows para o MTA e o gta_sa.exe que ele abre.' $Estado.sessaoNaIntegrada
    }
    if (@($Estado.mods).Count -gt 0) {
        Linha 'mods' 'Tirar mods da pasta do GTA' "$(@($Estado.mods).Count) item(ns) movidos para o backup, sem apagar. Eles podem causar crash ou expulsão." $true
    }
    if (@($Estado.componentes).Count -gt 0) {
        Linha 'componentes' 'Instalar componentes que faltam' 'DirectX e Visual C++ x86 usados pelo MTA. Não são removidos ao reverter.' $true
    }
    if (@($script:ChavesLeve | Where-Object { "$(& $valor $_)" -ne '0' }).Count) {
        Linha 'leve' 'Perfil leve de gráficos' 'Desliga grama, neblina de calor, fumaça de pneu e sombras volumétricas.' $false
    }
    if ([int]"$(& $valor 'streaming_memory')" -gt [int]$Estado.streamingMinimo) {
        $recente = $Estado.crash -and $Estado.crash.categoria -eq 'memoria' -and ((Get-Date) - [datetime]$Estado.crash.hora).TotalDays -lt 30
        Linha 'memoria' 'Modo pouca memória' "Baixa a memória de streaming para $($Estado.streamingMinimo) MB, como a wiki indica em crash de memória." $recente
    }
    if ("$(& $valor 'process_priority')" -in '', '0') {
        Linha 'prioridade' 'Prioridade acima do normal' 'Opção do próprio MTA. Ganho não medido.' $false
    }
    if ($Estado.gtaSet) {
        Linha 'gtaset' 'Refazer gta_sa.set' 'Renomeia o arquivo de opções do GTA. Passo indicado pela equipe do MTA.' $false
    }
}
