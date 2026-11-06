# Cria a ISO configurada a partir da ISO oficial. Confira antes o SHA-256 da oficial na pagina da Microsoft. Windows PowerShell 5.1.
param([Parameter(Mandatory)][string]$IsoOficial, [Parameter(Mandatory)][string]$Saida, [string]$Trabalho = "$env:TEMP\win-toolkit-iso")
$sp = $PSScriptRoot
$Kit = Split-Path -Parent $sp
$Arvore = $Trabalho
$sete = 'C:\Program Files\7-Zip\7z.exe'

$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $Arvore) { & cmd.exe /c rmdir /s /q "$Arvore" }
& $sete x $IsoOficial "-o$Arvore" -y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "7-Zip terminou com codigo $LASTEXITCODE" }
"arvore extraida: " + @(Get-ChildItem -LiteralPath $Arvore -Recurse -File -Force).Count + (" arquivos {0:HH:mm:ss}" -f (Get-Date))

# Respostas automaticas e limpeza no primeiro login. $OEM$\$1 vai para C:\ durante a instalacao.
[xml]$x = Get-Content -LiteralPath "$sp\autounattend.xml" -Raw
Copy-Item -LiteralPath "$sp\autounattend.xml" -Destination "$Arvore\autounattend.xml" -Force
$oem = Join-Path $Arvore 'sources\$OEM$\$1\SetupMateus\scripts'
[void][IO.Directory]::CreateDirectory($oem)
foreach ($s in 'comum.ps1', 'limpeza.ps1', 'reverter-limpeza.ps1') { Copy-Item -LiteralPath "$Kit\INSTALADOR\scripts\$s" -Destination $oem -Force }
"adicionados: autounattend.xml e " + @(Get-ChildItem -LiteralPath $oem).Count + ' scripts'

$cs = @'
using System;
using System.IO;
using System.Runtime.InteropServices.ComTypes;
public static class EscritorIso {
    public static void Gravar(string caminho, object objeto, int bloco, long total) {
        IStream s = (IStream)objeto;
        byte[] buf = new byte[bloco * 512];
        using (FileStream f = new FileStream(caminho, FileMode.Create, FileAccess.Write)) {
            long restante = total * bloco;
            IntPtr lidos = System.Runtime.InteropServices.Marshal.AllocHGlobal(4);
            try {
                while (restante > 0) {
                    int pedir = (int)Math.Min(restante, buf.Length);
                    s.Read(buf, pedir, lidos);
                    int n = System.Runtime.InteropServices.Marshal.ReadInt32(lidos);
                    if (n == 0) throw new IOException("stream terminou antes do fim");
                    f.Write(buf, 0, n);
                    restante -= n;
                }
            } finally { System.Runtime.InteropServices.Marshal.FreeHGlobal(lidos); }
        }
    }
}
'@
Add-Type -TypeDefinition $cs

function Nova-Opcao([string]$arquivo, [int]$plataforma) {
    $st = New-Object -ComObject ADODB.Stream
    $st.Type = 1; $st.Open(); $st.LoadFromFile($arquivo)
    $o = New-Object -ComObject IMAPI2FS.BootOptions
    $o.Manufacturer = 'Microsoft'; $o.PlatformId = $plataforma
    $o.AssignBootImage($st.psobject.BaseObject)
    # AssignBootImage redefine a emulacao pelo tamanho do arquivo: precisa vir depois.
    $o.Emulation = 0
    return $o
}

$img = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$img.ChooseImageDefaultsForMediaType(19)   # BD-R: comporta mais de 8,5 GB
$img.FileSystemsToCreate = 4               # UDF, como a ISO da Microsoft: aceita arquivo acima de 4 GB
$img.UDFRevision = 0x102
$img.VolumeName = 'WIN11PRO'
$img.FreeMediaBlocks = 16000000
$bios = Nova-Opcao "$Arvore\boot\etfsboot.com" 0
$uefi = Nova-Opcao "$Arvore\efi\microsoft\boot\efisys.bin" 0xEF
try {
    [void][System.__ComObject].InvokeMember('BootImageOptionsArray', [Reflection.BindingFlags]::SetProperty, $null, $img, @(, [object[]]@($bios, $uefi)))
    'entradas de boot: BIOS e UEFI'
} catch {
    "duas entradas recusadas ($($_.Exception.InnerException.Message)); usando so UEFI"
    $img.BootImageOptions = $uefi
}
"adicionando arvore {0:HH:mm:ss}" -f (Get-Date)
$img.Root.AddTree($Arvore, $false)
"gerando imagem {0:HH:mm:ss}" -f (Get-Date)
$res = $img.CreateResultImage()
[EscritorIso]::Gravar($Saida, $res.ImageStream, $res.BlockSize, $res.TotalBlocks)
"ISO criada: {0:N2} GB  {1:HH:mm:ss}" -f ((Get-Item -LiteralPath $Saida).Length / 1GB), (Get-Date)

"--- conferencia pelo 7-Zip"
$lista = & $sete l -slt $Saida
$arq = @{}; $p = $null; $t = $null; $pasta = $false
foreach ($l in $lista) {
    if ($l -match '^Path = (.+)$') { $p = $Matches[1]; $t = $null; $pasta = $false }
    elseif ($l -match '^Size = (\d+)$') { $t = [long]$Matches[1] }
    elseif ($l -match '^Folder = \+$') { $pasta = $true }
    elseif ($l -eq '' -and $p -and $null -ne $t) { if (-not $pasta -and $p -ne $Saida) { $arq[$p] = $t }; $p = $null }
}
$ruins = 0; $n = 0
Get-ChildItem -LiteralPath $Arvore -Recurse -File -Force | ForEach-Object {
    $n++
    $rel = $_.FullName.Substring($Arvore.Length + 1)
    if (-not $arq.ContainsKey($rel) -or $arq[$rel] -ne $_.Length) { $ruins++; if ($ruins -le 8) { "RUIM $rel" } }
}
"na arvore=$n  na ISO=$($arq.Count)  faltando_ou_diferentes=$ruins"
"entradas de boot: " + (($arq.Keys | Where-Object { $_ -like '`[BOOT`]*' }) -join ', ')

"--- conteudo real comparado por hash (extraido da ISO nova)"
$check = "$sp\check"
& $sete x $Saida "-o$check" 'autounattend.xml' 'sources\install.wim' 'sources\boot.wim' 'efi\boot\bootx64.efi' 'sources\$OEM$\$1\SetupMateus\scripts\limpeza.ps1' -y | Out-Null
foreach ($f in 'autounattend.xml', 'sources\install.wim', 'sources\boot.wim', 'efi\boot\bootx64.efi', 'sources\$OEM$\$1\SetupMateus\scripts\limpeza.ps1') {
    '{0,-52} {1}' -f $f, ((Get-FileHash -LiteralPath "$check\$f").Hash -eq (Get-FileHash -LiteralPath "$Arvore\$f").Hash)
}
& cmd.exe /c rmdir /s /q "$check"
"sha256 ISO nova: " + (Get-FileHash -LiteralPath $Saida).Hash
"FIM {0:HH:mm:ss}" -f (Get-Date)
