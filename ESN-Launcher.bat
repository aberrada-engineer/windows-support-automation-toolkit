@echo off
:: ============================================================================
:: ESN-Toolkit - Lanceur Interface Graphique
:: ============================================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ESN-GUI.ps1"
exit
