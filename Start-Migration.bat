@echo off
:: ============================================================================
:: Assistant de Migration de Poste de A à Z - ESN-Toolkit
:: ============================================================================
title ESN-Toolkit - Migration de Poste
color 0E

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ELEVATION] Demande des droits Administrateur...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-FullStationMigration.ps1"
