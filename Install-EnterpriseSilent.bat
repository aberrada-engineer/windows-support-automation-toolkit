@echo off
:: ============================================================================
:: ESN-Toolkit - Déploiement Silencieux d'Entreprise (GPO / Intune / SCCM)
:: Exécution 100% silencieuse, sans pop-up, avec code de sortie standard
:: ============================================================================
set TARGET=C:\ESN-Toolkit
if not exist "%TARGET%" mkdir "%TARGET%"
if not exist "%TARGET%\Logs" mkdir "%TARGET%\Logs"
if not exist "%TARGET%\Reports" mkdir "%TARGET%\Reports"

:: Synchronisation silencieuse des fichiers
xcopy "%~dp0*" "%TARGET%\" /E /Y /Q /I >nul 2>&1

:: Configuration PowerShell et enregistrement du Gardien Self-Healing
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force; & '%TARGET%\Invoke-SelfHealingService.ps1' -InstallServiceTask" >nul 2>&1

:: Code de retour succès
exit /b 0
