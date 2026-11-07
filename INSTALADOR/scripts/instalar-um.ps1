# Instala um programa em processo proprio, para varios rodarem juntos. Chamado por Invoke-Programas em comum.ps1.
# O nome nao pode ser Dados: comum.ps1 usa $script:Dados, que e a mesma variavel neste escopo.
param([Parameter(Mandatory)][string]$Item64)
. "$PSScriptRoot\comum.ps1"
$item = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Item64)) | ConvertFrom-Json
$script:PrefixoSaida = "[$($item.Pacote.id)] "
Invoke-Etapa $item.Nome { Install-Pacote $item.Pacote }
