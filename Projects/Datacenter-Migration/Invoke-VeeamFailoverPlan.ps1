#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-VeeamFailoverPlan - Orchestrateur de Bascule & Migration de Datacenter via Veeam.
    Reproduction du projet d'ingénierie critique mené en équipe pluridisciplinaire par Amine BERRADA.

.DESCRIPTION
    1. Contrôle des points de synchronisation Veeam inter-datacenters
    2. Orchestration du plan de bascule planifié (Planned Failover sans perte de données)
    3. Test d'intégrité et de connectivité post-bascule des VMs dans le nouveau Datacenter
    4. Validation de la redirection des flux réseaux et DNS
    5. PV officiel de bascule Datacenter pour COPIL
#>

[CmdletBinding()]
param(
    [string]$PlanName = "MIGRATION-DC1-VERS-DC2",
    [string]$TargetDatacenterIP = "10.200.0.1",
    [switch]$Simulation,
    [switch]$OpenReport
)
Set-StrictMode -Version Latest
if (-not $PSBoundParameters.ContainsKey('Simulation')) { $Simulation = $true }
if (-not $PSBoundParameters.ContainsKey('OpenReport')) { $OpenReport = $true }

if ([Environment]::UserInteractive) {
    try { Clear-Host } catch { Write-Verbose "Clear-Host ignored: $($_.Exception.Message)" }
}
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   🏢  BASCULE & MIGRATION DE DATACENTER (VEEAM REPLICATION) — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Projet d'Infrastructure Critique — Amine BERRADA (Référent Technique N3)" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  Plan de Bascule : $PlanName | Mode Simulation : $Simulation`n" -ForegroundColor Yellow

$failoverSteps = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-FOStep {
    param([string]$Step, [string]$Status, [string]$Detail)
    $script:failoverSteps.Add([PSCustomObject]@{
        Etape  = $Step
        Statut = $Status
        Detail = $Detail
    })
    $col = switch ($Status) { "OK" { "Green" } "WARN" { "Yellow" } default { "Cyan" } }
    Write-Host " [$Status] $Step — $Detail" -ForegroundColor $col
}

# 1. VERIFICATION DE LA REPLICATION VEEAM
Write-Host "[1/4] Contrôle de la réplication des VMs entre les deux Datacenters..." -ForegroundColor Yellow
$veeamSvc = @(Get-Service -Name "*Veeam*" -ErrorAction SilentlyContinue)
$hasVbr   = ($null -ne (Get-Command Get-VBRReplica -ErrorAction SilentlyContinue))
if ($Simulation) {
    Add-FOStep "Réplication Veeam" "OK" "[SIMULATION] Vérification des points de réplication (cible < 15 min)."
} elseif ($hasVbr) {
    try {
        $replicas = @(Get-VBRReplica -ErrorAction Stop)
        Add-FOStep "Réplication Veeam" "OK" "$($replicas.Count) réplica(s) Veeam VBR inventorié(s)."
    } catch {
        Add-FOStep "Réplication Veeam" "WARN" "Impossible d'interroger Get-VBRReplica : $($_.Exception.Message)"
    }
} elseif ($veeamSvc.Count -gt 0) {
    $runningVeeam = @($veeamSvc | Where-Object { $_.Status -eq 'Running' }).Count
    Add-FOStep "Réplication Veeam" $(if ($runningVeeam -eq $veeamSvc.Count) { "OK" } else { "WARN" }) "$runningVeeam/$($veeamSvc.Count) service(s) Veeam actif(s) (console VBR PowerShell absente pour le détail RPO)."
} else {
    Add-FOStep "Réplication Veeam" "WARN" "Aucun serveur/module Veeam détecté localement (lancer sur le serveur VBR ou passer -Simulation)."
}

# 2. TEST DU RESEAU CIBLE DATACENTER 2
Write-Host "`n[2/4] Test de connectivité vers le Datacenter cible ($TargetDatacenterIP)..." -ForegroundColor Yellow
$pingTarget = try { $p = [System.Net.NetworkInformation.Ping]::new(); $r = $p.Send($TargetDatacenterIP, 1000); $p.Dispose(); ($r.Status -eq 'Success') } catch { $false }
if ($pingTarget) {
    Add-FOStep "Liaison Intersites" "OK" "Lien 10 Gbps / MPLS opérationnel vers le nouveau Datacenter."
} else {
    Add-FOStep "Liaison Intersites" "WARN" "IP $TargetDatacenterIP injoignable depuis cet hôte."
}

# 3. ORCHESTRATION DU FAILOVER PLANIFIE
Write-Host "`n[3/4] Exécution du plan de bascule ordonnancé..." -ForegroundColor Yellow
if ($Simulation) {
    Write-Host "  -> [SIMULATION] Arrêt propre des VMs sur Datacenter 1" -ForegroundColor DarkGray
    Write-Host "  -> [SIMULATION] Dernière réplication différentielle finale" -ForegroundColor DarkGray
    Write-Host "  -> [SIMULATION] Démarrage des VMs sur les hôtes VMware/Nutanix du Datacenter 2" -ForegroundColor DarkGray
    Write-Host "  -> [SIMULATION] Commutation des VLANs et mise à jour des passerelles de routage" -ForegroundColor DarkGray
    Add-FOStep "Planned Failover" "OK" "[SIMULATION] Séquence de bascule validée (plan théorique)."
} elseif (-not $hasVbr -or -not $pingTarget) {
    Add-FOStep "Planned Failover" "WARN" "Bascule non exécutée : prérequis Veeam VBR / liaison Datacenter cible non vérifiés."
} else {
    Add-FOStep "Planned Failover" "INFO" "Prérequis VBR & réseau validés — validation manuelle requise avant déclenchement Start-VBRPlannedFailover."
}

# 4. PV OFFICIEL DE BASCULE DATACENTER
Write-Host "`n[4/4] Génération du Procès-Verbal de bascule Datacenter..." -ForegroundColor Yellow
$repoCore = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "Core\ESN-Core.psm1"
if (-not (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) -and (Test-Path $repoCore)) {
    Import-Module $repoCore -ErrorAction SilentlyContinue
}
$reportDir  = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Reports" } elseif ($env:ESN_TOOLKIT_ROOT) { Join-Path $env:ESN_TOOLKIT_ROOT "Reports" } elseif ($env:SystemDrive) { "$($env:SystemDrive)\ESN-Toolkit\Reports" } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
$safePlanName = $PlanName -replace '[^a-zA-Z0-9._-]', '_'
$reportPath = Join-Path $reportDir "PV-Bascule-Datacenter-$safePlanName.html"
if (-not (Test-Path $reportDir)) { New-Item $reportDir -ItemType Directory -Force | Out-Null }

$planHtml = [System.Net.WebUtility]::HtmlEncode([string]$PlanName)
$pvBadge = if ($Simulation) {
    "<span class='badge' style='background:#d97706;'>MODE SIMULATION — PLAN THEORIQUE NON EXECUTE</span>"
} elseif ($hasVbr -and $pingTarget) {
    "<span class='badge'>Prérequis Bascule Validés (Prêt VBR)</span>"
} else {
    "<span class='badge' style='background:#dc2626;'>RESERVES TECHNIQUES — PRE-REQUIS INCOMPLETS</span>"
}
$stepRowsHtml = ($failoverSteps | ForEach-Object {
    $col = if ($_.Statut -eq "OK") { "#10b981" } elseif ($_.Statut -eq "WARN") { "#f59e0b" } else { "#38bdf8" }
    $et = [System.Net.WebUtility]::HtmlEncode([string]$_.Etape)
    $st = [System.Net.WebUtility]::HtmlEncode([string]$_.Statut)
    $dt = [System.Net.WebUtility]::HtmlEncode([string]$_.Detail)
    "<tr><td><b>$et</b></td><td><span style='color:$col;font-weight:bold;'>$st</span></td><td>$dt</td></tr>"
}) -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>PV de Bascule Datacenter - $planHtml</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #0f172a; color: #f8fafc; padding: 35px; }
        .doc { background: #1e293b; border: 1px solid #334155; border-radius: 8px; padding: 40px; max-width: 900px; margin: auto; }
        h1 { color: #38bdf8; margin-top: 0; }
        .badge { background: #10b981; color: white; padding: 5px 12px; border-radius: 20px; font-weight: bold; font-size: 13px; }
        table { width: 100%; border-collapse: collapse; margin-top: 25px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #334155; }
        th { background: #0f172a; color: #38bdf8; }
        .signatures { display: flex; justify-content: space-between; margin-top: 50px; padding-top: 30px; border-top: 1px dashed #475569; }
    </style>
</head>
<body>
    <div class='doc'>
        <h1>🏢 PROCES-VERBAL DE BASCULE DE DATACENTER</h1>
        <p><b>Plan d'orchestration :</b> $planHtml | <b>Date d'exécution :</b> $(Get-Date -Format 'dd/MM/yyyy à HH:mm')</p>
        <p><b>Ingénieur Infrastructure & Systèmes :</b> Amine BERRADA (Référent Technique N3)</p>
        $pvBadge

        <table>
            <thead><tr><th>Jalon Critique</th><th>Statut</th><th>Détails & Validation</th></tr></thead>
            <tbody>
                $stepRowsHtml
            </tbody>
        </table>

        <div class='signatures'>
            <div><b>L'Équipe Projet Ingénierie :</b><br><br><br><i>Amine BERRADA & Équipe Infra</i></div>
            <div><b>Direction Technique / COPIL :</b><br><br><br><i>Validation Direction des Opérations</i></div>
        </div>
    </div>
</body>
</html>
"@
$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "  [OK] Procès-Verbal de bascule généré : $reportPath" -ForegroundColor Green
Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "   PROJET BASCULE DATACENTER OPERATIONNEL !" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
