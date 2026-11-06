<div align="center">

# upaiva.dev

### Do Windows recém-formatado ao PC pronto para trabalhar.
**Programas, dependências, drivers, segurança e otimização em um único app, com cada comando à vista.**

![Windows 11](https://img.shields.io/badge/Windows-11-000000?style=flat-square)
![.NET Framework](https://img.shields.io/badge/.NET_Framework-4.8-000000?style=flat-square)
![WPF](https://img.shields.io/badge/UI-WPF-000000?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-000000?style=flat-square)
![Tamanho](https://img.shields.io/badge/.exe-106_KB-000000?style=flat-square)
![Dependências](https://img.shields.io/badge/runtime_extra-nenhum-000000?style=flat-square)

[Baixar](../../releases/latest) · [Recursos](#recursos) · [Stack](#stack) · [Compilar](#compilar) · [Status](#status)

<img src="docs/instalar.png" alt="Tela Instalar do upaiva.dev, com a lista de programas e o planeta de partículas" width="900">

</div>

## Formatar não precisa custar o dia inteiro

Depois de formatar, começa a parte chata: baixar dezenas de instaladores, lembrar de cada runtime, caçar drivers, refazer configurações e torcer para o jogo não reclamar de uma DLL. Os otimizadores prometem milagres e escondem o que fazem.

O **upaiva.dev** troca isso por uma tela. Você escolhe o que entra, acompanha o comando real de cada etapa e sai com um relatório do que funcionou e do que não funcionou.

| | |
|---|---|
| **Tudo em um lugar** | Dependências, programas, skills, drivers, análise de segurança, otimização e manutenção |
| **Sempre a versão mais nova** | Instala por winget, npm e uv na hora, em vez de guardar instaladores velhos |
| **Nada escondido** | Comando, PID, código de saída e tempo de cada etapa aparecem no terminal embutido |
| **Retoma de onde parou** | Rodou de novo? Só refaz o que faltou. Cancelou? O que foi interrompido não conta como feito |
| **Reversível** | Ponto de restauração, plano simulado e backup do estado anterior antes de otimizar |
| **Leve de verdade** | Um `.exe` de 106 KB, sem runtime extra: usa o .NET e o PowerShell que já vêm no Windows 11 |

## Recursos

### Instalar
**23 dependências estilo AIO** (Visual C++ de 2005 em diante, .NET, DirectX, XNA, OpenAL, Java, WebView2), programas essenciais e um **catálogo opcional com 102 itens**, incluindo assistentes de IA, modelos locais, editores com agentes, DevOps, criação e jogos.

- **Busca instantânea** por nome ou categoria
- **Perfis prontos:** Completo, Básico, Gamer, Dev e IA, além de salvar e carregar a sua seleção
- **Fila visível** com o estado e o tempo de cada item
- **Progresso ponderado:** um pacote pesado conta mais que um utilitário pequeno
- **Cancelar a qualquer momento**, encerrando também os processos filhos

### Drivers
Busca no **catálogo oficial do Windows Update**, aponta dispositivos com erro e drivers antigos, cria um ponto de restauração e instala só o que você marcar. Para placas de vídeo, leva direto ao fabricante. Sem banco de drivers de terceiros.

### Analisar
Varredura **somente leitura** de segurança e saúde: Defender, Firewall, UAC, Secure Boot, TPM, VBS, proteção LSA, SMBv1, RDP, BitLocker, portas abertas, programas de inicialização, discos, travamentos e atualizações. Nada muda sem você marcar.

### Otimizar

<img src="docs/otimizar.png" alt="Tela Otimizar com os quatro níveis" width="900">

| Nível | Para quem | Custo |
|---|---|---|
| **Leve** | Qualquer PC: tira anúncios, sugestões e apps instalados sozinhos | Nenhuma função perdida |
| **Média** | Remove 21 apps, Recall e DiagTrack, e liga HAGS e Alto Desempenho | Mais consumo de bateria |
| **Alta** | Desliga SysMain, Windows Search, Xbox Live e Spooler | Sem impressora e sem busca indexada |
| **Altíssima** | Mais 13 serviços e apps em segundo plano bloqueados | Sem notificações e localização. Para PC na tomada |

Os níveis são cumulativos, somam mais de 90 ações no topo e podem ser **simulados antes de aplicar**.

### Ferramentas
Atualizar todos os programas, limpar disco, reparar o sistema com DISM e SFC, resetar a rede, criar ponto de restauração e **reinstalar pela Microsoft Store os apps removidos**.

### Terminal e Ctrl K

<img src="docs/terminal.png" alt="Terminal embutido durante uma instalação, com dados de demonstração" width="900">

<sub>Tela com dados de demonstração.</sub>

A saída real de cada processo, com a órbita do planeta acendendo na proporção do progresso. E, como no [site](https://upaiva.dev), **`Ctrl K`** abre um terminal que encontra programas, perfis e seções sem tirar as mãos do teclado.

<img src="docs/paleta.png" alt="Paleta de comandos aberta com Ctrl K" width="900">

## O que ele se recusa a fazer

Confiança vale mais que um número bonito na tela.

- **Nenhum nível desliga** Defender, Firewall, UAC, SmartScreen, Windows Update, TPM ou Secure Boot.
- **Não promete FPS.** Desligar VBS/HVCI é o único ajuste com ganho medido por testes independentes, e por isso fica à parte, desmarcado e com aviso.
- **Não usa banco de drivers de terceiros** nem Windows modificado.
- **Não leva logins nem histórico.** Tokens, `.env`, conversas, logs e projetos ficam fora do pacote, e o gerador de configurações para se encontrar algo com formato de segredo.
- **Decoração não finge ser status.** Comandos e telemetria de CPU, RAM e rede são reais, e a órbita só acende com progresso real.

## Stack

| Camada | Tecnologia | Por quê |
|---|---|---|
| Interface | WPF, XAML | Nativo, com renderização por hardware e sem navegador embutido |
| Linguagem | C# 5 | Compila com o `csc.exe` que já vem no Windows, sem SDK |
| Runtime | .NET Framework 4.8 | Já presente no Windows 11 |
| Motor | PowerShell 5.1 | O único shell garantido em um Windows recém-instalado |
| Pacotes | winget, npm, uv, Microsoft Store | Sempre a versão publicada mais recente |
| Drivers | Windows Update Agent (COM) | Fonte oficial da Microsoft |
| Tipografia | Inter, Inter Display, Cascadia Mono | A identidade do [upaiva.dev](https://upaiva.dev) |
| Gráficos | `DrawingContext` | Planeta de partículas e letter-spacing próprios, sem bibliotecas |

```mermaid
flowchart LR
    UI["upaiva.dev.exe<br/>WPF"] -- "inicia, com elevação quando precisa" --> PS["Scripts PowerShell"]
    PS -- "winget, npm, uv, DISM, Windows Update" --> SO["Windows"]
    PS -- "grava etapas, comandos e saída" --> LOG["instalador.log"]
    LOG -- "lido em tempo real" --> UI
    UI -- "cancelar.flag" --> PS
```

A interface não executa nada sozinha: ela inicia os scripts e acompanha o log. Assim, um erro de tela não derruba uma instalação em andamento, e o pedido de cancelamento alcança também os processos elevados, por meio de um arquivo que os dois lados enxergam.

## Como usar

1. Baixe o pacote da [última release](../../releases/latest) e extraia.
2. Abra `INSTALADOR\upaiva.dev.exe` com dois cliques, **sem** "Executar como administrador". O Windows pede permissão na hora certa.
3. O app não tem assinatura digital. Se o Windows avisar, use **Mais informações > Executar assim mesmo**.

O app precisa da pasta ao lado dele: `scripts`, `fonts`, `config`, `binarios` e `pacotes`.

## Compilar

Não precisa instalar SDK nenhum:

```powershell
powershell -ExecutionPolicy Bypass -File build\compilar.ps1
copy dist\upaiva.dev.exe INSTALADOR\
```

```text
app/            Interface: ui.xaml e app.cs
build/          compilar.ps1
docs/           Capturas de tela
INSTALADOR/     O que o .exe usa em execução
  scripts/      Instalar, drivers, analisar, otimizar, ferramentas, restaurar configs
  config/       Snapshot de skills e configurações do Claude e do Codex
  fonts/        Inter (licença OFL)
  binarios/     Binários grandes, só na release
  pacotes/      Bundle offline do winget, só na release
```

## Status

| | |
|---|---|
| **Testado de ponta a ponta** | Compilação, análise real, busca real de drivers, simulação da Altíssima, restauração das configs em pasta temporária, travas contra rodar no PC de origem e todo o fluxo da interface, incluindo o cancelamento, com instalador de teste |
| **Falta testar em máquina real** | Instalação real dos programas, instalação de drivers, aplicar e reverter níveis, correções da análise, ferramentas, reinstalação de apps e cancelamento em processo elevado |

O ganho de desempenho dos níveis não foi medido.

> **Repositório privado de propósito.** `INSTALADOR/config` traz skills e configurações pessoais. Antes de torná-lo público, remova essa pasta **e o histórico dela**.

---

<div align="center">

Feito por **Mateus Paiva** · [upaiva.dev](https://upaiva.dev)

<sub>Fontes Inter sob a licença SIL Open Font. Marcas citadas pertencem aos seus donos.</sub>

</div>
