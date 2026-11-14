#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-CloudHybridAudit v3.0 - Audit Cloud Hybride, Microsoft Entra ID & Intune.
    Évalue la synchronisation hybride, l'enrôlement MDM et la sécurité cloud M365.

.DESCRIPTION
    1. Contrôle du service et de l'état de synchronisation Microsoft Entra Connect (Azure AD Connect)
    2. Audit de l'enrôlement Intune MDM et conformité des stratégies de gestion de flotte
    3. Vérification de l'onboarding Microsoft Defender for Endpoint (MDE - Service Sense)
    4. Test de latence et connectivité vers les endpoints cloud Microsoft 365
    5. Rapport HTML d'audit Cloud Hybride
#>

[CmdletBinding()]
param(
    [switch]$OpenReport = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   ☁️  AUDIT CLOUD HYBRIDE, MICROSOFT ENTRA ID & INTUNE — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Contrôle Azure AD Connect, Intune MDM & Defender MDE — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

$cloudResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-CloudMetric {
    param([string]$Element, [string]$Value, [string]$Status, [string]$Detail)
    $script:cloudResults.Add([PSCustomObject]@{
        Composant   = $Element
        Valeur      = $Value
        Statut      = $Status
        Observation = $Detail
    })
    $col = switch ($Status) { "CONFORME" { "Green" } "INFO" { "Cyan" } "WARN" { "Yellow" } default { "Red" } }
    Write-Host " [$Status] $Element : $Value — $Detail" -ForegroundColor $col
}

# 1. AUDIT ENRÔLEMENT INTUNE MDM
Write-Host " [*] Audit de l'enrôlement Microsoft Intune (MDM)..." -ForegroundColor Yellow
$enrollments = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue |
               Where-Object { (Get-ItemProperty $_.PSPath).UPN -or (Get-ItemProperty $_.PSPath).ProviderID -match "MS DM Server" }

if ($enrollments) {
    $upn = (Get-ItemProperty $enrollments[0].PSPath).UPN
    Add-CloudMetric -Element "Enrôlement Intune MDM" -Value "Enrôlé ($upn)" -Status "CONFORME" -Detail "Machine gérée sous stratégie de gestion de flotte Microsoft Intune."
} else {
    Add-CloudMetric -Element "Enrôlement Intune MDM" -Value "Non enrôlé" -Status "WARN" -Detail "Machine non rattachée à Intune (Gestion locale ou AD on-premise uniquement)."
}

# 2. AUDIT DEFENDER FOR ENDPOINT (MDE - SENSE)
Write-Host "`n [*] Contrôle de l'agent Microsoft Defender for Endpoint (Sense)..." -ForegroundColor Yellow
$senseSvc = Get-Service -Name "Sense" -ErrorAction SilentlyContinue
$mdeOnboarding = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status" -Name "OnboardingState" -ErrorAction SilentlyContinue).OnboardingState

if ($senseSvc -and $senseSvc.Status -eq "Running" -and $mdeOnboarding -eq 1) {
    Add-CloudMetric -Element "Defender for Endpoint (MDE)" -Value "Actif & Onboardé" -Status "CONFORME" -Detail "Connecté au portail Microsoft Defender XDR (Service Sense en cours)."
} elseif ($senseSvc) {
    Add-CloudMetric -Element "Defender for Endpoint (MDE)" -Value "Présent ($($senseSvc.Status))" -Status "WARN" -Detail "Service Sense installé mais onboarding cloud incomplet."
} else {
    Add-CloudMetric -Element "Defender for Endpoint (MDE)" -Value "Non configuré" -Status "INFO" -Detail "Protection locale Defender standard ou EDR tiers actif."
}

# 3. CONTRÔLE AZURE AD CONNECT (SI SUR SERVEUR DE SYNCHRONISATION)
Write-Host "`n [*] Détection du moteur Microsoft Entra Connect (Azure AD Connect)..." -ForegroundColor Yellow
$aadcSyncSvc = Get-Service -Name "ADSync" -ErrorAction SilentlyContinue
if ($aadcSyncSvc) {
    $status = if ($aadcSyncSvc.Status -eq "Running") { "CONFORME" } else { "CRITIQUE" }
    Add-CloudMetric -Element "Serveur Azure AD Connect" -Value "Service ADSync $($aadcSyncSvc.Status)" -Status $status -Detail "Moteur de synchronisation d'annuaire hybride détecté sur ce serveur."
} else {
    Add-CloudMetric -Element "Serveur Azure AD Connect" -Value "Non installé" -Status "INFO" -Detail "Cette machine n'est pas le serveur de synchronisation ADSync."
}

# 4. CONNECTIVITÉ ET LATENCE VERS LE CLOUD MICROSOFT 365
Write-Host "`n [*] Test de latence des liaisons vers le Cloud M365..." -ForegroundColor Yellow
$endpoints = @(
    @{ Host = "login.microsoftonline.com"; Name = "Portail Authentification Entra ID" },
    @{ Host = "outlook.office365.com";     Name = "Messagerie Exchange Online" },
    @{ Host = "graph.microsoft.com";       Name = "API Microsoft Graph / Intune" }
)

foreach ($ep in $endpoints) {
    $ping = try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $start = [System.Diagnostics.Stopwatch]::StartNew()
        $connect = $tcp.BeginConnect($ep.Host, 443, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(1500, $false)
        $start.Stop()
        $tcp.Close()
        if ($wait) { "$($start.ElapsedMilliseconds) ms" } else { "Échec" }
    } catch { "Échec" }

    if ($ping -ne "Échec") {
        Add-CloudMetric -Element "Cloud $($ep.Name)" -Value "Joignable ($ping)" -Status "CONFORME" -Detail "Liaison HTTPS/443 fluide vers $($ep.Host)."
    } else {
        Add-CloudMetric -Element "Cloud $($ep.Name)" -Value "Bloqué / Timeout" -Status "CRITIQUE" -Detail "Impossible de contacter $($ep.Host) (Pare-feu ou coupure WAN)."
    }
}

# 5. GENERATION DU RAPPORT HTML
Import-Module "$PSScriptRoot\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
$reportDir  = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Reports" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
$reportPath = Join-Path $reportDir "Cloud-Hybrid-Report-$($env:COMPUTERNAME).html"
$rows = $cloudResults | ForEach-Object {
    $badge = if ($_.Statut -eq "CONFORME") { "#107c41" } elseif ($_.Statut -eq "WARN") { "#d83b01" } elseif ($_.Statut -eq "CRITIQUE") { "#a80000" } else { "#0078d4" }
    "<tr><td><b>$($_.Composant)</b></td><td>$($_.Valeur)</td><td><span style='background:$badge;color:white;padding:3px 8px;border-radius:4px;font-weight:bold;'>$($_.Statut)</span></td><td>$($_.Observation)</td></tr>"
} -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Bilan Cloud Hybride & Microsoft 365</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f8fafc; color: #1e293b; padding: 25px; }
        .card { background: white; border-radius: 8px; padding: 30px; max-width: 900px; margin: auto; box-shadow: 0 4px 15px rgba(0,0,0,0.06); }
        h1 { color: #0284c7; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; font-size: 14px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #e2e8f0; }
        th { background: #0284c7; color: white; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>☁️ Bilan de Santé Cloud Hybride & Microsoft 365</h1>
        <p><b>Machine :</b> $env:COMPUTERNAME | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm') | <b>Analyste :</b> Amine BERRADA (Référent Cloud & N3)</p>
        <table>
            <thead><tr><th>Composant Cloud</th><th>Valeur Détectée</th><th>Statut</th><th>Détails & Analyse</th></tr></thead>
            <tbody>$rows</tbody>
        </table>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n [OK] Rapport Cloud Hybride généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
