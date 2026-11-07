# Backup de drivers: guarda o driver que uma atualizacao vai substituir e tenta voltar a ele.
# So define funcoes: quem chama e drivers.ps1, depois de carregar comum.ps1.

# Um erro nestas classes pode impedir o Windows de iniciar: o Voltar nunca mexe nelas.
$script:ClassesCriticas = 'DiskDrive', 'HDC', 'SCSIAdapter', 'System', 'Computer', 'Processor', 'Volume', 'VolumeSnapshot', 'Firmware', 'SecurityDevices'

function Test-ClasseCritica([string]$Classe) { $script:ClassesCriticas -contains $Classe }

function Get-DispositivosPnp {
    $assinados = @{}
    foreach ($s in Get-CimInstance Win32_PnPSignedDriver) { if ($s.DeviceID) { $assinados[$s.DeviceID] = $s } }
    foreach ($e in Get-CimInstance Win32_PnPEntity | Where-Object DeviceID) {
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
