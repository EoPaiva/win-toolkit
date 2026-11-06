# Restaura skills e configs do Claude e do Codex a partir de config\configs.tar.
# -Casa permite testar numa pasta temporaria, sem tocar no perfil de verdade.
param([string]$Casa = $env:USERPROFILE, [string]$Etapa = 'tudo')
. "$PSScriptRoot\comum.ps1"

$config = Join-Path $script:Raiz 'config'
$manifesto = (Read-Utf8 (Join-Path $config 'manifesto.json')) | ConvertFrom-Json

function Restore-Arquivos {
    New-Item -ItemType Directory -Force $Casa | Out-Null
    & "$env:windir\System32\tar.exe" -xf (Join-Path $config 'configs.tar') -C $Casa
    if ($LASTEXITCODE -ne 0) { throw "tar terminou com codigo $LASTEXITCODE" }

    # Links do .claude\skills para .agents\skills: FAT32 e tar nao os preservam.
    foreach ($j in $manifesto.junctions) {
        $link = Join-Path $Casa $j.link
        $alvo = Join-Path $Casa $j.alvo
        if (-not (Test-Path -LiteralPath $alvo)) { throw "alvo ausente: $($j.alvo)" }
        if (-not (Test-Path -LiteralPath $link)) { New-Item -ItemType Junction -Path $link -Target $alvo | Out-Null }
    }

    # Os caminhos gravados nas configs apontam para C:\Users\mateu. Se a conta tiver outro nome, ajusta.
    $nome = Split-Path -Leaf $Casa
    if ($nome -ne 'mateu') {
        foreach ($rel in '.claude\settings.json', '.codex\config.toml', '.mcp.json') {
            $f = Join-Path $Casa $rel
            if (Test-Path -LiteralPath $f) {
                $t = Read-Utf8 $f
                $t = $t.Replace('C:/Users/mateu', ($Casa -replace '\\', '/')).Replace('C:\\Users\\mateu', ($Casa -replace '\\', '\\')).Replace('C:\Users\mateu', $Casa).Replace('c:\users\mateu', $Casa)
                Write-Utf8 $f $t
            }
        }
    }

    # O proxy Headroom ainda nao existe aqui. Com essa variavel ligada o Claude Code nao conectaria.
    Set-Proxy $false

    # Servidores MCP ficam no .claude.json, que o proprio Claude tambem escreve.
    $destino = Join-Path $Casa '.claude.json'
    $mcp = (Read-Utf8 (Join-Path $config 'claude-mcp-servers.json')) | ConvertFrom-Json
    if (Test-Path -LiteralPath $destino) { $atual = (Read-Utf8 $destino) | ConvertFrom-Json } else { $atual = New-Object PSObject }
    $atual | Add-Member -NotePropertyName mcpServers -NotePropertyValue $mcp -Force
    Write-Utf8 $destino ($atual | ConvertTo-Json -Depth 64)
    'OK'
}

function Set-Proxy([bool]$Ligado) {
    $f = Join-Path $Casa '.claude\settings.json'
    $s = (Read-Utf8 $f) | ConvertFrom-Json
    if ($Ligado) {
        $s.env | Add-Member -NotePropertyName ANTHROPIC_BASE_URL -NotePropertyValue 'http://127.0.0.1:8787' -Force
    } else {
        $s.env.PSObject.Properties.Remove('ANTHROPIC_BASE_URL')
    }
    Write-Utf8 $f ($s | ConvertTo-Json -Depth 64)
}

function Restore-Binarios {
    $bin = Join-Path $Casa '.local\bin'
    New-Item -ItemType Directory -Force $bin | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:Raiz 'binarios\rtk.exe') -Destination $bin -Force
    $cbm = Join-Path $Casa 'AppData\Local\Programs\codebase-memory-mcp'
    New-Item -ItemType Directory -Force $cbm | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:Raiz 'binarios\codebase-memory-mcp.exe') -Destination $cbm -Force
    'OK'
}

# Comando de hook cujo programa nao existe faz o Claude Code dar erro a cada uso.
# Devolve o caminho do programa que o comando precisa e confere se existe.
function Test-ComandoExiste([string]$Comando) {
    $c = $Comando.Trim()
    # Caminho com variavel so se resolve dentro do Claude: aqui nao da para conferir, e nao pode ser desligado.
    if ($c -match '\$\{|%\w+%|\$env:') { return $true }
    if ($c -match '^"([^"]+)"' -or $c -match "^'([^']+)'" -or $c -match '^(\S+)') { $exe = $Matches[1] } else { return $false }
    $existe = if ($exe -match '[\\/]') { Test-Path -LiteralPath $exe } else { [bool](Get-Command $exe -ErrorAction SilentlyContinue) }
    if (-not $existe) { return $false }
    if ($exe -match '^node(\.exe)?$' -and $c -match '"([^"]+\.(cjs|mjs|js))"') { return (Test-Path -LiteralPath $Matches[1]) }
    return $true
}

function Test-Hooks {
    $f = Join-Path $Casa '.claude\settings.json'
    $s = (Read-Utf8 $f) | ConvertFrom-Json
    $removidos = @()
    foreach ($evento in @($s.hooks.PSObject.Properties)) {
        $grupos = @()
        foreach ($grupo in @($evento.Value)) {
            $bons = @()
            foreach ($h in @($grupo.hooks)) {
                if (Test-ComandoExiste $h.command) { $bons += $h } else { $removidos += "$($evento.Name): $($h.command)" }
            }
            if ($bons.Count) { $grupo.hooks = $bons; $grupos += $grupo }
        }
        if ($grupos.Count) { $evento.Value = $grupos } else { $s.hooks.PSObject.Properties.Remove($evento.Name) }
    }
    if ($s.statusLine -and -not (Test-ComandoExiste $s.statusLine.command)) { $removidos += "statusLine: $($s.statusLine.command)"; $s.PSObject.Properties.Remove('statusLine') }
    if ($s.subagentStatusLine -and -not (Test-ComandoExiste $s.subagentStatusLine.command)) { $removidos += "subagentStatusLine: $($s.subagentStatusLine.command)"; $s.PSObject.Properties.Remove('subagentStatusLine') }

    if ($removidos.Count) {
        Write-Utf8 (Join-Path $script:Dados 'hooks-removidos.txt') ($removidos -join "`r`n")
        Write-Utf8 $f ($s | ConvertTo-Json -Depth 64)
        return "FALHA: $($removidos.Count) hook(s) sem programa foram desligados; veja hooks-removidos.txt"
    }
    Write-Utf8 $f ($s | ConvertTo-Json -Depth 64)
    'OK'
}

switch ($Etapa) {
    'arquivos' { Restore-Arquivos }
    'binarios' { Restore-Binarios }
    'hooks' { Test-Hooks }
    'proxy-ligado' { Set-Proxy $true; 'OK' }
    'proxy-desligado' { Set-Proxy $false; 'OK' }
    'tudo' { Restore-Arquivos; Restore-Binarios; Test-Hooks }
}
