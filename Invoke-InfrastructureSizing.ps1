#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-InfrastructureSizing v3.0 - Outil de Dimensionnement & Chiffrage Technique (COPIL / Avant-Vente).
    Évalue l'infrastructure existante et projette les besoins matériels, virtualisation et stockage.

.DESCRIPTION
    1. Inventaire des ressources physiques (CPU cores, RAM Go, Stockage brut et utile)
    2. Calcul de dimensionnement de cluster de virtualisation (N+1 redondance VMware / Nutanix)
    3. Projection de croissance du stockage à 1, 3 et 5 ans (taux annuel 15% / 25%)
    4. Calcul de capacité pour les sauvegardes selon la règle 3-2-1 (Rétention 30 jours + Immuabilité)
    5. Rapport exécutif HTML pour DSI et Comités de Pilotage (COPIL)
#>

[CmdletBinding()]
param(
    [int]$EstimatedVMCount = 10,
    [int]$AnnualGrowthPercent = 20,
    [switch]$OpenReport = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   📊  DIMENSIONNEMENT D'INFRASTRUCTURE & PROJECTION COPIL — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Chiffrage technique, consolidation virtualisation & stockage — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. AUDIT DES RESSOURCES MACHINE / HOTE
Write-Host " [*] Audit des ressources de l'environnement hôte..." -ForegroundColor Yellow
$cpuCores = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
$totalRAMGB = [math]::Round(((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB), 1)
$totalDiskGB = [math]::Round(((Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Measure-Object -Property Size -Sum).Sum / 1GB), 0)
$usedDiskGB = [math]::Round(((Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object { $_.Size - $_.FreeSpace } | Measure-Object -Sum).Sum / 1GB), 0)

Write-Host "  -> CPU Logiques : $cpuCores coeurs" -ForegroundColor Green
Write-Host "  -> RAM Totale   : $totalRAMGB Go" -ForegroundColor Green
Write-Host "  -> Stockage     : $usedDiskGB Go utilisés sur $totalDiskGB Go alloués" -ForegroundColor Green

# 2. PROJECTION DE CROISSANCE STOCKAGE (1, 3, 5 ANS)
Write-Host "`n [*] Calcul des projections de stockage (+ $AnnualGrowthPercent% par an)..." -ForegroundColor Yellow
$year1 = [math]::Round($usedDiskGB * [math]::Pow(1 + ($AnnualGrowthPercent/100), 1), 0)
$year3 = [math]::Round($usedDiskGB * [math]::Pow(1 + ($AnnualGrowthPercent/100), 3), 0)
$year5 = [math]::Round($usedDiskGB * [math]::Pow(1 + ($AnnualGrowthPercent/100), 5), 0)

Write-Host "  -> Croissance estimée : Actuel: $usedDiskGB Go | À 1 an: $year1 Go | À 3 ans: $year3 Go | À 5 ans: $year5 Go" -ForegroundColor Cyan

# 3. DIMENSIONNEMENT CLUSTER VIRTUALISATION (N+1)
Write-Host "`n [*] Dimensionnement d'un cluster haute disponibilité (N+1 Failover)..." -ForegroundColor Yellow
$vCpuPerVM = 2
$ramPerVM  = 8 # Go
$totalRequiredvCPU = $EstimatedVMCount * $vCpuPerVM
$totalRequiredRAM  = $EstimatedVMCount * $ramPerVM

# Avec ratio de consolidation vCPU:pCPU de 3:1
$physicalCoresNeeded = [math]::Ceiling($totalRequiredvCPU / 3)
# N+1 : minimum 2 ou 3 nœuds
$nodesCount = [Math]::Max(3, [math]::Ceiling($totalRequiredRAM / 64) + 1)
$ramPerNode = [math]::Ceiling($totalRequiredRAM / ($nodesCount - 1))

Write-Host "  -> Pour héberger $EstimatedVMCount VMs avec tolérance de panne (N+1) :" -ForegroundColor Green
Write-Host "     * Architecture recommandée : Cluster de $nodesCount nœuds hyperconvergés (ex: Nutanix ou VMware vSphere)" -ForegroundColor Green
Write-Host "     * Dimensionnement par nœud  : 16 Coeurs CPU / $ramPerNode Go RAM minimum" -ForegroundColor Green

# 4. DIMENSIONNEMENT SAUVEGARDE 3-2-1
$backupFullGB = $usedDiskGB
$backupDailyIncrGB = [math]::Round($usedDiskGB * 0.05, 0) # 5% de changement quotidien
$backup30DaysRetentionGB = [math]::Round($backupFullGB + ($backupDailyIncrGB * 30), 0)
$backupWithImmutabilityGB = [math]::Round($backup30DaysRetentionGB * 1.3, 0) # Marge 30%

Write-Host "`n [*] Dimensionnement du stockage de sauvegarde (Règle 3-2-1) :" -ForegroundColor Yellow
Write-Host "  -> Sauvegarde Full initiale     : $backupFullGB Go" -ForegroundColor Cyan
Write-Host "  -> Rétention 30 jours (Incr.)   : $backup30DaysRetentionGB Go" -ForegroundColor Cyan
Write-Host "  -> Capacité préconisée (Dépôt)  : $backupWithImmutabilityGB Go (incluant immutabilité WORM)" -ForegroundColor Green

# 5. GENERATION DU DOSSIER DE DIMENSIONNEMENT COPIL (HTML)
Import-Module "$PSScriptRoot\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
$repDir = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Reports" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
$reportPath = Join-Path $repDir "Dossier-Dimensionnement-Architecture.html"
$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Dossier de Dimensionnement Architecture</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f8fafc; color: #1e293b; padding: 30px; }
        .doc { background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 40px; max-width: 950px; margin: auto; box-shadow: 0 4px 20px rgba(0,0,0,0.06); }
        h1 { color: #0f172a; margin-top: 0; }
        .section-title { color: #0284c7; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px; margin-top: 30px; }
        .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin: 15px 0; }
        .card-stat { background: #f0fdf4; border: 1px solid #bbf7d0; padding: 15px; border-radius: 6px; }
        .stat-val { font-size: 22px; font-weight: bold; color: #15803d; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #e2e8f0; }
        th { background: #0f172a; color: white; }
    </style>
</head>
<body>
    <div class='doc'>
        <h1>DOSSIER DE DIMENSIONNEMENT D'INFRASTRUCTURE IT</h1>
        <p><b>Projet :</b> Évolution d'Infrastructure & Virtualisation | <b>Auteur :</b> Amine BERRADA (Référent Technique N3) | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy')</p>
        
        <h3 class='section-title'>1. Synthèse des Besoins en Virtualisation (Haute Disponibilité N+1)</h3>
        <div class='grid'>
            <div class='card-stat'><div>Périmètre VMs</div><div class='stat-val'>$EstimatedVMCount VMs</div></div>
            <div class='card-stat'><div>Topologie Recommandée</div><div class='stat-val'>Cluster $nodesCount Nœuds</div></div>
            <div class='card-stat'><div>RAM par Nœud</div><div class='stat-val'>$ramPerNode Go RAM</div></div>
        </div>

        <h3 class='section-title'>2. Projection de Croissance du Stockage (+ $AnnualGrowthPercent%/an)</h3>
        <table>
            <thead><tr><th>Horizon</th><th>Données Actives Estimées</th><th>Capacité Préconisée Utile</th></tr></thead>
            <tbody>
                <tr><td>Actuel</td><td>$usedDiskGB Go</td><td>$totalDiskGB Go</td></tr>
                <tr><td>À 1 An</td><td>$year1 Go</td><td>$([math]::Round($year1 * 1.3, 0)) Go</td></tr>
                <tr><td>À 3 Ans</td><td>$year3 Go</td><td>$([math]::Round($year3 * 1.3, 0)) Go</td></tr>
                <tr><td>À 5 Ans</td><td>$year5 Go</td><td>$([math]::Round($year5 * 1.3, 0)) Go</td></tr>
            </tbody>
        </table>

        <h3 class='section-title'>3. Préconisations Sauvegarde & Résilience (Règle 3-2-1)</h3>
        <p>Pour assurer la continuité d'activité avec dépôts immuables durcis (Veeam Backup) :</p>
        <ul>
            <li><b>Capacité de rétention recommandée :</b> $backupWithImmutabilityGB Go d'espace utile dédié.</li>
            <li><b>Immuabilité (Object Lock / Linux Hardened Repository) :</b> Verrouillage 14 à 30 jours anti-ransomware.</li>
            <li><b>Export externe :</b> Réplication hors-site ou vers stockage cloud S3 souverain.</li>
        </ul>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n [OK] Dossier de dimensionnement généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
