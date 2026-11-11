#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ESN-Console v3.0 - Console d'Administration & d'Automatisation Totale.
    Permet de piloter toutes les fonctionnalités du toolkit en quelques touches.
#>

$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent

function Show-Header {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   🖥️  ESN-TOOLKIT v3.0 — CONSOLE D'AUTOMATISATION TOTALE" -ForegroundColor White
    Write-Host "       AIOps, Astreinte 24/7, SecOps, AD Hygiene & MCO — Amine BERRADA" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  Hote : $env:COMPUTERNAME  |  Utilisateur : $env:USERNAME  |  Date : $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor DarkCyan
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
}

do {
    Show-Header
    Write-Host " --- DIAGNOSTICS & RESOLUTION DES PANNES ---" -ForegroundColor DarkGray
    Write-Host " [1] 📊 Audit Sante Complet + Rapport HTML Interactif" -ForegroundColor Green
    Write-Host " [2] ⚡ Auto-Remediation Totale (Fix 10 pannes courantes + Rapport)" -ForegroundColor Yellow
    Write-Host " [3] 🔍 Diagnostic Rapide (Simulation sans modification systeme)" -ForegroundColor Cyan
    Write-Host " [4] 🖨️  Reparation Imprimante (Purge et reset du Spooler d'impression)" -ForegroundColor White
    Write-Host " [5] 🌐 Reset Reseau (Purge DNS, Winsock et pile TCP/IP)" -ForegroundColor White
    Write-Host " [6] ☁️  Reparation Caches M365 (Teams, Outlook RoamCache, OneDrive, WAM Auth)" -ForegroundColor White

    Write-Host "`n --- ASTREINTE 24/7, AI-OPS & SECURITE AVANCEE ---" -ForegroundColor DarkGray
    Write-Host " [7] 🚨 Triage Flash d'Urgence P1/P2 (Boîte noire, Crash Dumps BSOD, Événements)" -ForegroundColor Red
    Write-Host " [8] 🤖 Activer l'Agent d'Auto-Guerison en Arriere-Plan (Self-Healing 15 min)" -ForegroundColor Green
    Write-Host " [9] 🚀 Zero-Touch Provisioning (Preparer un poste neuf en 1-clic)" -ForegroundColor Cyan
    Write-Host " [10]🛡️  Audit & Durcissement Securite ANSSI / CIS Benchmark" -ForegroundColor Red
    Write-Host " [11]🌐 Cartographie Reseau & Decouverte du Parc (Fleet Discovery)" -ForegroundColor Magenta
    Write-Host " [12]🚚 Assistant de Migration de Poste de A a Z (Sauvegarde / Restauration)" -ForegroundColor Yellow

    Write-Host "`n --- ACTIVE DIRECTORY, INFRASTRUCTURE & GOUVERNANCE ---" -ForegroundColor DarkGray
    Write-Host " [13]🏢 Audit d'Hygiene & Securite Active Directory (Privileges, Inactifs)" -ForegroundColor Magenta
    Write-Host " [14]🔒 Offboarding Collaborateur Securise & Proces-Verbal de Restitution" -ForegroundColor Yellow
    Write-Host " [15]💾 Audit Sauvegardes Veeam & Infrastructure" -ForegroundColor Cyan
    Write-Host " [16]📂 Ouvrir le dernier rapport HTML dans le navigateur" -ForegroundColor Blue
    Write-Host " [17]📦 Generer l'archive ZIP incident pour le ticket (Jira / GLPI / ServiceNow)" -ForegroundColor Cyan
    Write-Host " [Q] ❌ Quitter" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    $choice = Read-Host " Entrez votre choix (1-17 ou Q)"

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
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Fix Teams,Outlook,OneDrive,OfficeAuth
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "7" {
            Write-Host "`n[*] Diagnostic Flash d'Urgence P1/P2..." -ForegroundColor Red
            & "$ScriptDir\Invoke-P1EmergencyTriage.ps1"
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "8" {
            Write-Host "`n[*] Configuration de l'agent d'auto-guerison..." -ForegroundColor Green
            & "$ScriptDir\Invoke-SelfHealingService.ps1" -InstallServiceTask
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "9" {
            Write-Host "`n[*] Lancement du Provisioning Zero-Touch..." -ForegroundColor Cyan
            & "$ScriptDir\Invoke-ZeroTouchProvisioning.ps1"
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "10" {
            Write-Host "`n[*] Audit de durcissement et conformite ANSSI..." -ForegroundColor Red
            $enforce = Read-Host "Souhaitez-vous appliquer automatiquement les corrections ? (O/N)"
            if ($enforce.ToUpper() -eq "O") {
                & "$ScriptDir\Invoke-SecurityHardening.ps1" -Enforce
            } else {
                & "$ScriptDir\Invoke-SecurityHardening.ps1"
            }
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "11" {
            Write-Host "`n[*] Scan et cartographie du reseau..." -ForegroundColor Magenta
            & "$ScriptDir\Invoke-FleetDiscovery.ps1"
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "12" {
            Write-Host "`n[*] Lancement de l'Assistant de Migration..." -ForegroundColor Yellow
            & "$ScriptDir\Invoke-FullStationMigration.ps1"
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "13" {
            Write-Host "`n[*] Audit d'hygiene Active Directory..." -ForegroundColor Magenta
            & "$ScriptDir\Invoke-ADHygieneCheck.ps1"
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "14" {
            Write-Host "`n[*] Offboarding Collaborateur..." -ForegroundColor Yellow
            $targetUser = Read-Host "Entrez le nom d'utilisateur a desactiver"
            if ($targetUser) {
                & "$ScriptDir\Invoke-UserOffboarding.ps1" -Username $targetUser
            }
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "15" {
            Write-Host "`n[*] Audit des sauvegardes Veeam et SecOps..." -ForegroundColor Cyan
            if (Test-Path "$ScriptDir\Modules\Infra\ESN-Infra.psm1") {
                Import-Module "$ScriptDir\Modules\Infra\ESN-Infra.psm1" -Force
                Test-ESNSecurityPosture
                Test-ESNVeeamStatus
            }
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "16" {
            $latestReport = Get-ChildItem "C:\ESN-Toolkit\Reports\*.html" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestReport) {
                Start-Process $latestReport.FullName
                Write-Host "[OK] Rapport ouvert : $($latestReport.FullName)" -ForegroundColor Green
            } else {
                Write-Host "[!] Aucun rapport HTML trouve." -ForegroundColor Yellow
            }
            Start-Sleep -Seconds 2
        }
        "17" {
            $ticket = Read-Host "Entrez le numero de ticket (ex: INC-10492)"
            if (-not $ticket) { $ticket = "INC-$(Get-Date -Format 'yyyyMMdd-HHmm')" }
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -IncidentId $ticket -ExportZip
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
    }
} while ($choice.ToUpper() -ne "Q")

Write-Host "`nFermeture d'ESN-Console. A bientot !" -ForegroundColor Cyan
Start-Sleep -Seconds 1
