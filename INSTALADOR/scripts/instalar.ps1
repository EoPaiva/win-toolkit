# Instalador principal. Precisa rodar SEM administrador: Spotify e outros recusam instalar elevados,
# e programas por usuario iriam para o perfil errado. A parte de maquina pede UAC uma unica vez.
. "$PSScriptRoot\comum.ps1"

if ($env:COMPUTERNAME -eq 'MARINETE') { Write-Log 'PC de origem das configs: nada foi instalado.' Red; exit 1 }

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Feche esta janela e abra upaiva.dev.exe com dois cliques, sem "Executar como administrador".' -ForegroundColor Yellow
    Read-Host 'Enter para sair' | Out-Null
    exit 1
}

if (Test-Path -LiteralPath $script:Relatorio) { Remove-Item -LiteralPath $script:Relatorio -Force }
$programas = (Read-Utf8 (Join-Path $script:Raiz 'programas.json')) | ConvertFrom-Json

Write-Log 'Etapa 1 de 3: programas do sistema. Clique em Sim no aviso do Windows.' Cyan
$admin = Start-Process powershell.exe -Verb RunAs -PassThru -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\fase-admin.ps1`""
if ($admin) { $admin.WaitForExit() } else { Add-Resultado 'FALHOU' 'Fase de administrador' 'o aviso do Windows foi recusado' }
Update-Path

Write-Log 'Etapa 2 de 3: seus programas.' Cyan
Wait-Internet
Initialize-Winget
$fila = @(foreach ($p in $programas.usuario) { New-ItemPrograma "Programa $(if ($p.nome) { $p.nome } else { $p.id })" $p })

# Programas anotados no PC antes de formatar: so os nomes, instalados na versao mais nova.
$listaPc = Join-Path $script:Raiz 'programas-do-pc.txt'
if (Test-Path -LiteralPath $listaPc) {
    $conhecidos = @($programas.maquina | ForEach-Object { $_.id }) + @($programas.usuario | ForEach-Object { $_.id })
    Get-Content -LiteralPath $listaPc | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') -and $conhecidos -notcontains $_ } | ForEach-Object {
        $fila += New-ItemPrograma "Programa $_" ([pscustomobject]@{ id = $_ })
    }
}
Invoke-Programas $fila

Write-Log 'Etapa 3 de 3: dependencias, skills e configuracoes.' Cyan
$casa = $env:USERPROFILE
Add-UserPath (Join-Path $casa '.local\bin')
Add-UserPath (Join-Path $env:APPDATA 'npm')
Add-UserPath (Join-Path $env:APPDATA 'Python\Python314\Scripts')
Add-UserPath (Join-Path $casa 'AppData\Local\Programs\codebase-memory-mcp')

Invoke-Etapa 'Restaurar skills e configs' { & (Join-Path $PSScriptRoot 'restaurar-configs.ps1') -Etapa arquivos }
Invoke-Etapa 'Restaurar RTK e codebase-memory' { & (Join-Path $PSScriptRoot 'restaurar-configs.ps1') -Etapa binarios }

foreach ($v in $programas.uv_python) {
    Invoke-Etapa "Python $v via uv" {
        $c = Invoke-ComTempo 'uv' "python install $v" 15 "uv-python-$v"
        if ($c -ne 0) { "FALHA: codigo $c" } else { 'OK' }
    }
}

foreach ($n in $programas.npm) {
    Invoke-Etapa "npm $n" {
        $c = Invoke-ComTempo 'npm' "install -g $n" 15 "npm-$n"
        if ($c -ne 0) { "FALHA: codigo $c" } else { 'OK' }
    }
}

foreach ($n in $programas.pip) {
    Invoke-Etapa "pip $n" {
        $c = Invoke-ComTempo 'python' "-m pip install --user --disable-pip-version-check $n" 15 "pip-$n"
        if ($c -ne 0) { "FALHA: codigo $c" } else { 'OK' }
    }
}

Invoke-Etapa 'Serena para o Codex' {
    $venv = Join-Path $casa '.codex\tools\serena-1.7.0'
    $c = Invoke-ComTempo 'uv' "venv --python 3.13 --allow-existing `"$venv`"" 10 'serena-venv'
    if ($c -ne 0) { return "FALHA: venv codigo $c" }
    $c = Invoke-ComTempo 'uv' "pip install --python `"$venv\Scripts\python.exe`" serena-agent==1.7.0" 15 'serena-pip'
    if ($c -ne 0) { "FALHA: pip codigo $c" } else { 'OK' }
}

Invoke-Etapa 'Git com caminhos longos' {
    & git config --global core.longpaths true
    if ($LASTEXITCODE -ne 0) { "FALHA: codigo $LASTEXITCODE" } else { 'OK' }
}

foreach ($m in $programas.marketplaces) {
    Invoke-Etapa "Marketplace $m" {
        $c = Invoke-ComTempo 'claude' "plugin marketplace add $m" 10 "market-$m"
        if ($c -ne 0) { "FALHA: codigo $c" } else { 'OK' }
    }
}
foreach ($p in $programas.plugins) {
    Invoke-Etapa "Plugin $p" {
        $c = Invoke-ComTempo 'claude' "plugin install $p --scope user" 15 "plugin-$p"
        if ($c -ne 0) { "FALHA: codigo $c" } else { 'OK' }
    }
}

# So liga o proxy no Claude depois de ver o Headroom respondendo.
Invoke-Etapa 'Headroom' {
    $c = Invoke-ComTempo 'uv' 'tool install --python 3.13 --force "headroom-ai[proxy]"' 20 'headroom-install'
    if ($c -ne 0) { return "FALHA: uv tool codigo $c" }
    Update-Path
    $c = Invoke-ComTempo 'headroom' 'init -g claude' 10 'headroom-init'
    if ($c -ne 0) { & (Join-Path $PSScriptRoot 'restaurar-configs.ps1') -Etapa proxy-desligado | Out-Null; return "FALHA: init codigo $c; Claude segue sem proxy" }
    foreach ($i in 1..24) {
        try {
            if ((Invoke-WebRequest 'http://127.0.0.1:8787/readyz' -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) {
                & (Join-Path $PSScriptRoot 'restaurar-configs.ps1') -Etapa proxy-ligado | Out-Null
                return 'OK'
            }
        } catch { Start-Sleep -Seconds 5 }
    }
    & (Join-Path $PSScriptRoot 'restaurar-configs.ps1') -Etapa proxy-desligado | Out-Null
    'FALHA: proxy nao respondeu; Claude segue sem proxy'
}

foreach ($e in $programas.vscode) {
    Invoke-Etapa "VS Code $e" {
        $c = Invoke-ComTempo 'code' "--install-extension $e --force" 10 "vscode-$e"
        if ($c -ne 0) { "FALHA: codigo $c" } else { 'OK' }
    }
}

# Catalogo opcional: so o que foi marcado na interface, na versao mais nova.
$arqCat = Join-Path $script:Dados 'catalogo.txt'
if (Test-Path -LiteralPath $arqCat) {
    $catalogo = @(Get-Content -LiteralPath $arqCat -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    Invoke-Programas @($catalogo | Where-Object { $_ -notmatch '^(npm|uv):' } | ForEach-Object { New-ItemPrograma "Programa $_" ([pscustomobject]@{ id = $_ }) })
    # npm e uv ficam em fila: dois processos mexendo na mesma pasta global se atrapalham.
    foreach ($id in ($catalogo | Where-Object { $_ -match '^(npm|uv):' })) {
        Invoke-Etapa "Programa $id" {
            if ($id.StartsWith('npm:')) { $c = Invoke-ComTempo 'npm' "install -g $($id.Substring(4))" 15 "npm-$id"; if ($c -ne 0) { "FALHA: codigo $c" } else { 'OK' } }
            else { $c = Invoke-ComTempo 'uv' "tool install --python 3.12 --force $($id.Substring(3))" 20 "uv-$id"; if ($c -ne 0) { "FALHA: codigo $c" } else { 'OK' } }
        }
    }
}

# Precisa ser depois de tudo instalado: confere se cada hook aponta para algo que existe.
Invoke-Etapa 'Conferir hooks do Claude' { & (Join-Path $PSScriptRoot 'restaurar-configs.ps1') -Etapa hooks }

Update-Path
Write-Log ''
Write-Log '===== Conferencia final =====' Cyan
# Se algo foi desmarcado de proposito, a falta dele e aviso, nao falha.
$arqPular = Join-Path $script:Dados 'pular.txt'
$semItem = if ((Test-Path -LiteralPath $arqPular) -and @(Get-Content -LiteralPath $arqPular | Where-Object { $_ }).Count) { 'AVISO' } else { 'FALHOU' }
foreach ($c in 'git', 'gh', 'node', 'npm', 'pnpm', 'python', 'uv', 'bun', 'code', 'claude', 'codex', 'rtk', 'codebase-memory-mcp', 'headroom') {
    $g = Get-Command $c -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { Add-Resultado 'OK' "comando $c" $g.Source } else { Add-Resultado $semItem "comando $c" 'nao esta no PATH' }
}
$lista = & claude plugin list 2>&1 | Out-String
foreach ($p in $programas.plugins) {
    if ($lista -notmatch [regex]::Escape($p)) { Add-Resultado $semItem "plugin ativo $p" 'nao aparece em claude plugin list' }
}
foreach ($m in $programas.manual) { Add-Resultado 'MANUAL' $m.nome $m.motivo }

$linhas = Get-Content -LiteralPath $script:Relatorio -Encoding UTF8
$falhas = @($linhas | Where-Object { $_ -like 'FALHOU*' })
Write-Log ''
$linhas | Where-Object { $_ -notlike 'OK*' } | ForEach-Object { Write-Log $_ Yellow }
Write-Log ''
if ($falhas.Count -eq 0) {
    Write-Log 'Tudo instalado e conferido. Reinicie o PC.' Green
} else {
    Write-Log "$($falhas.Count) item(ns) falharam. Rode o upaiva.dev de novo: ele refaz so o que faltou." Yellow
}
Write-Log "Relatorio completo: $script:Relatorio"
if (-not $env:SETUP_GUI) { Read-Host 'Enter para fechar' | Out-Null }
Read-Host 'Enter para fechar' | Out-Null
