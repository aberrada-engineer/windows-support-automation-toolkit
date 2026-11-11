@echo off
:: ============================================================================
:: ESN-Toolkit - Console Interactive d'Administration
:: ============================================================================
title ESN-Toolkit - Console Interactive
color 0F

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ESN-Console.ps1"
