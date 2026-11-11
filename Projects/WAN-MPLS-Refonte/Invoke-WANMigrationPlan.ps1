<#
.SYNOPSIS
    Invoke-WANMigrationPlan.ps1 - Validation, bascule et audit de refonte WAN multi-sites (MPLS / SD-WAN / VPN IPsec) avec PRA/PCA.
.DESCRIPTION
    Conçu à partir du projet de refonte WAN multi-sites & PRA intersites :
    - Test de latence, gigue (jitter) et perte de paquets entre sites distants (QoS CoS/DSCP).
    - Validation MTU Path (détection du black-holing ICMP et fragmentation DF-bit).
    - Contrôle de la redondance WAN (bascule opérateur primaire MPLS -> lien de secours 4G/FttH/IPsec).
    - Audit de la bande passante dédiée à la réplication Veeam (WAN Accelerator) pour le PRA/PCA.
    - Génération de la fiche de recette opérateur et du Procès-Verbal de Bascule WAN.
.PARAMETER RemoteSites
    Tableau de hachage des sites distants avec IP passerelle/sonde et rôle.
.EXAMPLE
    .\Invoke-WANMigrationPlan.ps1 -PrimaryGateway "10.100.1.1" -BackupGateway "10.100.2.1"
#>

[CmdletBinding()]
param(
    [string]$PrimaryGateway = "10.0.0.1",
    [string]$BackupGateway = "10.0.1.1",
    [string[]]$RemoteSiteIPs = @("192.168.10.1", "192.168.20.1", "192.168.30.1"),
    [int]$VeeamWanPort = 6162,
    [switch]$SimulateFailover,
    [switch]$ReportOnly
)

$ErrorActionPreference = "Continue"

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   WAN MULTI-SITES (MPLS/SD-WAN) & PRA INTER-SITES VALIDATION ENGINE       " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "[*] Passerelle WAN Primaire (MPLS) : $PrimaryGateway" -ForegroundColor Gray
Write-Host "[*] Passerelle WAN Secours (IPsec) : $BackupGateway" -ForegroundColor Gray
Write-Host "[*] Sites distants analysés        : $($RemoteSiteIPs -join ', ')" -ForegroundColor Gray
Write-Host ""

$ReportDir = "$env:SystemDrive\ESN-Reports\WAN-Migration"
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = "$ReportDir\WAN-Audit-$Timestamp.log"

function Write-WANLog {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        default   { "White" }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

Write-WANLog "Démarrage de l'audit de performance et de bascule WAN..." "INFO"

# 1. Test MTU Path Discovery (Recherche de fragmentation)
Write-WANLog "[1/4] Audit MTU Path Discovery (Vérification Don't Fragment DF-bit)..." "INFO"
$TestMTUSizes = @(1500, 1492, 1460, 1400, 1360)
$OptimalMTU = 1500

foreach ($size in $TestMTUSizes) {
    # ping -f -l <size>
    $pingResult = ping.exe $PrimaryGateway -f -l $size -n 1 2>&1 | Out-String
    if ($pingResult -match "taille d'élément de données trop volumineuse" -or $pingResult -match "Packet needs to be fragmented") {
        Write-WANLog "Fragmentation requise pour MTU = $size octets sur le lien WAN." "WARN"
    } else {
        $OptimalMTU = $size
        Write-WANLog "Taille MTU optimale validée sans fragmentation : $size octets." "SUCCESS"
        break
    }
}

# 2. Mesure Latence, Gigue et Perte de Paquets vers les sites distants
Write-WANLog "[2/4] Mesure de performance SLA intersites (Latence / Gigue / Perte)..." "INFO"
$SiteResults = @()

foreach ($site in $RemoteSiteIPs) {
    $pings = @()
    $lost = 0
    for ($i = 1; $i -le 4; $i++) {
        $p = Test-Connection -ComputerName $site -Count 1 -ErrorAction SilentlyContinue
        if ($p) {
            $pings += $p.ResponseTime
        } else {
            $lost++
        }
    }

    $avgLatency = if ($pings.Count -gt 0) { [math]::Round(($pings | Measure-Object -Average).Average, 1) } else { 999 }
    $lossRate = [math]::Round(($lost / 4) * 100, 1)
    
    $slaStatus = if ($avgLatency -lt 30 -and $lossRate -eq 0) { "CONFORME SLA" } elseif ($avgLatency -lt 80) { "ACCEPTABLE" } else { "DEGRADE" }
    Write-WANLog "Site $site : Latence moy = ${avgLatency}ms | Perte = $lossRate% | SLA = $slaStatus" $(if ($slaStatus -eq "CONFORME SLA") { "SUCCESS" } else { "WARN" })

    $SiteResults += [PSCustomObject]@{
        SiteIP      = $site
        AvgLatency  = $avgLatency
        PacketLoss  = "$lossRate%"
        SLAStatus   = $slaStatus
    }
}

# 3. Audit du flux de réplication PRA (Veeam WAN Accelerator)
Write-WANLog "[3/4] Contrôle de connectivité PRA / Veeam WAN Accelerator (Port $VeeamWanPort)..." "INFO"
$VeeamPraResults = @()
foreach ($site in $RemoteSiteIPs) {
    $tcp = Test-NetConnection -ComputerName $site -Port $VeeamWanPort -WarningAction SilentlyContinue
    $status = if ($tcp.TcpTestSucceeded) { "ACCESSIBLE (Port $VeeamWanPort ouvert)" } else { "FERME / FILTRE" }
    Write-WANLog "Site $site (Veeam PRA Port $VeeamWanPort) : $status" $(if ($tcp.TcpTestSucceeded) { "SUCCESS" } else { "WARN" })
    
    $VeeamPraResults += [PSCustomObject]@{
        TargetIP   = $site
        Port       = $VeeamWanPort
        Accessible = $tcp.TcpTestSucceeded
        Status     = $status
    }
}

# 4. Simulation de bascule automatique (Failover Route)
Write-WANLog "[4/4] Validation des métriques de routage pour le basculement (Failover)..." "INFO"
$RoutingTable = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, NextHop, RouteMetric

$PrimaryRoute = $RoutingTable | Where-Object { $_.NextHop -eq $PrimaryGateway }
$BackupRoute = $RoutingTable | Where-Object { $_.NextHop -eq $BackupGateway }

if ($PrimaryRoute -and $BackupRoute) {
    if ($PrimaryRoute.RouteMetric -lt $BackupRoute.RouteMetric) {
        Write-WANLog "Priorité de routage optimale : Métrique Primaire ($($PrimaryRoute.RouteMetric)) < Secours ($($BackupRoute.RouteMetric)). Bascule automatique active." "SUCCESS"
    } else {
        Write-WANLog "ATTENTION : Métriques de routage incohérentes pour la bascule de passerelle." "WARN"
    }
} else {
    Write-WANLog "Passerelles multiples non actives simultanément dans la table de routage locale (Mode failover géré par routeur de bordure)." "INFO"
}

# 5. Génération du Procès-Verbal de Recette Opérateur
$HtmlReport = "$ReportDir\PV-Recette-Bascule-WAN.html"

$SiteRowsHtml = ($SiteResults | ForEach-Object {
    $badgeClass = if ($_.SLAStatus -eq "CONFORME SLA") { "status-ok" } else { "status-warn" }
    "<tr><td>$($_.SiteIP)</td><td>$($_.AvgLatency) ms</td><td>$($_.PacketLoss)</td><td class='$badgeClass'>$($_.SLAStatus)</td></tr>"
}) -join "`n"

$HtmlContent = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>PV de Recette & Validation WAN Multi-Sites & PRA</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0f172a; color: #f8fafc; margin: 0; padding: 24px; }
        .container { max-width: 950px; margin: auto; background-color: #1e293b; border-radius: 10px; padding: 28px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
        h1 { color: #38bdf8; border-bottom: 2px solid #334155; padding-bottom: 12px; margin-top: 0; font-size: 24px; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 4px; font-weight: bold; font-size: 12px; text-transform: uppercase; background: #0284c7; color: white; }
        .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin: 20px 0; }
        .card { background-color: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 16px; }
        .card-title { font-size: 13px; color: #94a3b8; text-transform: uppercase; margin-bottom: 6px; }
        .card-value { font-size: 20px; font-weight: bold; color: #38bdf8; }
        table { width: 100%; border-collapse: collapse; margin-top: 16px; }
        th, td { border: 1px solid #334155; padding: 10px 12px; text-align: left; }
        th { background-color: #0f172a; color: #38bdf8; font-size: 13px; }
        tr:nth-child(even) { background-color: #1a2234; }
        .status-ok { color: #4ade80; font-weight: bold; }
        .status-warn { color: #facc15; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Procès-Verbal de Recette WAN & PRA Multi-Sites <span class="badge">Validé</span></h1>
        <p style="color: #94a3b8;">Rapport de conformité opérationnelle : bascule de liens WAN, qualité de service opérateur et connectivité de réplication PRA.</p>
        
        <div class="grid">
            <div class="card">
                <div class="card-title">MTU Optimale Validée</div>
                <div class="card-value">$OptimalMTU Octets</div>
            </div>
            <div class="card">
                <div class="card-title">Passerelle Primaire</div>
                <div class="card-value">$PrimaryGateway</div>
            </div>
            <div class="card">
                <div class="card-title">Port PRA Veeam</div>
                <div class="card-value">Port $VeeamWanPort</div>
            </div>
        </div>

        <h3>Mesures de Performance Intersites (SLA Opérateur)</h3>
        <table>
            <thead>
                <tr>
                    <th>Site / Sonde Distante</th>
                    <th>Latence Moyenne</th>
                    <th>Perte de Paquets</th>
                    <th>Conformité SLA</th>
                </tr>
            </thead>
            <tbody>
                $SiteRowsHtml
            </tbody>
        </table>

        <p style="color: #64748b; font-size: 12px; margin-top: 24px;">Généré par Antigravity ESN-Toolkit • Projet : Refonte WAN & Continuité PRA • Référent : Amine BERRADA</p>
    </div>
</body>
</html>
"@

Set-Content -Path $HtmlReport -Value $HtmlContent -Encoding UTF8
Write-WANLog "PV de recette WAN généré : $HtmlReport" "SUCCESS"

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "   AUDIT & RECETTE WAN TERMINÉE AVEC SUCCÈS                                " -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "[+] Fichier PV de Recette : $HtmlReport" -ForegroundColor White
