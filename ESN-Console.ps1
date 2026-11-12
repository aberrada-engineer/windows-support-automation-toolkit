#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ESN-Console v3.8 - Console d'Administration, AIOps & Ingénierie d'Infrastructure.
    Développé pour Amine BERRADA — Administrateur Systèmes & Réseaux / Référent Technique N3.
#>

$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent

function Show-Header {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   🖥️  ESN-TOOLKIT v3.8 — CONSOLE D'EXPLOITATION & AIOPS TOTALE" -ForegroundColor White
    Write-Host "       Astreinte 24/7, SecOps, PRA/PCA, Virtualisation & Gouvernance — Amine BERRADA" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  Hôte : $env:COMPUTERNAME  |  Utilisateur : $env:USERNAME  |  Date : $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor DarkCyan
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
}

do {
    Show-Header
    Write-Host " --- DIAGNOSTICS & RESOLUTION DES PANNES N1/N2 ---" -ForegroundColor DarkGray
    Write-Host " [1]  📊 Audit Santé Complet + Rapport HTML Interactif" -ForegroundColor Green
    Write-Host " [2]  ⚡ Auto-Remédiation Totale (Fix 10 pannes courantes + Rapport)" -ForegroundColor Yellow
    Write-Host " [3]  🔍 Diagnostic Rapide (Simulation sans modification système)" -ForegroundColor Cyan
    Write-Host " [4]  🖨️  Réparation Imprimante (Purge et reset du Spooler d'impression)" -ForegroundColor White
    Write-Host " [5]  🌐 Reset Réseau (Purge DNS, Winsock et pile TCP/IP)" -ForegroundColor White
    Write-Host " [6]  ☁️  Réparation Caches M365 (Teams, Outlook RoamCache, OneDrive, WAM Auth)" -ForegroundColor White
    Write-Host " [7]  📦 Inventaire Matériel & Logiciel GLPI / OCS (Génération JSON/XML)" -ForegroundColor Cyan

    Write-Host "`n --- ASTREINTE 24/7, CYBERSÉCURITÉ & RÉSILIENCE (AIOPS N3) ---" -ForegroundColor DarkGray
    Write-Host " [8]  🚨 Triage Flash d'Urgence P1/P2 (Boîte noire, Crash Dumps BSOD, Événements)" -ForegroundColor Red
    Write-Host " [9]  🛑 Ransomware Emergency KillSwitch (Isolement d'urgence & Forensics)" -ForegroundColor Red
    Write-Host " [10] 🔄 Simulateur & Validateur PRA / PCA (Calcul RTO/RPO & Certificat SLA)" -ForegroundColor Green
    Write-Host " [11] 🤖 Activer l'Agent d'Auto-Guérison en Arrière-Plan (Self-Healing 15 min)" -ForegroundColor Green
    Write-Host " [12] 🔮 Analyse Prédictive AIOps 2.0 (Saturation disque, Usure SSD & RCA)" -ForegroundColor Cyan
    Write-Host " [13] 🚀 Zero-Touch Provisioning (Préparer un poste neuf en 1-clic)" -ForegroundColor Cyan
    Write-Host " [14] 🛡️  Audit & Durcissement Sécurité ANSSI / CIS Benchmark" -ForegroundColor Red
    Write-Host " [15] 🚚 Assistant de Migration de Poste de A à Z (Sauvegarde / Restauration)" -ForegroundColor Yellow

    Write-Host "`n --- INFRASTRUCTURE, SERVEURS, CLOUD & GOUVERNANCE COPIL ---" -ForegroundColor DarkGray
    Write-Host " [16] ☁️  Audit Cloud Hybride (Microsoft Entra ID, Intune & Defender MDE)" -ForegroundColor Cyan
    Write-Host " [17] 🌐 Audit Équipements Réseau, Pare-feux (FortiGate) & VPN IPsec" -ForegroundColor Magenta
    Write-Host " [18] 🗺️  Cartographie Réseau & Découverte du Parc (Fleet Discovery)" -ForegroundColor Magenta
    Write-Host " [19] 🏢 Audit d'Hygiène & Sécurité Active Directory (Privilèges, Inactifs)" -ForegroundColor Magenta
    Write-Host " [20] 🌐 Audit Services Cœur Réseau (DHCP Scopes, Scavenging DNS, Certificats PKI)" -ForegroundColor Cyan
    Write-Host " [21] ✉️  Audit & Diagnostics Exchange Hybride / On-Premise & Routage SMTP" -ForegroundColor Cyan
    Write-Host " [22] 🖥️  Audit Clusters Virtualisation & Hyperconvergence (VMware vSphere & Nutanix)" -ForegroundColor Green
    Write-Host " [23] 📊 Dimensionnement & Chiffrage Infrastructure (Cluster N+1, Stockage COPIL)" -ForegroundColor Cyan
    Write-Host " [24] 📑 Générateur de Rapport Mensuel Exécutif COPIL / COTECH (SLA 99.9%)" -ForegroundColor Green
    Write-Host " [25] 🔒 Offboarding Collaborateur Sécurisé & Procès-Verbal de Restitution" -ForegroundColor Yellow
    Write-Host " [26] 🛠️  Menu des 6 Projets Majeurs Réalisés (MDT, EDR, AD, Aruba, LAPS, Veeam)" -ForegroundColor Blue
    Write-Host " [27] 🐧 Audit Serveur Linux Distant (Ubuntu / Debian via SSH natif)" -ForegroundColor Green
    Write-Host " [28] 📡 Générateur & Déployeur de Sondes PRTG Network Monitor (XML/JSON)" -ForegroundColor Yellow
    Write-Host " [29] 🔄 Audit de Conformité WSUS & Forçage de Détection de Patchs" -ForegroundColor Cyan
    Write-Host " [30] 📑 Générateur de Dossier Officiel de Plan de Reprise d'Activité (PRA / DRP)" -ForegroundColor Magenta
    Write-Host " [31] 🛡️  Audit Posture Zero-Trust & Accès Conditionnel (TPM 2.0, VBS, LSA)" -ForegroundColor Red
    Write-Host " [32] 📢 Dispatcher d'Alertes & Intégration ITSM (GLPI, ServiceNow, Teams)" -ForegroundColor Yellow
    Write-Host " [33] 🎬 Simulateur d'Incidents Live Demo (Démonstration d'Auto-Guérison)" -ForegroundColor Green
    Write-Host " [34] 📊 Ouvrir le Pitch Deck de Présentation Technique (Slides HTML)" -ForegroundColor Blue
    Write-Host " [35] 🖥️  Ouvrir le Tableau de Bord Web Centralisé (ESN-Central Dashboard)" -ForegroundColor Blue
    Write-Host " [36] 📂 Ouvrir le dernier rapport HTML dans le navigateur" -ForegroundColor Blue
    Write-Host " [37] 📦 Générer l'archive ZIP incident pour le ticket (Jira / GLPI / ServiceNow)" -ForegroundColor Cyan
    Write-Host " [Q]  ❌ Quitter" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    $choice = Read-Host " Entrez votre choix (1-37 ou Q)"

    switch ($choice.ToUpper()) {
        "1" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -OpenReport; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "2" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -AutoFix -OpenReport; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "3" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Simulation -OpenReport; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "4" {
            Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -Recurse -ErrorAction SilentlyContinue
            Start-Service -Name Spooler -ErrorAction SilentlyContinue
            Write-Host "[OK] Spooler d'impression nettoyé et redémarré." -ForegroundColor Green
            Read-Host "`nAppuyez sur Entrée pour continuer..."
        }
        "5" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Fix DNS,Winsock; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "6" { & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -Fix Teams,Outlook,OneDrive,OfficeAuth; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "7" { & "$ScriptDir\Invoke-GLPIInventoryAgent.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "8" { & "$ScriptDir\Invoke-P1EmergencyTriage.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "9" {
            $sub = Read-Host "Souhaitez-vous ISOLER la machine (1) ou RESTAURER le réseau (2) ?"
            if ($sub -eq "2") { & "$ScriptDir\Invoke-RansomwareShield.ps1" -RestoreNetwork }
            else { & "$ScriptDir\Invoke-RansomwareShield.ps1" }
            Read-Host "`nAppuyez sur Entrée pour continuer..."
        }
        "10" { & "$ScriptDir\Invoke-DRTest.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "11" { & "$ScriptDir\Invoke-SelfHealingService.ps1" -InstallServiceTask; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "12" { & "$ScriptDir\Invoke-PredictiveHealthAnalysis.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "13" { & "$ScriptDir\Invoke-ZeroTouchProvisioning.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "14" {
            $enforce = Read-Host "Souhaitez-vous appliquer automatiquement les corrections ? (O/N)"
            if ($enforce.ToUpper() -eq "O") { & "$ScriptDir\Invoke-SecurityHardening.ps1" -Enforce }
            else { & "$ScriptDir\Invoke-SecurityHardening.ps1" }
            Read-Host "`nAppuyez sur Entrée pour continuer..."
        }
        "15" { & "$ScriptDir\Invoke-FullStationMigration.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "16" { & "$ScriptDir\Invoke-CloudHybridAudit.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "17" { & "$ScriptDir\Invoke-NetworkApplianceAudit.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "18" { & "$ScriptDir\Invoke-FleetDiscovery.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "19" { & "$ScriptDir\Invoke-ADHygieneCheck.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "20" { & "$ScriptDir\Invoke-CoreServicesAudit.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "21" { & "$ScriptDir\Invoke-ExchangeHealthCheck.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "22" { & "$ScriptDir\Invoke-HypervisorAudit.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "23" { & "$ScriptDir\Invoke-InfrastructureSizing.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "24" { & "$ScriptDir\Invoke-COPILReportGenerator.ps1"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "25" {
            $targetUser = Read-Host "Entrez le nom d'utilisateur à désactiver"
            if ($targetUser) { & "$ScriptDir\Invoke-UserOffboarding.ps1" -Username $targetUser }
            Read-Host "`nAppuyez sur Entrée pour continuer..."
        }
        "26" {
            Clear-Host
            Write-Host "================================================================================" -ForegroundColor Cyan
            Write-Host "   PROJETS MAJEURS RÉALISÉS PAR AMINE BERRADA (ESN & CLIENTS FINAUX)            " -ForegroundColor White
            Write-Host "================================================================================" -ForegroundColor Cyan
            Write-Host " [A] 🔄 Migration Inter-Domaines Active Directory (SID History, ACLs NTFS)" -ForegroundColor White
            Write-Host " [B] 🛡️  Déploiement Automatisé d'EDR / Antivirus (+200 hôtes SentinelOne)" -ForegroundColor White
            Write-Host " [C] 🔌 Déploiement & Configuration Switches Aruba (~20 commutateurs)" -ForegroundColor White
            Write-Host " [D] 🔐 Déploiement Windows LAPS & Durcissement Post-Audit" -ForegroundColor White
            Write-Host " [E] 🏢 Bascule Planifiée Datacenter & Orchestration Veeam PRA" -ForegroundColor White
            Write-Host " [F] 🖥️  Industrialisation Déploiement MDT / WDS (~200 Postes Texdecor)" -ForegroundColor White
            Write-Host " [G] 🌐 Refonte WAN Multi-Sites (MPLS / SD-WAN) & PRA Intersites" -ForegroundColor White
            Write-Host " [R] ↩️  Retour au menu principal" -ForegroundColor DarkGray
            Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
            $pChoice = Read-Host "Sélectionnez un projet à auditer ou simuler (A-G ou R)"
            switch ($pChoice.ToUpper()) {
                "A" { & "$ScriptDir\Projects\AD-Migration\Invoke-ADDomainMigration.ps1" -ReportOnly }
                "B" { & "$ScriptDir\Projects\EDR-Deployment\Invoke-EDRMassRollout.ps1" -ReportOnly }
                "C" { & "$ScriptDir\Projects\Network-Aruba\New-ArubaSwitchConfig.ps1" }
                "D" { & "$ScriptDir\Projects\Windows-LAPS\Deploy-WindowsLAPS.ps1" -ReportOnly }
                "E" { & "$ScriptDir\Projects\Datacenter-Migration\Invoke-VeeamFailoverPlan.ps1" -DryRun }
                "F" { & "$ScriptDir\Projects\MDT-Deployment\Invoke-MDTIndustrialization.ps1" -ReportOnly }
                "G" { & "$ScriptDir\Projects\WAN-MPLS-Refonte\Invoke-WANMigrationPlan.ps1" -ReportOnly }
            }
            Read-Host "`nAppuyez sur Entrée pour revenir au menu principal..."
        }
        "27" {
            $lHost = Read-Host "Entrez l'IP ou le nom du serveur Linux (défaut: 192.168.1.50)"
            if (-not $lHost) { $lHost = "192.168.1.50" }
            & "$ScriptDir\Invoke-LinuxHeterogeneousAudit.ps1" -TargetHost $lHost -SimulationMode -OpenReport
            Read-Host "`nAppuyez sur Entrée pour continuer..."
        }
        "28" { & "$ScriptDir\Invoke-PRTGSensorDeployer.ps1" -TargetSensor "All"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "29" { & "$ScriptDir\Invoke-WSUSComplianceManager.ps1" -OpenReport; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "30" { & "$ScriptDir\Invoke-DRPGenerator.ps1" -OpenReport; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "31" { & "$ScriptDir\Invoke-ZeroTrustAudit.ps1" -OpenReport; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "32" { & "$ScriptDir\Invoke-ITSMConnector.ps1" -Target Simulation; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "33" { & "$ScriptDir\Invoke-IncidentLabSimulator.ps1" -Scenario "N1-Workstation"; Read-Host "`nAppuyez sur Entrée pour continuer..." }
        "34" {
            $slides = Join-Path $ScriptDir "Presentation\index.html"
            if (Test-Path $slides) { Start-Process $slides; Write-Host "[OK] Pitch Deck ouvert." -ForegroundColor Green }
            Start-Sleep -Seconds 2
        }
        "35" { & "$ScriptDir\Invoke-CentralDashboard.ps1"; Start-Sleep -Seconds 2 }
        "36" {
            $latestReport = Get-ChildItem "C:\ESN-Toolkit\Reports\*.html", "$env:SystemDrive\ESN-Reports\*\*.html" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestReport) {
                Start-Process $latestReport.FullName
                Write-Host "[OK] Rapport ouvert : $($latestReport.FullName)" -ForegroundColor Green
            } else {
                Write-Host "[!] Aucun rapport HTML trouvé." -ForegroundColor Yellow
            }
            Start-Sleep -Seconds 2
        }
        "37" {
            $ticket = Read-Host "Entrez le numéro de ticket (ex: INC-10492)"
            if (-not $ticket) { $ticket = "INC-$(Get-Date -Format 'yyyyMMdd-HHmm')" }
            & "$ScriptDir\Invoke-IncidentAnalysis.ps1" -IncidentId $ticket -ExportZip
            Read-Host "`nAppuyez sur Entrée pour continuer..."
        }
    }
} while ($choice.ToUpper() -ne "Q")

Write-Host "`nFermeture d'ESN-Console. À bientôt !" -ForegroundColor Cyan
Start-Sleep -Seconds 1
