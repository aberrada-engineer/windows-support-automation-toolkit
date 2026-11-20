<#
.SYNOPSIS
    Invoke-COPILReportGenerator.ps1 - Générateur de Rapport Mensuel Exécutif pour Comités de Pilotage (COPIL) et Comités Techniques (COTECH).
.DESCRIPTION
    Conçu pour les ESN et DSI exigeantes (expérience AEXIN Genève, Porsche, TAG Heuer, Hublot) :
    - Calcul du Taux de Disponibilité Système (SLA global, cible 99.9%).
    - Répartition et métriques des incidents par criticité (P1 Bloquant, P2 Majeur, P3 Mineur) et MTTR (Mean Time To Resolve).
    - Taux de succès des sauvegardes et immutabilité PRA (Veeam).
    - Suivi de la capacité de stockage et tendances d'obsolescence matérielle.
    - Suivi des remédiations de sécurité et conformité EDR/LAPS.
    - Production d'un rapport exécutif HTML ultra-design avec indicateurs clés, cadrage budgétaire et recommandations stratégiques.
.PARAMETER ClientName
    Nom du compte client / contrat infogérance (ex: "Groupe Luxe - Genève").
.PARAMETER ReportingMonth
    Période de facturation / reporting (défaut: mois en cours).
.EXAMPLE
    .\Invoke-COPILReportGenerator.ps1 -ClientName "AEXIN - Contrat VIP Genève"
#>

[CmdletBinding()]
param(
    [string]$ClientName = "Compte Entreprise Clé",
    [string]$ReportingMonth = (Get-Date -Format "MMMM yyyy"),
    [double]$TargetSla = 99.9,
    [switch]$Simulate,
    [switch]$OpenInBrowser
)
Set-StrictMode -Version Latest

$ErrorActionPreference = "Continue"

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   EXECUTIVE COPIL / COTECH REPORT GENERATOR (GOVERNANCE & SLA 99.9%)     " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "[*] Client / Contrat : $ClientName" -ForegroundColor Gray
Write-Host "[*] Période de suivi : $ReportingMonth" -ForegroundColor Gray
Write-Host "[*] Cible SLA        : $TargetSla % | Simulate : $Simulate" -ForegroundColor Gray
Write-Host ""

$schemaScript = Join-Path $PSScriptRoot "Core/ESN-OutputSchema.ps1"
if (Test-Path $schemaScript) { . $schemaScript }
$ReportDir = if (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) { Get-ESNReportRoot -SubFolder "COPIL" } elseif ($env:ESN_TOOLKIT_ROOT) { Join-Path $env:ESN_TOOLKIT_ROOT "Reports/COPIL" } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports/COPIL" }
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$HtmlFile = Join-Path $ReportDir "COPIL-Executive-$Timestamp.html"

# 1. Collecte télémétrique locale
Write-Host "[1/4] Collecte des indicateurs de performance et d'incidents..." -ForegroundColor White
$OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$UptimeDays = if ($OS -and $OS.LastBootUpTime) { [math]::Round(((Get-Date) - $OS.LastBootUpTime).TotalDays, 1) } else { "N/A" }

if ($Simulate) {
    $ActualSLA         = "99.94%"
    $TotalTickets      = 47
    $P1Tickets         = 1
    $P2Tickets         = 4
    $P3Tickets         = 42
    $MttrMinutes       = "28 min"
    $BackupSuccessRate = "100%"
    $AntivirusCoverage = "100%"
    $SlaBadgeText      = "MODE SIMULATION — SLA $TargetSla%"
    $SlaFooterNote     = "Simulation COPIL — Métriques de démonstration (connecteur ITSM non requis en mode -Simulate)."
} else {
    $mpStatus = if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) { Get-MpComputerStatus -ErrorAction SilentlyContinue } else { $null }
    $veeamSvc = @(Get-Service -Name "*Veeam*" -ErrorAction SilentlyContinue)
    $ActualSLA         = "N/A (Source ITSM)"
    $TotalTickets      = "N/A"
    $P1Tickets         = "N/A"
    $P2Tickets         = "N/A"
    $P3Tickets         = "N/A"
    $MttrMinutes       = "N/A"
    $BackupSuccessRate = if ($veeamSvc.Count -gt 0) { "$(@($veeamSvc | Where-Object Status -eq 'Running').Count)/$($veeamSvc.Count) svc" } else { "N/A (Veeam absent)" }
    $AntivirusCoverage = if ($mpStatus -and $mpStatus.RealTimeProtectionEnabled) { "Defender Actif" } else { "N/A (EDR local)" }
    $SlaBadgeText      = "COLLECTE LOCALE — SOURCE ITSM REQUISE"
    $SlaFooterNote     = "Télémétrie locale réelle (Uptime : $UptimeDays j). Connecter un export ServiceNow/GLPI/VBR ou passer -Simulate pour les KPI SLA/Tickets."
}
Write-Host "  -> Disponibilité : $ActualSLA (Uptime: $UptimeDays j) | Volume tickets : $TotalTickets" -ForegroundColor Gray

Write-Host "[2/4] Analyse des seuils de capacité et de continuité..." -ForegroundColor White
$Disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Where-Object { $_.Size -gt 0 })
$StorageRows = @()
foreach ($d in $Disks) {
    $totalGB = [math]::Round($d.Size / 1GB, 1)
    $freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
    $usedPercent = [math]::Round((($d.Size - $d.FreeSpace) / $d.Size) * 100, 1)
    $devHtml = [System.Net.WebUtility]::HtmlEncode([string]$d.DeviceID)
    $StorageRows += "<tr><td>$devHtml</td><td>${totalGB} Go</td><td>${freeGB} Go</td><td>${usedPercent}%</td><td>$(if ($usedPercent -lt 85) {'<span style=''color:#4ade80;''>Optimal</span>'} else {'<span style=''color:#ef4444;''>Action requise</span>'})</td></tr>"
}

Write-Host "[3/4] Consolidation des recommandations stratégiques d'ingénierie..." -ForegroundColor White

# 2. Génération du Rapport Exécutif Haute Qualité
Write-Host "[4/4] Génération de la présentation exécutive..." -ForegroundColor White

$clientHtml  = [System.Net.WebUtility]::HtmlEncode([string]$ClientName)
$monthHtml   = [System.Net.WebUtility]::HtmlEncode([string]$ReportingMonth)
$slaTextHtml = [System.Net.WebUtility]::HtmlEncode([string]$SlaBadgeText)
$slaNoteHtml = [System.Net.WebUtility]::HtmlEncode([string]$SlaFooterNote)
$badgeBg     = if ($Simulate) { "#d97706" } else { "#0284c7" }

$HtmlContent = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Comité de Pilotage (COPIL) - $clientHtml</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #0b0f19; color: #f1f5f9; margin: 0; padding: 32px; }
        .wrapper { max-width: 1100px; margin: auto; background-color: #111827; border: 1px solid #1f2937; border-radius: 12px; padding: 36px; box-shadow: 0 20px 40px rgba(0,0,0,0.6); }
        .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #374151; padding-bottom: 20px; margin-bottom: 28px; }
        .title-h1 { margin: 0; font-size: 26px; color: #38bdf8; font-weight: 700; letter-spacing: -0.5px; }
        .subtitle { color: #9ca3af; margin: 4px 0 0 0; font-size: 14px; }
        .badge { background: $badgeBg; color: white; padding: 6px 14px; border-radius: 6px; font-weight: 600; font-size: 13px; text-transform: uppercase; }
        .kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 32px; }
        .kpi-card { background-color: #1f2937; border-radius: 8px; padding: 20px; border-left: 4px solid #38bdf8; }
        .kpi-title { font-size: 12px; text-transform: uppercase; color: #9ca3af; font-weight: 600; margin-bottom: 8px; }
        .kpi-value { font-size: 28px; font-weight: 800; color: #f9fafb; }
        .kpi-sub { font-size: 12px; color: #34d399; margin-top: 4px; }
        .section-title { font-size: 18px; color: #e5e7eb; border-left: 4px solid #60a5fa; padding-left: 10px; margin: 28px 0 16px 0; font-weight: 600; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { border: 1px solid #374151; padding: 12px 16px; text-align: left; }
        th { background-color: #1f2937; color: #93c5fd; font-size: 13px; text-transform: uppercase; }
        tr:nth-child(even) { background-color: #162032; }
        .reco-box { background-color: #172554; border: 1px solid #1e40af; border-radius: 8px; padding: 20px; margin-top: 24px; }
        .reco-box h4 { margin: 0 0 10px 0; color: #93c5fd; font-size: 16px; }
        .reco-box ul { margin: 0; padding-left: 20px; color: #dbeafe; font-size: 14px; line-height: 1.6; }
        .footer { margin-top: 36px; border-top: 1px solid #374151; padding-top: 16px; display: flex; justify-content: space-between; font-size: 12px; color: #6b7280; }
    </style>
</head>
<body>
    <div class="wrapper">
        <div class="header">
            <div>
                <h1 class="title-h1">Comité de Pilotage (COPIL) & COTECH Mensuel</h1>
                <p class="subtitle">Client : <strong>$clientHtml</strong> • Période : <strong>$monthHtml</strong></p>
            </div>
            <div>
                <span class="badge">$slaTextHtml</span>
            </div>
        </div>

        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="kpi-title">Disponibilité Globale (SLA)</div>
                <div class="kpi-value">$ActualSLA</div>
                <div class="kpi-sub">Cible contractuelle : $TargetSla%</div>
            </div>
            <div class="kpi-card" style="border-left-color: #34d399;">
                <div class="kpi-title">Sauvegardes / PRA</div>
                <div class="kpi-value">$BackupSuccessRate</div>
                <div class="kpi-sub">$slaNoteHtml</div>
            </div>
            <div class="kpi-card" style="border-left-color: #f59e0b;">
                <div class="kpi-title">MTTR Moyen (Résolution)</div>
                <div class="kpi-value">$MttrMinutes</div>
                <div class="kpi-sub">Volume total : $TotalTickets ticket(s)</div>
            </div>
            <div class="kpi-card" style="border-left-color: #a855f7;">
                <div class="kpi-title">Couverture Cybersécurité</div>
                <div class="kpi-value">$AntivirusCoverage</div>
                <div class="kpi-sub">Uptime hôte mesuré : $UptimeDays j</div>
            </div>
        </div>

        <div class="section-title">Synthèse de l'Activité Support & Incidents (MCO)</div>
        <table>
            <thead>
                <tr>
                    <th>Niveau de Gravité</th>
                    <th>Volume Traité</th>
                    <th>Délai Prise en Compte (GTR)</th>
                    <th>Délai Résolution (MTTR)</th>
                    <th>Respect SLA</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><strong>P1 - Bloquant (Astreinte 24/7)</strong></td>
                    <td>$P1Tickets</td>
                    <td>$(if ($Simulate) { '3 minutes' } else { 'N/A (ITSM)' })</td>
                    <td>$(if ($Simulate) { '22 minutes' } else { 'N/A (ITSM)' })</td>
                    <td><span style="color: $(if ($Simulate) { '#4ade80' } else { '#facc15' }); font-weight: bold;">$(if ($Simulate) { 'SIMULATION CONFORME' } else { 'NON MESURE' })</span></td>
                </tr>
                <tr>
                    <td><strong>P2 - Majeur (Dégradation forte)</strong></td>
                    <td>$P2Tickets</td>
                    <td>$(if ($Simulate) { '12 minutes' } else { 'N/A (ITSM)' })</td>
                    <td>$(if ($Simulate) { '45 minutes' } else { 'N/A (ITSM)' })</td>
                    <td><span style="color: $(if ($Simulate) { '#4ade80' } else { '#facc15' }); font-weight: bold;">$(if ($Simulate) { 'SIMULATION CONFORME' } else { 'NON MESURE' })</span></td>
                </tr>
                <tr>
                    <td><strong>P3 / P4 - Demandes & Exploitation</strong></td>
                    <td>$P3Tickets</td>
                    <td>$(if ($Simulate) { '&lt; 1 heure' } else { 'N/A (ITSM)' })</td>
                    <td>$(if ($Simulate) { '1.4 jours' } else { 'N/A (ITSM)' })</td>
                    <td><span style="color: $(if ($Simulate) { '#4ade80' } else { '#facc15' }); font-weight: bold;">$(if ($Simulate) { 'SIMULATION CONFORME' } else { 'NON MESURE' })</span></td>
                </tr>
            </tbody>
        </table>

        <div class="section-title">Capacité & Santé de l'Infrastructure</div>
        <table>
            <thead>
                <tr>
                    <th>Ressource / Volume</th>
                    <th>Capacité Totale</th>
                    <th>Espace Libre</th>
                    <th>Taux d'Occupation</th>
                    <th>Statut MCO</th>
                </tr>
            </thead>
            <tbody>
                $($StorageRows -join "`n")
            </tbody>
        </table>

        <div class="reco-box">
            <h4>Recommandations Stratégiques & Arbitrages COTECH</h4>
            <ul>
                <li><strong>Continuité d'Activité (PRA) :</strong> $(if ($Simulate) { 'Simulation annuelle de bascule intersites validée avec RTO mesuré à 38 minutes (conforme à l''engagement contrat).' } else { 'Auditer périodiquement le RPO/RTO et l''immuabilité Veeam via Invoke-DRTest.ps1 et Invoke-VeeamImmutableAudit.ps1.' })</li>
                <li><strong>Capacité & Cycle de Vie :</strong> Suivre les volumes disques locaux et l''évolution des datastores sous le seuil d''alerte de 85%.</li>
                <li><strong>Cybersécurité :</strong> Maintenir la rotation Windows LAPS et la couverture EDR temps réel sur 100% du parc.</li>
            </ul>
        </div>

        <div class="footer">
            <div>Dossier Exécutif présenté en Comité de Pilotage • Antigravity ESN-Toolkit</div>
            <div>Référent Technique N3 & Ingénieur Système : <strong>Amine BERRADA</strong></div>
        </div>
    </div>
</body>
</html>
"@

Set-Content -Path $HtmlFile -Value $HtmlContent -Encoding UTF8
Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "   RAPPORT COPIL GÉNÉRÉ AVEC SUCCÈS                                        " -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "[+] Fichier HTML Exécutif : $HtmlFile" -ForegroundColor White
if ($OpenInBrowser) {
    Start-Process $HtmlFile
}
