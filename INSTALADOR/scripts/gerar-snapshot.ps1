# Empacota skills e configs desta maquina em config\configs.tar. Nunca leva projetos, memorias de projeto, login, token, .env nem transcricoes.
param([string]$Saida, [string]$Trabalho = (Join-Path $env:TEMP 'snap-setup'))
if (-not $Saida) { $Saida = Join-Path (Split-Path -Parent $PSScriptRoot) 'config' }
if ($env:COMPUTERNAME -ne 'MARINETE') { throw 'As configs so podem ser geradas no PC de origem. Nada foi alterado.' }
$h = $env:USERPROFILE
if (Test-Path -LiteralPath $Trabalho) { Remove-Item -LiteralPath $Trabalho -Recurse -Force }
New-Item -ItemType Directory -Force $Trabalho, $Saida | Out-Null

$ExcluirArquivos = '.credentials.json', 'auth.json', '.env', '.env.*', '*.pem', '*.key', 'id_rsa*', 'id_ed25519*', '*.sqlite*', '*.db', '*.db-*', '*.log', '*.bak', '*.bak-*', 'settings.json.before-*', '*.tmp', '*.tmp.*', '*.jsonl', '*.dmp', '*.pid', '*.lock', 'history*', 'last-status.txt', 'runner.*', 'checkpoints.*'
$ExcluirPastas = 'node_modules', '__pycache__', '.git', 'cache', 'logs', '.sandbox-secrets', 'synced', 'observation-log', 'state', 'sessions', 'session-data', 'session-env', 'telemetry', 'tmp', 'temp', 'backups', 'file-history', 'shell-snapshots', 'uploads', 'downloads', 'crash*', 'dumps'

function Copy-Pasta([string]$Rel) {
    $o = Join-Path $h $Rel
    if (-not (Test-Path -LiteralPath $o)) { return }
    & robocopy.exe $o (Join-Path $Trabalho $Rel) /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XF @ExcluirArquivos /XD @ExcluirPastas | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy falhou em $Rel (codigo $LASTEXITCODE)" }
}

function Copy-Arquivo([string]$Rel) {
    $o = Join-Path $h $Rel
    if (-not (Test-Path -LiteralPath $o)) { return }
    $d = Join-Path $Trabalho $Rel
    New-Item -ItemType Directory -Force (Split-Path -Parent $d) | Out-Null
    Copy-Item -LiteralPath $o -Destination $d -Force
}

foreach ($p in '.claude\agents', '.claude\hooks', '.claude\helpers', '.claude\rules', '.claude\skills', '.claude\skill-observations', '.claude\skill-updates',
    '.agents', '.orca\agent-hooks',
    '.codex\agents', '.codex\rules', '.codex\skills', '.codex\harness', '.codex\vendor_imports') { Copy-Pasta $p }
foreach ($a in '.claude\CLAUDE.md', '.claude\RTK.md', '.claude\settings.json', '.codex\AGENTS.md', '.codex\config.toml', '.gitconfig', '.mcp.json') { Copy-Arquivo $a }

$junctions = @(Get-ChildItem -LiteralPath (Join-Path $h '.claude\skills') -Force | Where-Object LinkType | ForEach-Object {
    [pscustomobject]@{ link = ".claude\skills\$($_.Name)"; alvo = ".agents\skills\$($_.Name)" }
})

# Pacote de reinstalacao dos servidores MCP: nomes e comandos, sem o resto do .claude.json (conta e historico).
$claude = Get-Content -LiteralPath (Join-Path $h '.claude.json') -Raw | ConvertFrom-Json -AsHashtable
[IO.File]::WriteAllText((Join-Path $Saida 'claude-mcp-servers.json'), ($claude.mcpServers | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding($false)))

# Varredura de segredos no que vai viajar. Qualquer achado interrompe o empacotamento.
$padrao = '(sk-ant-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{16,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|postgres(ql)?(\+\w+)?://[^:\s/$]+:[^@\s$]{6,}@)'
$achados = @(Get-ChildItem -LiteralPath $Trabalho -Recurse -File -Force | Where-Object { $_.Length -lt 5MB } | ForEach-Object {
    $m = Select-String -LiteralPath $_.FullName -Pattern $padrao -List -ErrorAction SilentlyContinue
    if ($m) { [pscustomobject]@{ arquivo = $_.FullName.Substring($Trabalho.Length + 1); linha = $m.LineNumber; tipo = ($m.Matches[0].Value.Substring(0, [Math]::Min(6, $m.Matches[0].Value.Length))) } }
})
if ($achados.Count) {
    $achados | ForEach-Object { Write-Host "SEGREDO? $($_.arquivo):$($_.linha) [$($_.tipo)...]" -ForegroundColor Red }
    throw "Varredura encontrou $($achados.Count) arquivo(s) suspeito(s). Pacote NAO gerado."
}

$tar = Join-Path $Saida 'configs.tar'
& "$env:windir\System32\tar.exe" -cf $tar -C $Trabalho .
if ($LASTEXITCODE -ne 0) { throw "tar terminou com codigo $LASTEXITCODE" }
$arquivos = Get-ChildItem -LiteralPath $Trabalho -Recurse -File -Force
$manifesto = [ordered]@{ gerado = (Get-Date).ToString('s'); arquivos = $arquivos.Count; bytes = ($arquivos | Measure-Object Length -Sum).Sum; sha256 = (Get-FileHash -LiteralPath $tar).Hash; junctions = $junctions }
[IO.File]::WriteAllText((Join-Path $Saida 'manifesto.json'), ($manifesto | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $Trabalho -Recurse -Force
Write-Host ("Snapshot: {0} arquivos, {1:N1} MB, {2} junctions, 0 segredos encontrados." -f $arquivos.Count, ((Get-Item -LiteralPath $tar).Length / 1MB), $junctions.Count) -ForegroundColor Green
