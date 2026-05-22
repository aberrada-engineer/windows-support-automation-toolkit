<#
.SYNOPSIS
    Invoke-Migration — Capture ou restaure l'état complet d'un utilisateur.

.DESCRIPTION
    Interface en ligne de commande pour le module ESN-Migration.
    Deux modes : Capture (sauvegarde depuis l'ancien poste) et
    Restore (restauration vers le nouveau poste).

.EXAMPLE
    # Capture complète depuis PC-ANCIEN pour l'utilisateur jdupont
    .\Invoke-Migration.ps1 -Action Capture -SourceComputer PC-ANCIEN -Username jdupont -All

    # Capture données + Outlook seulement
    .\Invoke-Migration.ps1 -Action Capture -SourceComputer PC-ANCIEN -Username jdupont -IncludeOutlook

    # Restauration depuis le dossier de backup vers PC-NOUVEAU
    .\Invoke-Migration.ps1 -Action Restore -BackupDir "C:\ESN-Toolkit\Migrations\jdupont_PC-ANCIEN_2025-05-15_1430" -TargetComputer PC-NOUVEAU -Username jdupont

    # Simulation capture (aucune copie)
    .\Invoke-Migration.ps1 -Action Capture -SourceComputer PC-ANCIEN -Username jdupont -All -Simulation

.NOTES
    Auteur   : Amine Berrada
    Version  : 1.0.0
    Tags     : migration, poste, utilisateur, backup, restore, robocopy
    Durée    : 15 min à 2h selon volume
    Prérequis: Accès admin C$ sur les postes source et cible
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("Capture","Restore")]
    [string]$Action,

    # Capture
    [string]$SourceComputer  = "",
    [string]$Username        = $env:USERNAME,
    [string]$BackupRoot      = "C:\ESN-Toolkit\Migrations",
    [switch]$IncludeOutlook,
    [switch]$IncludeBrowsers,
    [switch]$IncludePrinters,
    [switch]$IncludeNetDrives,
    [switch]$All,

    # Restore
    [string]$BackupDir       = "",
    [string]$TargetComputer  = $env:COMPUTERNAME,

    # Commun
    [switch]$Simulation,
    [switch]$OpenReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ToolkitRoot   = $PSScriptRoot
$CorePath      = Join-Path $ToolkitRoot "Core\ESN-Core.psm1"
$MigModulePath = Join-Path $ToolkitRoot "Modules\Migration\ESN-Migration.psm1"

# Chargement des modules
foreach ($mp in @($CorePath, $MigModulePath)) {
    if (-not (Test-Path $mp)) {
        Write-Host "[ERREUR] Module introuvable : $mp" -ForegroundColor Red
        exit 1
    }
    Import-Module $mp -Force -ErrorAction Stop
}

# Session
$incidentId = "MIG-$(Get-Date -Format 'yyyyMMdd-HHmm')-$Username"
Initialize-ESNSession -ScriptName "Invoke-Migration.ps1" `
                      -IncidentId $incidentId `
                      -ComputerName ($SourceComputer ? $SourceComputer : $TargetComputer)

# ─── CAPTURE ─────────────────────────────────────────────────
if ($Action -eq "Capture") {

    if (-not $SourceComputer) {
        Write-Host "[ERREUR] -SourceComputer requis pour la capture." -ForegroundColor Red
        exit 1
    }

    Write-ESNLog "Démarrage CAPTURE — $Username@$SourceComputer" "SECTION"

    $backupDir = Invoke-UserStateCapture `
        -SourceComputer   $SourceComputer `
        -Username         $Username `
        -BackupRoot       $BackupRoot `
        -IncludeOutlook:  $IncludeOutlook `
        -IncludeBrowsers: $IncludeBrowsers `
        -IncludePrinters: $IncludePrinters `
        -IncludeNetDrives:$IncludeNetDrives `
        -All:             $All `
        -Simulation:      $Simulation

    if ($backupDir) {
        Write-ESNLog "Dossier de capture : $backupDir" "OK"
        Write-Host "`n  Dossier de backup : " -NoNewline
        Write-Host $backupDir -ForegroundColor Yellow
        Write-Host "  → Utilisez ce chemin pour la restauration :" -ForegroundColor Cyan
        Write-Host "  .\Invoke-Migration.ps1 -Action Restore -BackupDir `"$backupDir`" -TargetComputer NOM-NOUVEAU-PC -Username $Username" -ForegroundColor Cyan
    }
}

# ─── RESTORE ─────────────────────────────────────────────────
if ($Action -eq "Restore") {

    if (-not $BackupDir) {
        # Proposer un sélecteur interactif si non fourni
        Write-ESNLog "Aucun -BackupDir spécifié — recherche des captures disponibles..." "INFO"
        $available = Get-ChildItem $BackupRoot -Directory -EA SilentlyContinue |
                     Where-Object { Test-Path (Join-Path $_.FullName "manifest.json") } |
                     Sort-Object LastWriteTime -Descending

        if (-not $available) {
            Write-Host "[ERREUR] Aucune capture trouvée dans $BackupRoot" -ForegroundColor Red
            exit 1
        }

        Write-Host "`nCaptures disponibles :" -ForegroundColor Cyan
        $i = 1
        foreach ($d in $available) {
            $mf = Get-Content (Join-Path $d.FullName "manifest.json") -Raw | ConvertFrom-Json
            Write-Host "  [$i] $($d.Name) — $($mf.Username)@$($mf.SourceComputer) — $([math]::Round($mf.SizeMB,0)) Mo" -ForegroundColor White
            $i++
        }
        $choice = Read-Host "`nNuméro de la capture à restaurer"
        $idx    = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $available.Count) {
            Write-Host "Choix invalide." -ForegroundColor Red; exit 1
        }
        $BackupDir = $available[$idx].FullName
    }

    Write-ESNLog "Démarrage RESTAURATION — $BackupDir → $TargetComputer\$Username" "SECTION"

    Invoke-UserStateRestore `
        -BackupDir      $BackupDir `
        -TargetComputer $TargetComputer `
        -Username       $Username `
        -Simulation:    $Simulation
}

# ─── RAPPORT ─────────────────────────────────────────────────
$report = Export-ESNReport `
    -Title "Migration $Action — $Username — $incidentId" `
    -Open:$OpenReport

Show-ESNSummary
Write-Host "`n  Rapport : $report" -ForegroundColor Cyan
