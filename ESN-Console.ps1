#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ESN-Console v3.2 - Console d'Administration & d'Automatisation Totale.
    Permet de piloter toutes les fonctionnalités du toolkit en quelques touches.
#>

$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent

function Show-Header {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   🖥️  ESN-TOOLKIT v3.2 — CONSOLE D'EXPLOITATION & AIOPS TOTALE" -ForegroundColor White
    Write-Host "       Astreinte 24/7, SecOps, PRA/PCA, Cloud Hybride & Predictive — Amine BERRADA" -ForegroundColor Gray
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

    Write-Host "`n --- ASTREINTE 24/7, CYBERSECURITE & RESILIENCE (AI-OPS) ---" -ForegroundColor DarkGray
    Write-Host " [7] 🚨 Triage Flash d'Urgence P1/P2 (Boîte noire, Crash Dumps BSOD, Événements)" -ForegroundColor Red
    Write-Host " [8] 🛑 Ransomware Emergency KillSwitch (Isolement d'urgence & Forensics)" -ForegroundColor Red
    Write-Host " [9] 🔄 Simulateur & Validateur PRA / PCA (Calcul RTO/RPO & Certificat SLA)" -ForegroundColor Green
    Write-Host " [10]🤖 Activer l'Agent d'Auto-Guerison en Arriere-Plan (Self-Healing 15 min)" -ForegroundColor Green
    Write-Host " [11]🔮 Analyse Prédictive AIOps 2.0 (Saturation disque, Usure SSD & RCA)" -ForegroundColor Cyan
    Write-Host " [12]🚀 Zero-Touch Provisioning (Preparer un poste neuf en 1-clic)" -ForegroundColor Cyan
    Write-Host " [13]🛡️  Audit & Durcissement Securite ANSSI / CIS Benchmark" -ForegroundColor Red
    Write-Host " [14]🚚 Assistant de Migration de Poste de A a Z (Sauvegarde / Restauration)" -ForegroundColor Yellow

    Write-Host "`n --- CLOUD HYBRIDE, INFRASTRUCTURE, RESEAU & GOUVERNANCE COPIL ---" -ForegroundColor DarkGray
    Write-Host " [15]☁️  Audit Cloud Hybride (Microsoft Entra ID, Intune & Defender MDE)" -ForegroundColor Cyan
    Write-Host " [16]🌐 Audit Équipements Réseau, Pare-feux (FortiGate) & VPN IPsec" -ForegroundColor Magenta
    Write-Host " [17]🗺️  Cartographie Reseau & Decouverte du Parc (Fleet Discovery)" -ForegroundColor Magenta
    Write-Host " [18]🏢 Audit d'Hygiene & Securite Active Directory (Privileges, Inactifs)" -ForegroundColor Magenta
    Write-Host " [19]📊 Dimensionnement & Chiffrage Infrastructure (Cluster N+1, Stockage COPIL)" -ForegroundColor Cyan
    Write-Host " [20]🔒 Offboarding Collaborateur Securise & Proces-Verbal de Restitution" -ForegroundColor Yellow
    Write-Host " [21]💾 Audit Sauvegardes Veeam & SecOps" -ForegroundColor Cyan
    Write-Host " [22]🖥️  Ouvrir le Tableau de Bord Web Centralisé (ESN-Central Dashboard)" -ForegroundColor Blue
    Write-Host " [23]📂 Ouvrir le dernier rapport HTML dans le navigateur" -ForegroundColor Blue
    Write-Host " [24]📦 Generer l'archive ZIP incident pour le ticket (Jira / GLPI / ServiceNow)" -ForegroundColor Cyan
    Write-Host " [Q] ❌ Quitter" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    $choice = Read-Host " Entrez votre choix (1-24 ou Q)"

    switch ($choice.ToUpper()) {
        "1" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -OpenReport; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "2" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -AutoFix -OpenReport; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "3" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Simulation -OpenReport; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "4" {
            Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -Recurse -ErrorAction SilentlyContinue
            Start-Service -Name Spooler -ErrorAction SilentlyContinue
            Write-Host "[OK] Spooler d'impression nettoye et redemarre." -ForegroundColor Green
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "5" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Fix DNS,Winsock; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "6" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Fix Teams,Outlook,OneDrive,OfficeAuth; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "7" { & "$ScriptDir\Invoke-P1EmergencyTriage.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "8" {
            $sub = Read-Host "Souhaitez-vous ISOLER la machine (1) ou RESTAURER le reseau (2) ?"
            if ($sub -eq "2") { & "$ScriptDir\Invoke-RansomwareShield.ps1" -RestoreNetwork }
            else { & "$ScriptDir\Invoke-RansomwareShield.ps1" }
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "9" { & "$ScriptDir\Invoke-DRTest.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "10" { & "$ScriptDir\Invoke-SelfHealingService.ps1" -InstallServiceTask; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "11" { & "$ScriptDir\Invoke-PredictiveHealthAnalysis.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "12" { & "$ScriptDir\Invoke-ZeroTouchProvisioning.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "13" {
            $enforce = Read-Host "Souhaitez-vous appliquer automatiquement les corrections ? (O/N)"
            if ($enforce.ToUpper() -eq "O") { & "$ScriptDir\Invoke-SecurityHardening.ps1" -Enforce }
            else { & "$ScriptDir\Invoke-SecurityHardening.ps1" }
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "14" { & "$ScriptDir\Invoke-FullStationMigration.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "15" { & "$ScriptDir\Invoke-CloudHybridAudit.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "16" { & "$ScriptDir\Invoke-NetworkApplianceAudit.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "17" { & "$ScriptDir\Invoke-FleetDiscovery.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "18" { & "$ScriptDir\Invoke-ADHygieneCheck.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "19" { & "$ScriptDir\Invoke-InfrastructureSizing.ps1"; Read-Host "`nAppuyez sur Entree pour continuer..." }
        "20" {
            $targetUser = Read-Host "Entrez le nom d'utilisateur a desactiver"
            if ($targetUser) { & "$ScriptDir\Invoke-UserOffboarding.ps1" -Username $targetUser }
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "21" {
            if (Test-Path "$ScriptDir\Modules\Infra\ESN-Infra.psm1") {
                Import-Module "$ScriptDir\Modules\Infra\ESN-Infra.psm1" -Force
                Test-ESNSecurityPosture
                Test-ESNVeeamStatus
            }
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
        "22" { & "$ScriptDir\Invoke-CentralDashboard.ps1"; Start-Sleep -Seconds 2 }
        "23" {
            $latestReport = Get-ChildItem "C:\ESN-Toolkit\Reports\*.html" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestReport) {
                Start-Process $latestReport.FullName
                Write-Host "[OK] Rapport ouvert : $($latestReport.FullName)" -ForegroundColor Green
            } else {
                Write-Host "[!] Aucun rapport HTML trouve." -ForegroundColor Yellow
            }
            Start-Sleep -Seconds 2
        }
        "24" {
            $ticket = Read-Host "Entrez le numero de ticket (ex: INC-10492)"
            if (-not $ticket) { $ticket = "INC-$(Get-Date -Format 'yyyyMMdd-HHmm')" }
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -IncidentId $ticket -ExportZip
            Read-Host "`nAppuyez sur Entree pour continuer..."
        }
    }
} while ($choice.ToUpper() -ne "Q")

Write-Host "`nFermeture d'ESN-Console. A bientot !" -ForegroundColor Cyan
Start-Sleep -Seconds 1
