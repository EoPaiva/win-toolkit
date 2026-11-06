@echo off
title Reverter limpeza
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0scripts\reverter-limpeza.ps1\"'"
pause
