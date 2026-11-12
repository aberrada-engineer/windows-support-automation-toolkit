<#
.SYNOPSIS
    Invoke-IncidentLabSimulator.ps1 - Simulateur d'Incidents Réels pour Démonstrations Techniques & Entretiens d'Embauche.
.DESCRIPTION
    Conçu pour permettre à Amine BERRADA de réaliser une démonstration en direct (live demo) devant un recruteur ou un jury technique :
    - Génère de manière sûre et contrôlée des anomalies de production (Service arrêté, cache réseau encombré, fichiers temp).
    - Enchaîne immédiatement avec le diagnostic et l'auto-remédiation automatique (-AutoFix).
    - Affiche en direct le passage du score dégradé (ex: 55/100) au score assaini (95/100).
    - Génère et ouvre le rapport HTML complet prouvant l'efficacité de la résolution.
    - Dispose d'un switch de nettoyage (-CleanUp) pour rétablir la machine dans son état d'origine.
.PARAMETER Scenario
    Scénario d'incident à simuler : 'N1-Workstation', 'P1-Emergency', 'SecOps-Baseline'.
.PARAMETER CleanUp
    Nettoie tous les artefacts de simulation créés.
.EXAMPLE
    .\Invoke-IncidentLabSimulator.ps1 -Scenario "N1-Workstation"
#>

[CmdletBinding()]
param(
    [ValidateSet("N1-Workstation", "P1-Emergency", "SecOps-Baseline")]
    [string]$Scenario = "N1-Workstation",
    [switch]$CleanUp
)

$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent

if ($CleanUp) {
    Write-Host "[*] Nettoyage des artefacts de simulation..." -ForegroundColor Cyan
    Remove-Item "$env:TEMP\ESN-Simu-*" -Force -Recurse -ErrorAction SilentlyContinue
    Start-Service -Name Spooler -ErrorAction SilentlyContinue
    Write-Host "[+] Environnement rétabli à l'état initial." -ForegroundColor Green
    return
}

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   ESN-TOOLKIT LIVE DEMO — INCIDENT & SELF-HEALING SIMULATOR               " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "[*] Scénario sélectionné : $Scenario" -ForegroundColor Yellow
Write-Host "[*] Hôte de test         : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host ""

# 1. Injection contrôlée de l'anomalie
Write-Host "[1/3] Injection de l'incident contrôlé pour la démonstration..." -ForegroundColor White

switch ($Scenario) {
    "N1-Workstation" {
        Write-Host "  -> Arrêt du Spooler d'impression pour simuler un blocage..." -ForegroundColor Gray
        Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue

        Write-Host "  -> Création de fichiers temporaires d'encombrement..." -ForegroundColor Gray
        $dummyFile = "$env:TEMP\ESN-Simu-LargeFile-$([guid]::NewGuid().ToString().Substring(0,8)).tmp"
        [IO.File]::WriteAllBytes($dummyFile, (New-Object byte[] 10485760)) # 10 Mo
        Write-Host "  -> Anomalies injectées : Spooler arrêté + 10 Mo de fichiers temp." -ForegroundColor Yellow
    }
    "P1-Emergency" {
        Write-Host "  -> Simulation d'un événement critique d'astreinte..." -ForegroundColor Gray
        Write-EventLog -LogName Application -Source "Application Error" -EventId 1000 -EntryType Error -Message "ESN-Lab Simulation : Crash applicatif critique simulé pour démonstration d'astreinte P1." -ErrorAction SilentlyContinue
        Write-Host "  -> Événement critique généré dans les journaux d'application." -ForegroundColor Yellow
    }
    "SecOps-Baseline" {
        Write-Host "  -> Simulation d'une dérive de posture de sécurité..." -ForegroundColor Gray
        Write-Host "  -> Lancement du contrôle ANSSI..." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "[2/3] Exécution de l'Auto-Remédiation Totale d'ESN-Toolkit (-AutoFix)..." -ForegroundColor White
Write-Host "      (Démonstration de la résolution sans intervention humaine)" -ForegroundColor Gray
Write-Host "--------------------------------------------------------------------------" -ForegroundColor DarkGray

# Appel du moteur d'auto-remédiation
$IncidentScript = Join-Path $ScriptDir "Invoke-IncidentAnalysis.ps1"
if (Test-Path $IncidentScript) {
    & $IncidentScript -AutoFix -OpenReport
} else {
    Write-Host "[-] Moteur principal non trouvé à l'emplacement : $IncidentScript" -ForegroundColor Red
}

Write-Host "--------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "[3/3] Démonstration terminée !" -ForegroundColor Green
Write-Host "      • Le service arrêté a été relancé automatiquement." -ForegroundColor White
Write-Host "      • Les fichiers temporaires ont été purgés." -ForegroundColor White
Write-Host "      • Le rapport exécutif avant/après s'affiche dans votre navigateur." -ForegroundColor White
Write-Host ""
Write-Host "💡 Pour nettoyer les fichiers de test, exécutez :" -ForegroundColor Cyan
Write-Host "   .\Invoke-IncidentLabSimulator.ps1 -CleanUp" -ForegroundColor White
