<#
.SYNOPSIS
    Invoke-IncidentAnalysis v3 — Orchestrateur principal du toolkit ESN.
    PATCH 5/5 — Phase industrialisation & cohérence globale.

.DESCRIPTION
    Intègre l'ensemble des patches de la phase industrialisation :
      - PATCH 1 : ESN-OutputSchema  → sorties JSON unifiées OK/WARNING/CRITICAL
      - PATCH 2 : IncidentPatterns  → base de connaissances incidents
      - PATCH 3 : ESN-ReportBuilder → rapport HTML offline complet
      - PATCH 4 : ESN-Migration v2  → score migration + manifest v2.0
      - ESN-HealthScore             → scoring pondéré 5 domaines
      - ESN-Remediation             → auto-remédiation avec logs avant/après

    Workflow :
      1. Score santé multi-domaines (Réseau/Système/Sécurité/Stockage/Services)
      2. Diagnostic détaillé (Network, Windows, AD, M365)
      3. Remédiation automatique (-AutoFix)
      4. Rapport HTML unifié via ESN-ReportBuilder (sections pliables,
         score global, impacts détaillés, base de connaissances, machine info)
      5. Export JSON standardisé via ESN-OutputSchema
      6. ZIP incident

.PARAMETER ComputerName
    Poste à analyser (local par défaut).
.PARAMETER IncidentId
    Numéro de ticket (auto-généré si absent).
.PARAMETER Modules
    Modules de diagnostic : All | Network | Windows | AD | M365
.PARAMETER AutoFix
    Applique automatiquement toutes les remédiations détectées.
.PARAMETER Fix
    Remédiations ciblées : DNS | Winsock | Services | Teams |
    Outlook | OneDrive | TempFiles | WindowsUpdate
.PARAMETER Force
    Pas de confirmation pour les actions Medium/High risk.
.PARAMETER ExportZip
    Génère un ZIP incident (log + rapport HTML + JSON).
.PARAMETER OpenReport
    Ouvre le rapport HTML dans le navigateur.
.PARAMETER Simulation
    Dry-run : détection réelle, zéro modification système.
.PARAMETER SkipHealthScore
    Sauter le calcul du score santé (plus rapide).
.PARAMETER HoursBack
    Fenêtre d'analyse des événements Windows (défaut 24h).
.PARAMETER ServiceList
    Services supplémentaires à surveiller.

.EXAMPLE
    # Analyse complète + autofix + rapport
    .\Invoke-IncidentAnalysis.ps1 -AutoFix -OpenReport

    # Poste distant, ticket, ZIP
    .\Invoke-IncidentAnalysis.ps1 -ComputerName "PC-DUPONT" -IncidentId "INC-001" -ExportZip -OpenReport

    # Modules ciblés + fix DNS
    .\Invoke-IncidentAnalysis.ps1 -Modules Network,Windows -Fix DNS,TempFiles -Force

    # Simulation complète
    .\Invoke-IncidentAnalysis.ps1 -AutoFix -Simulation -OpenReport

.NOTES
    Auteur  : Amine Berrada
    Version : 3.0.0
    Tags    : diagnostic, incident, scoring, remédiation, rapport, AD, M365, réseau
    Prérequis : PowerShell 5.1+, Windows 10/11
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]   $ComputerName    = $env:COMPUTERNAME,
    [string]   $IncidentId      = "INC-$(Get-Date -Format 'yyyyMMdd-HHmm')",
    [string[]] $Modules         = @("All"),
    [switch]   $AutoFix,
    [string[]] $Fix             = @(),
    [switch]   $Force,
    [switch]   $ExportZip,
    [switch]   $OpenReport,
    [switch]   $Simulation,
    [switch]   $SkipHealthScore,
    [int]      $HoursBack       = 24,
    [string[]] $ServiceList     = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ─────────────────────────────────────────────────────────────
# CHEMINS
# ─────────────────────────────────────────────────────────────
$Root  = $PSScriptRoot
$Paths = @{
    Core            = Join-Path $Root "Core\ESN-Core.psm1"
    OutputSchema    = Join-Path $Root "Core\ESN-OutputSchema.ps1"
    ReportBuilder   = Join-Path $Root "Core\ESN-ReportBuilder.ps1"
    IncidentPatterns= Join-Path $Root "Core\IncidentPatterns.json"
    Network         = Join-Path $Root "Modules\Network\ESN-Network.psm1"
    Windows         = Join-Path $Root "Modules\Windows\ESN-Windows.psm1"
    AD              = Join-Path $Root "Modules\AD\ESN-AD.psm1"
    M365            = Join-Path $Root "Modules\M365\ESN-M365.psm1"
    Remediation     = Join-Path $Root "Modules\Remediation\ESN-Remediation.psm1"
    HealthScore     = Join-Path $Root "Modules\HealthScore\ESN-HealthScore.psm1"
}

# ─────────────────────────────────────────────────────────────
# CHARGEMENT CORE (obligatoire)
# ─────────────────────────────────────────────────────────────
if (-not (Test-Path $Paths.Core)) {
    Write-Host "[ERREUR FATAL] Core introuvable : $($Paths.Core)" -ForegroundColor Red
    Write-Host "Exécuter depuis la racine du toolkit." -ForegroundColor Yellow
    exit 1
}
Remove-Module ESN-Core -Force -ErrorAction SilentlyContinue
Import-Module $Paths.Core -Force -ErrorAction Stop

# ─────────────────────────────────────────────────────────────
# CHARGEMENT PATCHES (non-bloquants si absents)
# ─────────────────────────────────────────────────────────────
$hasOutputSchema  = $false
$hasReportBuilder = $false

if (Test-Path $Paths.OutputSchema) {
    . $Paths.OutputSchema
    $hasOutputSchema = $true
    Write-ESNLog "ESN-OutputSchema chargé" "OK"
} else {
    Write-ESNLog "ESN-OutputSchema absent — sorties JSON désactivées" "WARN"
}

if (Test-Path $Paths.ReportBuilder) {
    . $Paths.ReportBuilder
    $hasReportBuilder = $true
    Write-ESNLog "ESN-ReportBuilder chargé" "OK"
} else {
    Write-ESNLog "ESN-ReportBuilder absent — rapport HTML basique" "WARN"
}

# ─────────────────────────────────────────────────────────────
# SESSION
# ─────────────────────────────────────────────────────────────
Initialize-ESNSession -ScriptName "Invoke-IncidentAnalysis.ps1" `
                      -IncidentId $IncidentId `
                      -ComputerName $ComputerName

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────
function Should-Run([string]$m) {
    $Modules -contains "All" -or $Modules -contains $m
}

function Load-ESNModule([string]$Name, [string]$Path) {
    if (-not (Test-Path $Path)) {
        Write-ESNLog "Module $Name introuvable : $Path" "WARN"
        return $false
    }
    Remove-Module $Name -Force -ErrorAction SilentlyContinue
    Import-Module $Path -Force -ErrorAction SilentlyContinue
    Write-ESNLog "Module chargé : $Name" "OK"
    return $true
}

# ─────────────────────────────────────────────────────────────
# PRÉ-CHECKS
# ─────────────────────────────────────────────────────────────
Write-ESNLog "Vérifications préliminaires" "SECTION"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Add-ESNResult "Prérequis" "Droits administrateur" `
    (if ($isAdmin) { "OK" } else { "WARN" }) `
    (if ($isAdmin) { "Admin" } else { "Non-admin — checks limités" }) "" `
    -ScoreImpact $(if (-not $isAdmin) { 5 } else { 0 })

Add-ESNResult "Prérequis" "PowerShell" "OK" "v$($PSVersionTable.PSVersion)" ""
Add-ESNResult "Prérequis" "Patches industrialisation" `
    (if ($hasOutputSchema -and $hasReportBuilder) { "OK" } else { "WARN" }) `
    "OutputSchema:$(if($hasOutputSchema){'✓'}else{'✗'}) ReportBuilder:$(if($hasReportBuilder){'✓'}else{'✗'})" ""

if ($Simulation) {
    Add-ESNResult "Prérequis" "Mode" "WARN" "SIMULATION — Aucune modification système" ""
}

if ($ComputerName -ne $env:COMPUTERNAME) {
    if (-not (Test-Connection $ComputerName -Count 2 -Quiet -ErrorAction SilentlyContinue)) {
        Add-ESNResult "Prérequis" "Joignabilité $ComputerName" "ERROR" "INJOIGNABLE" "" 30
        Write-ESNLog "Poste $ComputerName injoignable — arrêt." "ERROR"
        Show-ESNSummary
        exit 1
    }
    Add-ESNResult "Prérequis" "Joignabilité $ComputerName" "OK" "Ping OK" ""
} else {
    Add-ESNResult "Prérequis" "Cible" "INFO" "Analyse locale — $env:COMPUTERNAME" ""
}

# ─────────────────────────────────────────────────────────────
# HEALTH SCORE (scoring pondéré 5 domaines)
# ─────────────────────────────────────────────────────────────
$healthResult = $null
if (-not $SkipHealthScore) {
    Write-ESNLog "MODULE SCORE SANTÉ" "SECTION"
    if (Load-ESNModule "ESN-HealthScore" $Paths.HealthScore) {
        try {
            $healthResult = Invoke-HealthScore `
                -ComputerName $ComputerName `
                -HoursBack    $HoursBack `
                -Simulation:  $Simulation `
                -PassThru

            if ($healthResult) {
                # Injection des scores dans la session ESN-Core
                # avec traçabilité des impacts (PATCH 1 — centralisation)
                $domMap = [ordered]@{
                    "Réseau"   = "Network"
                    "Système"  = "System"
                    "Sécurité" = "Security"
                    "Stockage" = "Storage"
                    "Services" = "Services"
                }
                foreach ($label in $domMap.Keys) {
                    $key    = $domMap[$label]
                    $score  = $healthResult.$key.Score
                    $lbl    = $healthResult.$key.Label
                    $recs   = $healthResult.$key.Recommendations
                    $st     = if ($score -ge 80) { "OK" } elseif ($score -ge 60) { "WARN" } else { "ERROR" }
                    $impact = if ($st -eq "ERROR") { 15 } elseif ($st -eq "WARN") { 7 } else { 0 }
                    $detail = if ($recs -and $recs.Count -gt 0) {
                        "$($recs.Count) recommandation(s) : $($recs[0])"
                    } else { "Aucune recommandation" }
                    Add-ESNResult "Score $label" "Score pondéré $label" $st `
                        "$score/100 — $lbl" $detail -ScoreImpact $impact
                }

                $gs     = $healthResult.Global.Score
                $gst    = if ($gs -ge 80) { "OK" } elseif ($gs -ge 60) { "WARN" } else { "ERROR" }
                $gimpact= if ($gst -eq "ERROR") { 20 } elseif ($gst -eq "WARN") { 10 } else { 0 }
                Add-ESNResult "Score Global" "Score Santé Pondéré" $gst `
                    "$gs/100 — $($healthResult.Global.Label)" `
                    "Poids : Réseau 20% | Système 20% | Sécurité 25% | Stockage 20% | Services 15%" `
                    -ScoreImpact $gimpact
            }
        } catch {
            Add-ESNResult "Score Santé" "Module HealthScore" "WARN" $_.Exception.Message "" 5
        }
    }
}

# ─────────────────────────────────────────────────────────────
# MODULE NETWORK
# ─────────────────────────────────────────────────────────────
if (Should-Run "Network") {
    Write-ESNLog "MODULE RÉSEAU" "SECTION"
    if (Load-ESNModule "ESN-Network" $Paths.Network) {
        try {
            Invoke-NetworkDiag -ComputerName $ComputerName
        } catch {
            Add-ESNResult "Réseau" "Module Network" "ERROR" $_.Exception.Message "" 10
        }
    }
}

# ─────────────────────────────────────────────────────────────
# MODULE WINDOWS
# ─────────────────────────────────────────────────────────────
if (Should-Run "Windows") {
    Write-ESNLog "MODULE WINDOWS" "SECTION"
    if (Load-ESNModule "ESN-Windows" $Paths.Windows) {
        try {
            Invoke-WindowsDiag -ComputerName $ComputerName -HoursBack $HoursBack
        } catch {
            Add-ESNResult "Windows" "Module Windows" "ERROR" $_.Exception.Message "" 10
        }
    }
}

# ─────────────────────────────────────────────────────────────
# MODULE AD
# ─────────────────────────────────────────────────────────────
if (Should-Run "AD") {
    Write-ESNLog "MODULE ACTIVE DIRECTORY" "SECTION"
    if (Load-ESNModule "ESN-AD" $Paths.AD) {
        try {
            Invoke-ADAudit -InactiveDays 90
        } catch {
            Add-ESNResult "AD" "Module AD" "ERROR" $_.Exception.Message "" 10
        }
    }
}

# ─────────────────────────────────────────────────────────────
# MODULE M365
# ─────────────────────────────────────────────────────────────
if (Should-Run "M365") {
    Write-ESNLog "MODULE MICROSOFT 365" "SECTION"
    if (Load-ESNModule "ESN-M365" $Paths.M365) {
        try {
            Invoke-M365Audit -AutoDisconnect
        } catch {
            Add-ESNResult "M365" "Module M365" "ERROR" $_.Exception.Message "" 10
        }
    }
}

# ─────────────────────────────────────────────────────────────
# MODULE REMÉDIATION
# ─────────────────────────────────────────────────────────────
$remResults = $null
if (Load-ESNModule "ESN-Remediation" $Paths.Remediation) {
    Write-ESNLog "MODULE REMÉDIATION" "SECTION"

    $remParams = @{
        ComputerName = $ComputerName
        AutoFix      = $AutoFix
        Force        = $Force
        Simulation   = $Simulation
        ServiceList  = $ServiceList
    }
    if ($Fix.Count -gt 0) { $remParams.Fix = $Fix }

    try {
        $remResults = Invoke-Remediation @remParams

        # Injection résultats remédiation dans la session
        foreach ($r in $remResults) {
            $st = if (-not $r.Detected)              { "OK"    }
                  elseif ($r.Applied -and $r.Success) { "OK"    }
                  elseif ($r.Applied)                 { "ERROR" }
                  else                                { "WARN"  }

            $val = if (-not $r.Detected)              { "Aucun problème"    }
                   elseif ($r.Applied -and $r.Success) { "Corrigé"           }
                   elseif ($r.Applied)                 { "Échec : $($r.Error)" }
                   else                                { "Détecté, non corrigé — relancer avec -AutoFix" }

            $impact = if ($st -eq "ERROR") { 10 } elseif ($st -eq "WARN") { 5 } else { 0 }
            Add-ESNResult "Remédiation" $r.Name $st $val $r.Detail -ScoreImpact $impact
        }
    } catch {
        Add-ESNResult "Remédiation" "Module Remediation" "ERROR" $_.Exception.Message "" 10
    }
}

# ─────────────────────────────────────────────────────────────
# EXPORT JSON UNIFIÉ (PATCH 1 — ESN-OutputSchema)
# ─────────────────────────────────────────────────────────────
$jsonPath = $null
if ($hasOutputSchema) {
    Write-ESNLog "Export JSON standardisé" "SECTION"
    try {
        $session    = Get-ESNSession
        $jsonDir    = Join-Path (Get-ESNConfig).ReportRoot (Get-Date -Format 'yyyy-MM-dd')
        $jsonPath   = Join-Path $jsonDir "$IncidentId.json"
        New-Item $jsonDir -ItemType Directory -Force | Out-Null

        # Convertir les résultats ESN-Core vers le schéma unifié
        $unifiedChecks = $session.Results | ForEach-Object {
            $sev = switch ($_.Status) {
                "OK"   { "OK"       }
                "WARN" { "WARNING"  }
                "ERROR"{ "CRITICAL" }
                default{ "INFO"     }
            }
            [PSCustomObject]@{
                id           = "$(($_.Category -replace ' ','') -replace '[^A-Z0-9]','' | Select-Object -First 3)-$(Get-Random -Max 999)"
                domain       = ($_.Category -replace ' .*', '')
                check        = $_.Check
                severity     = $sev
                value        = $_.Value
                detail       = $_.Details
                score_impact = if ($sev -eq "CRITICAL") { 15 } elseif ($sev -eq "WARNING") { 5 } else { 0 }
                timestamp    = (Get-Date -Format "o")
            }
        }

        $payload = [PSCustomObject]@{
            schema_version = "1.0"
            incident_id    = $IncidentId
            computer       = $ComputerName
            operator       = $env:USERNAME
            generated_at   = (Get-Date -Format "o")
            simulation     = $Simulation.IsPresent
            global_score   = if ($healthResult) { $healthResult.Global.Score } else { $session.Score }
            domain_scores  = if ($healthResult) {
                @{
                    network  = $healthResult.Network.Score
                    system   = $healthResult.System.Score
                    security = $healthResult.Security.Score
                    storage  = $healthResult.Storage.Score
                    services = $healthResult.Services.Score
                }
            } else { @{} }
            checks_total   = $session.Results.Count
            checks_ok      = @($session.Results | Where-Object Status -eq "OK").Count
            checks_warning = @($session.Results | Where-Object Status -in "WARN","WARNING").Count
            checks_critical= @($session.Results | Where-Object Status -in "ERROR","CRITICAL").Count
            errors         = $session.Errors
            warnings       = $session.Warnings
            checks         = $unifiedChecks
            remediation    = if ($remResults) {
                $remResults | Select-Object Id, Name, Detected, Applied, Success, Before, After, RebootRequired
            } else { @() }
        }

        $payload | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8 -Force
        Write-ESNLog "JSON exporté : $jsonPath" "OK"
        Add-ESNResult "Export" "JSON unifié (schema v1.0)" "OK" $jsonPath ""
    } catch {
        Write-ESNLog "Erreur export JSON : $($_.Exception.Message)" "WARN"
        $jsonPath = $null
    }
}

# ─────────────────────────────────────────────────────────────
# RAPPORT HTML (PATCH 3 — ESN-ReportBuilder)
# ─────────────────────────────────────────────────────────────
Write-ESNLog "Génération rapport HTML" "SECTION"

$reportDir  = Join-Path (Get-ESNConfig).ReportRoot (Get-Date -Format 'yyyy-MM-dd')
$reportPath = Join-Path $reportDir "$IncidentId`_rapport.html"
New-Item $reportDir -ItemType Directory -Force | Out-Null

$session = Get-ESNSession

if ($hasReportBuilder) {
    try {
        $remData = if ($null -ne $remResults) { $remResults } else { @() }
        $reportPath = Build-ESNReport `
            -SessionData          $session `
            -HealthData           $healthResult `
            -RemediationData      $remData `
            -ComputerName         $ComputerName `
            -IncidentId           $IncidentId `
            -OutputPath           $reportPath `
            -IncidentPatternsPath $Paths.IncidentPatterns `
            -Open:                $OpenReport

        Write-ESNLog "Rapport HTML complet (ReportBuilder v3) : $reportPath" "OK"
    } catch {
        Write-ESNLog "ESN-ReportBuilder erreur ($($_.Exception.Message)) — fallback rapport basique" "WARN"
        $hasReportBuilder = $false
    }
}

# Fallback : rapport HTML basique via ESN-Core si ReportBuilder KO
if (-not $hasReportBuilder) {
    $reportPath = Export-ESNReport `
        -Title "Analyse $IncidentId — $ComputerName$(if($Simulation){' [SIM]'})" `
        -OutputPath $reportPath `
        -Open:$OpenReport
    Write-ESNLog "Rapport HTML basique (ESN-Core) : $reportPath" "OK"
}

# ─────────────────────────────────────────────────────────────
# ZIP INCIDENT
# ─────────────────────────────────────────────────────────────
$zipPath = $null
if ($ExportZip) {
    Write-ESNLog "Génération ZIP incident" "SECTION"
    $extraFiles = @($reportPath)
    if ($jsonPath -and (Test-Path $jsonPath)) { $extraFiles += $jsonPath }
    if ($healthResult -and $healthResult.ReportPath -and (Test-Path $healthResult.ReportPath)) {
        $extraFiles += $healthResult.ReportPath
    }
    $zipPath = Export-ESNZip -ExtraFiles $extraFiles
    Write-ESNLog "ZIP : $zipPath" "OK"
}

# ─────────────────────────────────────────────────────────────
# RÉSUMÉ CONSOLE
# ─────────────────────────────────────────────────────────────
Show-ESNSummary

Write-Host ""
if ($healthResult) {
    $gc = if ($healthResult.Global.Score -ge 80) { "Green" } elseif ($healthResult.Global.Score -ge 60) { "Yellow" } else { "Red" }
    Write-Host "  Score santé   : $($healthResult.Global.Score)/100 — $($healthResult.Global.Label)" -ForegroundColor $gc
    Write-Host "    Réseau      : $($healthResult.Network.Score)/100" -ForegroundColor DarkGray
    Write-Host "    Système     : $($healthResult.System.Score)/100"  -ForegroundColor DarkGray
    Write-Host "    Sécurité    : $($healthResult.Security.Score)/100" -ForegroundColor DarkGray
    Write-Host "    Stockage    : $($healthResult.Storage.Score)/100"  -ForegroundColor DarkGray
    Write-Host "    Services    : $($healthResult.Services.Score)/100" -ForegroundColor DarkGray
}
Write-Host "  Rapport HTML  : $reportPath"        -ForegroundColor Cyan
if ($jsonPath) { Write-Host "  JSON unifié   : $jsonPath" -ForegroundColor Cyan }
if ($zipPath)  { Write-Host "  ZIP incident  : $zipPath"  -ForegroundColor Cyan }
Write-Host "  Log           : $($session.LogFile)" -ForegroundColor DarkGray

# Rappel problèmes non corrigés
if ($remResults) {
    $notFixed = @($remResults | Where-Object { $_.Detected -and -not $_.Applied })
    if ($notFixed.Count -gt 0) {
        Write-Host ""
        Write-Host "  ⚠  $($notFixed.Count) problème(s) détecté(s) non corrigé(s) :" -ForegroundColor Yellow
        $notFixed | ForEach-Object { Write-Host "     · $($_.Name)" -ForegroundColor Yellow }
        Write-Host "  → .\Invoke-IncidentAnalysis.ps1 -AutoFix -Force" -ForegroundColor DarkGray
    }
}
Write-Host ""

# ─────────────────────────────────────────────────────────────
# RETOUR OBJET (pipeline-friendly)
# ─────────────────────────────────────────────────────────────
return [PSCustomObject]@{
    # Identité
    IncidentId              = $IncidentId
    ComputerName            = $ComputerName
    Timestamp               = Get-Date

    # Scores
    HealthScore             = if ($healthResult) { $healthResult.Global.Score  } else { $null }
    HealthLabel             = if ($healthResult) { $healthResult.Global.Label  } else { $null }
    ScoreNetwork            = if ($healthResult) { $healthResult.Network.Score  } else { $null }
    ScoreSystem             = if ($healthResult) { $healthResult.System.Score   } else { $null }
    ScoreSecurity           = if ($healthResult) { $healthResult.Security.Score } else { $null }
    ScoreStorage            = if ($healthResult) { $healthResult.Storage.Score  } else { $null }
    ScoreServices           = if ($healthResult) { $healthResult.Services.Score } else { $null }

    # Diagnostic
    DiagScore               = $session.Score
    DiagErrors              = $session.Errors.Count
    DiagWarnings            = $session.Warnings.Count
    TotalChecks             = $session.Results.Count

    # Remédiation
    RemediationsDetected    = if ($remResults) { @($remResults | Where-Object Detected).Count } else { 0 }
    RemediationsFixed       = if ($remResults) { @($remResults | Where-Object { $_.Applied -and $_.Success }).Count } else { 0 }
    RebootRequired          = if ($remResults) { (@($remResults | Where-Object RebootRequired).Count) -gt 0 } else { $false }

    # Fichiers générés
    ReportPath              = $reportPath
    JsonPath                = $jsonPath
    ZipPath                 = $zipPath
    LogPath                 = $session.LogFile
    HealthReportPath        = if ($healthResult) { $healthResult.ReportPath } else { $null }
}
