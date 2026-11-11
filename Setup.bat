@echo off
:: ============================================================================
:: ESN-Toolkit v3.0 - Setup & Installation Automatique (1-Clic)
:: Développé pour Amine BERRADA - Administrateur Systèmes & Réseaux
:: ============================================================================
title ESN-Toolkit - Installation
color 0B

echo ===============================================================================
echo            INSTALLATION AUTOMATIQUE - ESN-TOOLKIT v3.0
echo       Infrastructure & Workstation Support Automation Platform
echo ===============================================================================
echo.

:: Vérification des privilèges administrateur
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ATTENTION] Ce script necessite des privileges Administrateur.
    echo Elevation des privileges en cours...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Exécution du script PowerShell d'installation
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ESNToolkit.ps1"

echo.
echo Appuyez sur une touche pour quitter...
pause >nul
