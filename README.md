# win-toolkit

Kit para reinstalar o Windows 11 Pro e deixar um PC pronto: a ISO configurada e o **upaiva.dev**, um app com visual de terminal que instala programas, analisa falhas e otimiza o sistema.

> **Repositório privado de propósito.** `INSTALADOR/config` traz skills e configurações pessoais do Claude e do Codex. Antes de tornar público, tire essa pasta **e o histórico dela**.

## O que o upaiva.dev faz

| Aba | Função |
|---|---|
| **Instalar** | Dependências estilo AIO (Visual C++, .NET, DirectX, XNA, OpenAL, Java, WebView2), programas e skills, mais um catálogo opcional com 102 itens, incluindo apps de IA. Tudo pelo winget, npm ou uv, na versão mais nova |
| **Drivers** | Busca no catálogo oficial do Windows Update, instala o que for marcado com ponto de restauração antes, aponta dispositivos com erro e abre a ferramenta do fabricante. Sem banco de drivers de terceiros |
| **Analisar** | Varredura somente leitura de segurança e saúde: Defender, Firewall, UAC, Secure Boot, TPM, VBS, LSA, SMBv1, RDP, BitLocker, portas, inicialização, discos, travamentos e atualizações. Só corrige o que for marcado |
| **Otimizar** | Níveis Leve, Média, Alta e Altíssima, cumulativos, com plano simulado, backup e reversão |
| **Ferramentas** | Atualizar tudo, limpar disco, reparar sistema, resetar rede, ponto de restauração |
| **Terminal** | Comandos reais, PID, código de saída e tempo, com CPU, RAM e rede medidos |

Nenhum nível de otimização desliga Defender, Firewall, UAC, SmartScreen, Windows Update, TPM ou Secure Boot. Desligar VBS/HVCI é a única opção com ganho medido em testes independentes: fica à parte, desmarcada, com aviso.

A rede de nós ao fundo é decoração. O status, os comandos, os medidores de CPU e RAM e a telemetria são reais.

## Estrutura

```text
app/                         Código do app (C# + WPF, sem dependências além do Windows)
build/compilar.ps1           Gera dist/upaiva.dev.exe com o compilador que já vem no Windows
build/criar-iso.ps1          Gera a ISO configurada a partir da ISO oficial
build/autounattend.xml       Respostas automáticas e limpeza no primeiro login
INSTALADOR/                  Scripts, lista de programas e configs
se-o-rufus-recusar-a-iso/    Arquivos para copiar por cima da ISO oficial, se preciso
ATUALIZAR-CONFIGS.cmd        Atualiza as configs, só no PC de origem
```

## Fora do repositório

| Item | Tamanho | Onde está |
|---|---|---|
| `INSTALADOR/binarios` e `INSTALADOR/pacotes` | 535 MB | No zip anexado à [release](../../releases), porque passam do limite de 100 MB do Git |
| `upaiva.dev.exe` | 72 KB | Na release, ou gerado por `build/compilar.ps1` |
| ISO do Windows | 8,1 GB | Não vai: passa do limite de 2 GB da release e o conteúdo é da Microsoft. Baixe a oficial e rode `build/criar-iso.ps1` |

Logins, tokens, `.env`, conversas, logs e projetos ficam de fora por construção, e o `gerar-snapshot.ps1` interrompe o pacote se encontrar algo com formato de segredo.

## Gerar

```powershell
powershell -ExecutionPolicy Bypass -File build\compilar.ps1
powershell -ExecutionPolicy Bypass -File build\criar-iso.ps1 -IsoOficial C:\caminho\Win11_ptBR_x64.iso -Saida C:\caminho\Windows11-Pro-Mateus.iso
```

Depois, grave a ISO com o Rufus (GPT, UEFI, com **todas as opções de personalização desmarcadas**) e siga `INSTALADOR/LEIA-ME.txt`.

## Situação dos testes

**Testado:** compilação; busca real de drivers; restauração das configs em pasta temporária; marketplaces e plugins do zero; análise real; simulação do nível Altíssima; fluxo da interface com script falso; travas contra rodar no PC de origem; hash e abertura da ISO.

**Ainda não testado em máquina real:** Rufus, boot, instalação do Windows, limpeza no primeiro login, instalação real dos programas, instalar drivers, aplicar e reverter níveis, correções da análise e ferramentas. Fazer antes de confiar: dar boot e parar na tela de escolher o disco, em que nada foi alterado.

O ganho de desempenho dos níveis não foi medido. Em geral, esses ajustes não têm medição independente.
