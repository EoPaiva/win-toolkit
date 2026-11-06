# PRODUCT

## Platform

Windows 11 desktop, native WPF on .NET Framework 4.8. No browser, no installed runtime beyond what ships with Windows.

## Stack

C# and XAML compiled with the `csc.exe` that ships with Windows. PowerShell 5.1 scripts do the work; the interface only starts them and follows their log.

## Users and purpose

Mateus Paiva, full-stack developer and Head of AI, on a freshly formatted PC. He runs upaiva.dev once after installing Windows, then returns for maintenance: updating programs, checking drivers, reviewing security and tuning the system. He reads technical output and wants to see the real commands.

## What it does

- Install dependencies, programs, skills and configurations, always at the latest version, through winget, npm and uv.
- Find official driver updates through Windows Update and link to the vendor for graphics.
- Scan security and system health in read-only mode, fixing only what is checked.
- Apply four cumulative, reversible optimization levels, with a dry run first.
- Run maintenance routines and show a live terminal with real commands, PIDs, exit codes and timing.

## Product truth to preserve

- No level disables Defender, Firewall, UAC, SmartScreen, Windows Update, TPM or Secure Boot.
- Performance gains are not promised. VBS is the only tweak with independent measurements, and it stays a separate, unchecked option.
- Status, commands and telemetry on screen are real. Decoration must never read as status.
- Only skills and configurations travel. No projects, logs, history or logins.
- Install, apply and tools are blocked on the source PC (MARINETE); scan, dry run and driver search stay available.

## Voice

Portuguese (Brazil). Direct, specific and plain. Technical terms in the terminal, plain sentences elsewhere.

## Brand commitment

The visual identity follows the owner's site, https://upaiva.dev (repository EoPaiva/terminal-cv). It was named by the owner as the style to follow.

## Inferred

Inferred from this project's conversation, not from an interview: everything above except the brand commitment, which the owner stated directly.
