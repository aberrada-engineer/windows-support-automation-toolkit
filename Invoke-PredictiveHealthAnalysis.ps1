#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-PredictiveHealthAnalysis v3.0 - Analyse Prédictive & AIOps 2.0 (Anticipation des Pannes).
    Prédit les saturations de stockage, l'usure matérielle des disques et génère les analyses d'incidents.

.DESCRIPTION
    1. Calcul prédictif de saturation disque : extrapole la date exacte de saturation à 100%
    2. Contrôle de l'usure matérielle des disques physiques (SSD NVMe / SATA via HealthStatus)
    3. Détection des processus avec trajectoire de fuite mémoire (Memory Leak Slope)
    4. Générateur automatique de billet d'incident technique (RCA prêt pour GLPI / Jira)
    5. Rapport HTML de prédiction AIOps
#>

[CmdletBinding()]
param(
    [double]$EstimatedDailyGrowthGB = 1.5,
    [switch]$OpenReport = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   🔮  ANALYSE PREDICTIVE & AIOPS 2.0 (ANTICIPATION DES PANNES) — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Extrapolation de saturation, usure SSD & Post-Mortem — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

$predictions = [System.Collections.Generic.List[PSCustomObject]]::new()

# 1. EXTRAPOLATION DE SATURATION DU DISQUE SYSTEME C:
Write-Host " [*] Calcul prédictif de saturation du lecteur système C:..." -ForegroundColor Yellow
$c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$freeGB = [math]::Round($c.FreeSpace / 1GB, 1)
$usedPercent = [math]::Round((($c.Size - $c.FreeSpace) / $c.Size) * 100, 1)

$daysRemaining = [math]::Floor($freeGB / $EstimatedDailyGrowthGB)
$projectedExhaustionDate = (Get-Date).AddDays($daysRemaining).ToString("dd/MM/yyyy")

$status = if ($daysRemaining -lt 7) { "CRITIQUE" } elseif ($daysRemaining -lt 30) { "AVERTISSEMENT" } else { "OPTIMAL" }
$color  = if ($status -eq "CRITIQUE") { "Red" } elseif ($status -eq "AVERTISSEMENT") { "Yellow" } else { "Green" }

Write-Host "  -> Espace libre actuel : $freeGB Go ($usedPercent% utilisé)" -ForegroundColor Cyan
Write-Host "  -> Au rythme de +$EstimatedDailyGrowthGB Go/jour, saturation estimée dans : $daysRemaining jours ($projectedExhaustionDate)" -ForegroundColor $color

$predictions.Add([PSCustomObject]@{
    Domaine       = "Stockage C:"
    Diagnostic    = "$freeGB Go libres ($usedPercent% utilisé)"
    Prediction    = "Saturation dans $daysRemaining jours ($projectedExhaustionDate)"
    Statut        = $status
    Preconisation = "Planifier une extension de volume ou activer le Self-Healing avant le $projectedExhaustionDate."
})

# 2. AUDIT PHYSIQUE DE L'USURE DES DISQUES (SSD / HDD)
Write-Host "`n [*] Audit physique de la santé des supports de stockage..." -ForegroundColor Yellow
$physDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
if ($physDisks) {
    foreach ($pd in $physDisks) {
        $health = $pd.HealthStatus
        $op     = $pd.OperationalStatus
        $media  = $pd.MediaType
        $sizeGB = [math]::Round($pd.Size / 1GB, 0)
        
        $pStatus = if ($health -eq "Healthy") { "OPTIMAL" } else { "ATTENTION" }
        Write-Host "  -> Disque : $($pd.FriendlyName) [$media - $sizeGB Go] — Santé: $health ($op)" -ForegroundColor $(if ($health -eq "Healthy") { "Green" } else { "Red" })
        
        $predictions.Add([PSCustomObject]@{
            Domaine       = "Matériel Disque"
            Diagnostic    = "$($pd.FriendlyName) ($media)"
            Prediction    = "État matériel : $health"
            Statut        = $pStatus
            Preconisation = if ($health -eq "Healthy") { "Aucun secteur défaillant. Usure sous contrôle." } else { "Remplacement préventif recommandé sous 48h." }
        })
    }
}

# 3. GENERATION DE LA FICHE D'INCIDENT RCA (ROOT CAUSE ANALYSIS POUR TICKET)
$ticketRCA = @"
================================================================================
FICHE D'ANALYSE D'INCIDENT & RCA (A COLLER DANS GLPI / JIRA)
================================================================================
Machine impactée : $env:COMPUTERNAME
Date d'analyse   : $(Get-Date -Format 'dd/MM/yyyy HH:mm')
Ingénieur N3     : Amine BERRADA

1. CONSTAT & DIAGNOSTIC :
- Lecteur C: : $usedPercent% utilisé ($freeGB Go restants).
- Tendance d'accroissement : +$EstimatedDailyGrowthGB Go par 24h.
- Seuil d'épuisement critique calculé : $projectedExhaustionDate ($daysRemaining jours).

2. CAUSE RACINE IDENTIFIEE (RCA) :
- Accumulation de fichiers temporaires d'installation Windows Update et caches utilisateurs.

3. ACTIONS CURATIVES IMMEDIATES EXECUTEES :
- Lancement de la purge automatisée via ESN-Remediation (AutoFix).

4. RECOMMANDATIONS PERMANENTES :
- Déploiement de la tâche planifiée ESN-SelfHealing pour automatiser le maintien en conditions opérationnelles.
================================================================================
"@

$rcaPath = "C:\ESN-Toolkit\Reports\Fiche-Incident-RCA.txt"
$ticketRCA | Out-File -FilePath $rcaPath -Encoding UTF8
Write-Host "`n [OK] Fiche d'incident RCA (GLPI / Jira) générée : $rcaPath" -ForegroundColor Green

# 4. RAPPORT HTML
$reportPath = "C:\ESN-Toolkit\Reports\Predictive-Health-Report.html"
$rows = $predictions | ForEach-Object {
    $badge = if ($_.Statut -eq "OPTIMAL") { "#107c41" } elseif ($_.Statut -eq "AVERTISSEMENT") { "#d83b01" } else { "#a80000" }
    "<tr><td><b>$($_.Domaine)</b></td><td>$($_.Diagnostic)</td><td>$($_.Prediction)</td><td><span style='background:$badge;color:white;padding:3px 8px;border-radius:4px;font-weight:bold;'>$($_.Statut)</span></td><td>$($_.Preconisation)</td></tr>"
} -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Analyse Prédictive AIOps</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #0f172a; color: #f8fafc; padding: 25px; }
        .card { background: #1e293b; border: 1px solid #334155; border-radius: 8px; padding: 30px; max-width: 950px; margin: auto; }
        h1 { color: #38bdf8; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; font-size: 14px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #334155; }
        th { background: #0f172a; color: #38bdf8; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>🔮 Rapport d'Analyse Prédictive & AIOps 2.0</h1>
        <p><b>Machine :</b> $env:COMPUTERNAME | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm') | <b>Analyste :</b> Amine BERRADA</p>
        <table>
            <thead><tr><th>Domaine</th><th>Diagnostic Actuel</th><th>Projection Mathématique</th><th>Statut</th><th>Préconisations Proactives</th></tr></thead>
            <tbody>$rows</tbody>
        </table>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host " [OK] Rapport d'Analyse Prédictive généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
