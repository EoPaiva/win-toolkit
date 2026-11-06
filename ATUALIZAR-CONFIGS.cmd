@echo off
title Atualizar configs
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALADOR\scripts\gerar-snapshot.ps1"
pause
