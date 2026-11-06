# Varredura de falhas: SOMENTE LEITURA. Nao corrige nada; corrigir.ps1 age so no que o usuario marcar.
param([switch]$Profundo)
. "$PSScriptRoot\comum.ps1"
$admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$achados = New-Object System.Collections.ArrayList
$total = 26; if ($Profundo) { $total++ }
Write-Log "@total $total"
Write-Log "scanner.start host=$env:COMPUTERNAME user=$env:USERNAME elevated=$admin deep=$Profundo mode=read-only" Cyan

function Achado($id, $sev, $titulo, $det, $fix = $false) {
    [void]$achados.Add([pscustomobject]@{ id = $id; sev = $sev; titulo = $titulo; det = "$det"; fix = [bool]$fix })
    Write-Log "  | finding sev=$sev id=$id :: $det"
}
function Sonda([string]$nome, [scriptblock]$acao) {
    Write-Log "[....] probe $nome"
    try { & $acao } catch { Write-Log "  | $($_.Exception.Message)"; Achado "erro-$nome" 'INFO' "Não foi possível ler: $nome" $_.Exception.Message.Substring(0, [Math]::Min(110, $_.Exception.Message.Length)) }
    Write-Log "[ ok ] probe $nome"
}
function Reg($c, $n) { try { (Get-ItemProperty -Path $c -Name $n -ErrorAction Stop).$n } catch { $null } }

Sonda 'Get-MpComputerStatus' {
    $m = Get-MpComputerStatus -ErrorAction Stop
    if (-not $m.RealTimeProtectionEnabled) { Achado 'defender-rtp' 'CRITICO' 'Antivirus em tempo real desligado' 'RealTimeProtectionEnabled=False' $true }
    elseif ($m.AntivirusSignatureAge -gt 7) { Achado 'defender-sig' 'ALTO' 'Assinaturas do Defender desatualizadas' "AntivirusSignatureAge=$($m.AntivirusSignatureAge)d" }
    else { Achado 'defender-ok' 'OK' 'Defender ativo' "RTP=True sigAge=$($m.AntivirusSignatureAge)d" }
}
Sonda 'Get-NetFirewallProfile' {
    $off = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled })
    if ($off.Count) { Achado 'firewall' 'CRITICO' 'Firewall desligado' "profiles.off=$($off.Name -join ',')" $true } else { Achado 'firewall-ok' 'OK' 'Firewall ativo' 'Domain,Private,Public=Enabled' }
}
Sonda 'HKLM\..\Policies\System\EnableLUA' {
    if ((Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA') -eq 0) { Achado 'uac' 'CRITICO' 'UAC desligado' 'EnableLUA=0' $true } else { Achado 'uac-ok' 'OK' 'UAC ativo' 'EnableLUA=1' }
}
Sonda 'Confirm-SecureBootUEFI' {
    if (Confirm-SecureBootUEFI -ErrorAction Stop) { Achado 'secureboot-ok' 'OK' 'Secure Boot ligado' 'UEFI SecureBoot=True' } else { Achado 'secureboot' 'ALTO' 'Secure Boot desligado' 'ligue na BIOS; a Riot exige para o Vanguard' }
}
Sonda 'Get-Tpm' {
    $t = Get-Tpm -ErrorAction Stop
    if ($null -eq $t.TpmPresent) { throw 'requer elevação' }
    if ($t.TpmReady) { Achado 'tpm-ok' 'OK' 'TPM pronto' "TpmPresent=$($t.TpmPresent) TpmReady=True" } else { Achado 'tpm' 'ALTO' 'TPM não está pronto' "TpmPresent=$($t.TpmPresent) TpmReady=False" }
}
Sonda 'Win32_DeviceGuard (VBS/HVCI)' {
    $g = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
    $hvci = @($g.SecurityServicesRunning) -contains 2
    if ($hvci) { Achado 'hvci-ok' 'OK' 'Integridade de Memória ativa' "VBS=$($g.VirtualizationBasedSecurityStatus) HVCI=running" } else { Achado 'hvci' 'MEDIO' 'Integridade de Memória desligada' "VBS=$($g.VirtualizationBasedSecurityStatus) HVCI=off (mais FPS, menos proteção)" }
}
Sonda 'HKLM\..\Lsa\RunAsPPL' {
    if ((Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL') -in 1, 2) { Achado 'lsa-ok' 'OK' 'Proteção LSA ativa' 'RunAsPPL>=1' } else { Achado 'lsa' 'MEDIO' 'Proteção LSA desligada' 'RunAsPPL=0; credenciais em memória menos protegidas' $true }
}
Sonda 'Get-SmbServerConfiguration (SMBv1)' {
    if ((Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol) { Achado 'smb1' 'ALTO' 'SMBv1 ligado' 'protocolo obsoleto; vetor do WannaCry' $true } else { Achado 'smb1-ok' 'OK' 'SMBv1 desligado' 'EnableSMB1Protocol=False' }
}
Sonda 'HKLM\..\Terminal Server (RDP/NLA)' {
    $off = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections'
    $nla = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication'
    if ($off -eq 0 -and $nla -ne 1) { Achado 'rdp-nla' 'ALTO' 'Area de Trabalho Remota sem NLA' 'fDenyTSConnections=0 UserAuthentication=0' $true }
    elseif ($off -eq 0) { Achado 'rdp' 'MEDIO' 'Area de Trabalho Remota ligada' 'fDenyTSConnections=0 NLA=1' } else { Achado 'rdp-ok' 'OK' 'Area de Trabalho Remota desligada' 'fDenyTSConnections=1' }
}
Sonda 'Get-BitLockerVolume C:' {
    $b = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
    if ($b.ProtectionStatus -eq 'On') { Achado 'bitlocker-ok' 'OK' 'Disco criptografado' "VolumeStatus=$($b.VolumeStatus)" } else { Achado 'bitlocker' 'MEDIO' 'Disco C: sem criptografia' "ProtectionStatus=$($b.ProtectionStatus); ative em Configurações se o PC for portatil" }
}
Sonda 'Get-LocalUser Guest/Convidado' {
    $c = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID -like '*-501' -and $_.Enabled })
    if ($c.Count) { Achado 'guest' 'ALTO' 'Conta Convidado ativa' "user=$($c[0].Name)" $true } else { Achado 'guest-ok' 'OK' 'Conta Convidado desligada' 'SID *-501 Enabled=False' }
}
Sonda 'Win32_UserAccount PasswordRequired' {
    $s = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled -and -not $_.PasswordRequired -and $null -eq $_.PasswordLastSet })
    if ($s.Count) { Achado 'senha' 'ALTO' 'Conta sem senha' "users=$($s.Name -join ',')" }
}
Sonda 'HKLM\..\Explorer\NoDriveTypeAutoRun' {
    if ((Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun') -ne 255) { Achado 'autorun' 'MEDIO' 'AutoRun não bloqueado em mídias removíveis' 'NoDriveTypeAutoRun!=0xFF' $true } else { Achado 'autorun-ok' 'OK' 'AutoRun bloqueado' 'NoDriveTypeAutoRun=0xFF' }
}
Sonda 'Get-WindowsOptionalFeature MicrosoftWindowsPowerShellV2' {
    if ((Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2 -ErrorAction Stop).State -eq 'Enabled') { Achado 'ps2' 'MEDIO' 'PowerShell 2.0 habilitado' 'versão sem os registros de segurança atuais' $true }
}
Sonda 'Get-NetTCPConnection -State Listen' {
    $l = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalAddress -in '0.0.0.0', '::' -and $_.LocalPort -lt 49152 })
    $d = ($l | Select-Object -First 12 | ForEach-Object { "$($_.LocalPort)/$((Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName)" }) -join ' '
    Achado 'portas' 'INFO' "$($l.Count) portas abertas para a rede" $d
}
Sonda 'Run keys + Get-AuthenticodeSignature' {
    $sem = New-Object System.Collections.ArrayList; $n = 0
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
        $i = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if (-not $i) { continue }
        foreach ($p in $i.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
            $n++
            $v = "$($p.Value)".Trim()
            $exe = if ($v -match '^"([^"]+)"') { $Matches[1] } else { ($v -split '\s+')[0] }
            if ((Test-Path -LiteralPath $exe -ErrorAction SilentlyContinue) -and (Get-AuthenticodeSignature -LiteralPath $exe).Status -ne 'Valid') { [void]$sem.Add($p.Name) }
        }
    }
    if ($sem.Count) { Achado 'startup-assinatura' 'MEDIO' "$($sem.Count) programas de inicialização sem assinatura válida" ($sem -join ', ') }
    if ($n -gt 12) { Achado 'startup' 'MEDIO' "$n programas iniciam com o Windows" 'reduza no Gerenciador de Tarefas' } else { Achado 'startup-ok' 'OK' "$n programas iniciam com o Windows" 'Run keys' }
}
Sonda 'Get-PhysicalDisk + Get-StorageReliabilityCounter' {
    foreach ($d in Get-PhysicalDisk -ErrorAction Stop) {
        if ($d.HealthStatus -ne 'Healthy') { Achado "disco-$($d.DeviceId)" 'CRITICO' "Disco com problema: $($d.FriendlyName)" "HealthStatus=$($d.HealthStatus)" }
        else {
            $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            $w = if ($r -and $null -ne $r.Wear) { " wear=$($r.Wear)%" } else { '' }
            $temp = if ($r -and $r.Temperature) { " temp=$($r.Temperature)C" } else { '' }
            Achado "disco-ok-$($d.DeviceId)" 'OK' "Disco saudavel: $($d.FriendlyName)" "$($d.MediaType)$w$temp"
        }
    }
}
Sonda 'Get-Volume free space' {
    foreach ($v in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }) {
        $p = [Math]::Round(100 * $v.SizeRemaining / $v.Size)
        if ($p -lt 10) { Achado "espaco-$($v.DriveLetter)" 'ALTO' "Pouco espaço em $($v.DriveLetter):" "free=$p% ($([Math]::Round($v.SizeRemaining / 1GB)) GB)" }
        elseif ($p -lt 20) { Achado "espaco-$($v.DriveLetter)" 'MEDIO' "Espaço baixo em $($v.DriveLetter):" "free=$p% ($([Math]::Round($v.SizeRemaining / 1GB)) GB)" }
        else { Achado "espaco-ok-$($v.DriveLetter)" 'OK' "Espaço livre em $($v.DriveLetter):" "free=$p%" }
    }
}
Sonda 'Win32_OperatingSystem memory/uptime' {
    $o = Get-CimInstance Win32_OperatingSystem
    $up = [Math]::Round(((Get-Date) - $o.LastBootUpTime).TotalDays, 1)
    if ($up -gt 14) { Achado 'uptime' 'MEDIO' 'PC sem reiniciar ha muito tempo' "uptime=${up}d" }
    $u = [Math]::Round(100 * (1 - $o.FreePhysicalMemory / $o.TotalVisibleMemorySize))
    if ($u -gt 90) { Achado 'ram' 'MEDIO' 'Memoria quase cheia agora' "ram.used=$u%" } else { Achado 'ram-ok' 'OK' 'Memoria sob controle' "ram.used=$u%" }
}
Sonda 'Get-PnpDevice problem codes' {
    $p = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.Status -in 'Error', 'Degraded' })
    if ($p.Count) { Achado 'drivers' 'ALTO' "$($p.Count) dispositivos com erro de driver" (($p | Select-Object -First 5 -ExpandProperty FriendlyName) -join ', ') } else { Achado 'drivers-ok' 'OK' 'Dispositivos sem erro' 'Status!=Error' }
}
Sonda 'Get-WinEvent System 41/1001/WHEA 30d' {
    $d = (Get-Date).AddDays(-30)
    $k = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $d } -ErrorAction SilentlyContinue).Count
    $b = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $d } -ErrorAction SilentlyContinue).Count
    $w = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $d } -ErrorAction SilentlyContinue).Count
    $det = "KernelPower41=$k BugCheck1001=$b WHEA=$w window=30d"
    if ($b -gt 0 -or $w -gt 0) { Achado 'crashes' 'ALTO' 'Telas azuis ou erros de hardware recentes' $det } elseif ($k -gt 0) { Achado 'crashes' 'MEDIO' 'Desligamentos inesperados recentes' $det } else { Achado 'crashes-ok' 'OK' 'Sem travamentos graves em 30 dias' $det }
}
Sonda 'Win32_QuickFixEngineering + WU reboot flag' {
    $u = Get-CimInstance Win32_QuickFixEngineering -ErrorAction Stop | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
    $dias = if ($u) { ((Get-Date) - $u.InstalledOn).Days } else { 999 }
    if ($dias -gt 45) { Achado 'updates' 'ALTO' 'Windows sem atualizar há muito tempo' "lastHotfix=$($u.HotFixID) age=${dias}d" } else { Achado 'updates-ok' 'OK' 'Windows atualizado recentemente' "lastHotfix=$($u.HotFixID) age=${dias}d" }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { Achado 'reinicio' 'MEDIO' 'Reinício pendente do Windows Update' 'RebootRequired key present' }
}
Sonda 'winget upgrade' {
    $s = & winget.exe upgrade --accept-source-agreements --disable-interactivity 2>&1
    $i = [array]::FindIndex([string[]]$s, [Predicate[string]] { param($x) $x -match '^-{10,}' })
    $n = if ($i -ge 0) { @($s[($i + 1)..($s.Count - 1)] | Where-Object { $_ -match '\S+\s+\S+\s+\S+\s+\S+' -and $_ -match '\d+\.\d+' }).Count } else { 0 }
    if ($n -gt 0) { Achado 'apps' 'MEDIO' "$n programas com atualização disponível" 'use FERRAMENTAS > Atualizar tudo' } else { Achado 'apps-ok' 'OK' 'Programas atualizados' 'winget upgrade=0' }
}
Sonda 'DISM /Online /Cleanup-Image /CheckHealth' {
    if (-not $admin) { throw 'requer elevação' }
    $s = & dism.exe /English /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
    if ($s -match 'No component store corruption') { Achado 'dism-ok' 'OK' 'Componentes do Windows íntegros' 'CheckHealth=clean' } else { Achado 'dism' 'ALTO' 'Componentes do Windows com sinal de corrupção' 'use FERRAMENTAS > Reparar sistema' }
}
if ($Profundo) {
    Sonda 'sfc /verifyonly' {
        if (-not $admin) { throw 'requer elevação' }
        & sfc.exe /verifyonly | Out-Null
        if ($LASTEXITCODE -ne 0) { Achado 'sfc' 'ALTO' 'Arquivos de sistema com violação de integridade' "sfc exit=$LASTEXITCODE" } else { Achado 'sfc-ok' 'OK' 'Arquivos de sistema íntegros' 'sfc exit=0' }
    }
}
$ordem = @{ CRITICO = 0; ALTO = 1; MEDIO = 2; INFO = 3; OK = 4 }
$lista = @($achados | Sort-Object { $ordem[$_.sev] })
Write-Utf8 (Join-Path $script:Dados 'analise.json') (ConvertTo-Json -InputObject $lista -Depth 3)
Write-Log "scanner.done findings=$($lista.Count) critical=$(@($lista | Where-Object sev -eq 'CRITICO').Count) high=$(@($lista | Where-Object sev -eq 'ALTO').Count) medium=$(@($lista | Where-Object sev -eq 'MEDIO').Count)" Green
