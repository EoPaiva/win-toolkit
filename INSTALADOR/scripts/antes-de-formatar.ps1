# Roda no PC QUE SERA FORMATADO. Nao apaga nada do PC e nao copia programas, logs nem arquivos pessoais.
# Itens: dados, programas, rede, loja, completos, wifi. Tudo fica ao lado do app, para a instalacao usar depois.
param([string]$Itens = 'dados,programas,rede')
. "$PSScriptRoot\comum.ps1"
if ($env:COMPUTERNAME -eq 'MARINETE') { Write-Log 'policy.deny host=MARINETE reason=source-of-configs: nada foi alterado' Red; exit 1 }

$pedidos = @($Itens -split ',' | Where-Object { $_ })
# Ficam de fora componentes do Windows, o que a limpeza remove e utilitarios de fabricante.
$ignorar = '^(Microsoft\.(VCLibs|UI\.Xaml|WindowsAppRuntime|AppInstaller|Edge|EdgeWebView2Runtime|Office|Teams|OneDrive|GamingApp|Outlook|365Copilot|Copilot|DotNet\.Native|WindowsTerminal|PowerShell|VCRedist|DotNet|OpenCLGLVulkan|GameInput|DirectX)|Nvidia\.|AMD\.|Intel\.|Realtek\.|Acer\.|ASUS\.|Lenovo\.|Dell\.|HP\.|MSI\.|Gigabyte\.)'

function Limpar-Pasta([string]$Pasta) {
    if (Test-Path -LiteralPath $Pasta) { Get-ChildItem -LiteralPath $Pasta -Force | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force } }
    New-Item -ItemType Directory -Force $Pasta | Out-Null
}

function Get-IdsExportados([string]$Fonte) {
    $temp = Join-Path $script:Logs "export-$Fonte-$PID.json"
    & winget.exe export -o $temp --source $Fonte --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    if (-not (Test-Path -LiteralPath $temp)) { throw "winget export --source $Fonte nao gerou a lista (codigo $LASTEXITCODE)" }
    try {
        $e = (Read-Utf8 $temp) | ConvertFrom-Json
        @($e.Sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier } | Where-Object { $_ } | Sort-Object -Unique)
    } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

Write-Log "@total $($pedidos.Count + 1)"
Write-Log "format.prepare start items=$($pedidos -join ',') folder=$script:Raiz" Cyan

if ($pedidos -contains 'dados') {
    Passo 'Dados deste PC' {
        $sistema = Get-CimInstance Win32_ComputerSystem
        $linhas = New-Object System.Collections.ArrayList
        [void]$linhas.Add("Modelo: $($sistema.Manufacturer) $($sistema.Model)")
        [void]$linhas.Add("Processador: $((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)")
        [void]$linhas.Add("Memoria: $([math]::Round($sistema.TotalPhysicalMemory / 1GB)) GB")
        [void]$linhas.Add("Windows atual: $((Get-CimInstance Win32_OperatingSystem).Caption)")
        try {
            $lic = (Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKeyDescription
            [void]$linhas.Add("Licenca gravada na placa-mae: $(if ($lic) { $lic } else { 'nenhuma' })")
        } catch { [void]$linhas.Add('Licenca gravada na placa-mae: nao lida') }
        foreach ($d in Get-Disk -ErrorAction SilentlyContinue) { [void]$linhas.Add("Disco $($d.Number): $($d.FriendlyName), $([math]::Round($d.Size / 1GB)) GB, $($d.BusType)") }
        foreach ($v in Get-CimInstance Win32_VideoController) { [void]$linhas.Add("Video: $($v.Name)") }
        foreach ($n in Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=True') { [void]$linhas.Add("Rede: $($n.Name)") }
        Write-Utf8 (Join-Path $script:Raiz 'pc-alvo.txt') (($linhas -join "`r`n") + "`r`n")
        Write-Log "  | $($linhas.Count) linhas em pc-alvo.txt"
    }
}

if ($pedidos -contains 'programas') {
    Passo 'Lista de programas (winget)' {
        # Fora do catalogo nao entra: o instalador baixa a versao mais nova de cada um.
        $ids = @(Get-IdsExportados 'winget' | Where-Object { $_ -notmatch $ignorar })
        $texto = @('# Programas para instalar na versao mais nova. Apague a linha do que voce nao quiser.') + $ids
        Write-Utf8 (Join-Path $script:Raiz 'programas-do-pc.txt') (($texto -join "`r`n") + "`r`n")
        Write-Log "  | $($ids.Count) programas em programas-do-pc.txt"
    }
}

if ($pedidos -contains 'rede') {
    Passo 'Driver das placas de rede' {
        $pasta = Join-Path $script:Raiz 'drivers'
        Limpar-Pasta $pasta
        $redes = @(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" | Where-Object { $_.DeviceID -match '^(PCI|USB|SDIO)\\' -and $_.InfName -match '^oem\d+\.inf$' })
        $infs = @($redes | Select-Object -ExpandProperty InfName -Unique)
        if (-not $infs.Count) { Write-Log '  | nenhum driver de rede de terceiros: o proprio Windows cuida da rede deste PC'; return }
        $falhas = 0
        foreach ($i in $infs) {
            & pnputil.exe /export-driver $i $pasta 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $falhas++; Write-Log "  | $i falhou (codigo $LASTEXITCODE)" }
        }
        if ($falhas) { throw "$falhas de $($infs.Count) drivers nao copiados: tenha cabo de rede ou celular roteando por USB" }
        Write-Log "  | $($infs.Count) driver(s) em drivers\"
    }
}

if ($pedidos -contains 'loja') {
    Passo 'Lista de apps da Loja' {
        $ids = @(Get-IdsExportados 'msstore')
        # O mesmo programa aparece nos dois catalogos (Discord.Discord e o Discord da Loja): sem isto, instalaria duas vezes.
        $repetidos = @(Get-IdsExportados 'winget' | ForEach-Object { ($_ -split '\.')[-1] })
        $lista = (Read-Utf8 (Join-Path $script:Raiz 'programas.json')) | ConvertFrom-Json
        $repetidos += @($lista.maquina + $lista.usuario | ForEach-Object { $_.rotulo })
        $repetidos = @($repetidos | ForEach-Object { $_ -replace '\s', '' })
        $puladas = 0
        $texto = New-Object System.Collections.ArrayList
        [void]$texto.Add('# Apps da Microsoft Store para reinstalar. Apague a linha do que voce nao quiser.')
        foreach ($id in $ids) {
            if (Test-Cancelado) { break }
            # A primeira linha traz o nome: "Encontrado Nome do App [ID]". A primeira palavra muda com o idioma.
            $s = & winget.exe show --id $id --exact --source msstore --accept-source-agreements --disable-interactivity 2>&1 | Out-String
            $nome = if ($s -match "(?m)^\S+ (.+) \[$([regex]::Escape($id))\]") { $Matches[1].Trim() } else { $id }
            if ($repetidos -contains ($nome -replace '\s', '')) { $puladas++; continue }
            [void]$texto.Add("$id # $nome")
        }
        Write-Utf8 (Join-Path $script:Raiz 'loja-do-pc.txt') (($texto -join "`r`n") + "`r`n")
        Write-Log "  | $($ids.Count - $puladas) apps em loja-do-pc.txt, $puladas ja na lista de programas"
    }
}

if ($pedidos -contains 'completos') {
    Passo 'Todos os drivers' {
        # Ficam so guardados: instalar todos sozinho poderia trocar um driver novo por um antigo.
        $pasta = Join-Path $script:Raiz 'drivers-completos'
        Limpar-Pasta $pasta
        & pnputil.exe /export-driver * $pasta 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "pnputil terminou com codigo $LASTEXITCODE" }
        $arqs = @(Get-ChildItem -LiteralPath $pasta -Recurse -File -Force)
        if (-not @($arqs | Where-Object { $_.Extension -eq '.inf' }).Count) { throw 'pnputil nao copiou nenhum driver' }
        Write-Log ("  | {0} arquivos, {1:N1} GB em drivers-completos\" -f $arqs.Count, (($arqs | Measure-Object Length -Sum).Sum / 1GB))
    }
}

if ($pedidos -contains 'wifi') {
    Passo 'Redes Wi-Fi com senhas' {
        $pasta = Join-Path $script:Raiz 'wifi'
        Limpar-Pasta $pasta
        $svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -ne 'Running') { Write-Log '  | este PC nao esta usando Wi-Fi: nada a copiar'; return }
        # Nunca registrar a saida do netsh nem o conteudo destes arquivos: as senhas estao em texto puro.
        & netsh.exe wlan export profile key=clear "folder=$pasta" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "netsh terminou com codigo $LASTEXITCODE" }
        $n = @(Get-ChildItem -LiteralPath $pasta -Filter '*.xml' -File).Count
        Write-Log "  | $n redes em wifi\, com senha em texto puro. A instalacao apaga os arquivos ao importar."
    }
}

Passo 'O que NAO foi copiado' {
    foreach ($p in 'Desktop', 'Documents', 'Downloads', 'Pictures', 'Videos', 'Music', 'Saved Games') {
        $o = Join-Path $env:USERPROFILE $p
        if (Test-Path -LiteralPath $o) {
            # 0x400000: arquivo so na nuvem, que formatar nao perde.
            $t = (Get-ChildItem -LiteralPath $o -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band 0x400000) } | Measure-Object Length -Sum).Sum
            Write-Log ("  | {0,8:N1} GB  {1}" -f ($t / 1GB), $o)
        }
    }
    Write-Log '  | confira tambem o OneDrive, outras particoes e pastas na raiz do C:'
}

Write-Log 'format.prepare done: nada foi apagado deste PC. Tenha a chave do Windows em maos, se ela nao estiver na placa-mae.' Green
