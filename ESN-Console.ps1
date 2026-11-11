#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ESN-Console v3.0 - Menu d'administration interactif (TUI).
    Permet de piloter toutes les fonctionnalités du toolkit en quelques touches.
#>

$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent

function Show-Header {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   🖥️  ESN-TOOLKIT v3.0 — CONSOLE INTERACTIVE D'ADMINISTRATION" -ForegroundColor White
    Write-Host "       Plateforme Support, MCO, Reseau & Securite — Amine BERRADA" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  Hote : $env:COMPUTERNAME  |  Utilisateur : $env:USERNAME  |  Date : $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor DarkCyan
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
}

do {
    Show-Header
    Write-Host " [1] 📊 Audit Sante Complet + Rapport HTML Interactif" -ForegroundColor Green
    Write-Host " [2] ⚡ Auto-Remediation Totale (Fix 8 pannes courantes + Rapport)" -ForegroundColor Yellow
    Write-Host " [3] 🔍 Diagnostic Rapide (Simulation sans modification systeme)" -ForegroundColor Cyan
    Write-Host " [4] 🖨️  Reparation Imprimante (Purge et reset du Spooler d'impression)" -ForegroundColor White
    Write-Host " [5] 🌐 Reset Reseau (Purge DNS, Winsock et pile TCP/IP)" -ForegroundColor White
    Write-Host " [6] ☁️  Reparation Caches M365 (Teams, Outlook RoamCache, OneDrive, WAM Auth)" -ForegroundColor White
    Write-Host " [7] 🏢 Audit Sante Active Directory & Reseau Infrastructure" -ForegroundColor Magenta
    Write-Host " [8] 🛡️  Audit Posture de Securite (BitLocker, Veeam, EDR, Ports)" -ForegroundColor Red
    Write-Host " [9] 📂 Ouvrir le dernier rapport HTML dans le navigateur" -ForegroundColor Blue
    Write-Host " [10]📦 Generer l'archive ZIP incident pour le ticket (Jira / GLPI / ServiceNow)" -ForegroundColor Cyan
    Write-Host " [Q] ❌ Quitter" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    $choice = Read-Host " Entrez votre choix (1-10 ou Q)"

    switch ($choice.ToUpper()) {
        "1" {
            Write-Host "`n[*] Lancement de l'audit de sante global..." -ForegroundColor Cyan
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -OpenReport
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "2" {
            Write-Host "`n[*] Lancement de l'auto-remediation complete..." -ForegroundColor Yellow
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -AutoFix -OpenReport
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "3" {
            Write-Host "`n[*] Lancement du diagnostic en mode SIMULATION..." -ForegroundColor Cyan
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Simulation -OpenReport
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "4" {
            Write-Host "`n[*] Purge et redemarrage du spooler d'impression..." -ForegroundColor White
            Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -Recurse -ErrorAction SilentlyContinue
            Start-Service -Name Spooler -ErrorAction SilentlyContinue
            Write-Host "[OK] Spooler d'impression nettoye et redemarre avec succes." -ForegroundColor Green
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "5" {
            Write-Host "`n[*] Reinitialisation pile reseau & DNS..." -ForegroundColor White
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Fix DNS,Winsock
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "6" {
            Write-Host "`n[*] Purge des caches M365..." -ForegroundColor White
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Fix Teams,Outlook,OneDrive
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "7" {
            Write-Host "`n[*] Audit de l'Active Directory et de l'infrastructure..." -ForegroundColor Magenta
            if (Test-Path "$ScriptDir\Modules\Infra\ESN-Infra.psm1") {
                Import-Module "$ScriptDir\Modules\Infra\ESN-Infra.psm1" -Force
                Test-ESNADHealth
            } else {
                Write-Host "[!] Module Infra en cours d'activation." -ForegroundColor Yellow
            }
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "8" {
            Write-Host "`n[*] Audit de posture de securite et sauvegardes..." -ForegroundColor Red
            if (Test-Path "$ScriptDir\Modules\Infra\ESN-Infra.psm1") {
                Import-Module "$ScriptDir\Modules\Infra\ESN-Infra.psm1" -Force
                Test-ESNSecurityPosture
                Test-ESNVeeamStatus
            } else {
                Write-Host "[!] Module Infra en cours d'activation." -ForegroundColor Yellow
            }
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "9" {
            $latestReport = Get-ChildItem "C:\ESN-Toolkit\Reports\*.html" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestReport) {
                Start-Process $latestReport.FullName
                Write-Host "[OK] Rapport ouvert : $($latestReport.FullName)" -ForegroundColor Green
            } else {
                Write-Host "[!] Aucun rapport HTML trouve dans C:\ESN-Toolkit\Reports" -ForegroundColor Yellow
            }
            Start-Sleep -Seconds 2
        }
        "10" {
            $ticket = Read-Host "Entrez le numero de ticket (ex: INC-10492)"
            if (-not $ticket) { $ticket = "INC-$(Get-Date -Format 'yyyyMMdd-HHmm')" }
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -IncidentId $ticket -ExportZip
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
    }
} while ($choice.ToUpper() -ne "Q")

Write-Host "`nFermeture d'ESN-Console. A bientot !" -ForegroundColor Cyan
Start-Sleep -Seconds 1
