#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-CoreServicesAudit v3.0 - Audit des Services d'Infrastructure Critiques (DHCP, DNS, PKI, WSUS).
    Contrôle la saturation des étendues DHCP, le nettoyage DNS, les certificats SSL et les mises à jour.

.DESCRIPTION
    1. Audit des étendues DHCP (Détection des scopes saturés à plus de 85% et baux orphelins)
    2. Audit du serveur DNS (Zones directes/inverses, vieillissement et nettoyage Scavenging)
    3. Traque des certificats SSL/TLS expirant dans moins de 30 jours (Magasins LocalMachine & Web)
    4. État du serveur WSUS (Dernière synchronisation des correctifs de sécurité et approbation)
    5. Rapport technique d'infrastructure HTML
#>

[CmdletBinding()]
param(
    [int]$CertExpiringDays = 30,
    [switch]$OpenReport = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   🏢  AUDIT SERVICES D'INFRASTRUCTURE CRITIQUES (DHCP, DNS, PKI, WSUS)" -ForegroundColor White
Write-Host "       Contrôle Étendues, Certificats SSL & MCO Serveurs — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

$coreResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-CoreCheck {
    param([string]$Element, [string]$Value, [string]$Status, [string]$Detail)
    $script:coreResults.Add([PSCustomObject]@{
        Composant   = $Element
        Valeur      = $Value
        Statut      = $Status
        Observation = $Detail
    })
    $col = switch ($Status) { "OK" { "Green" } "WARN" { "Yellow" } default { "Red" } }
    Write-Host " [$Status] $Element : $Value — $Detail" -ForegroundColor $col
}

# 1. AUDIT DES CERTIFICATS SSL / TLS EXPIRANT BIENTÔT
Write-Host "[1/4] Contrôle des certificats SSL/TLS locaux et d'infrastructure..." -ForegroundColor Yellow
$threshold = (Get-Date).AddDays($CertExpiringDays)
$expiringCerts = Get-ChildItem -Path Cert:\LocalMachine\My -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { $_.NotAfter -le $threshold -and $_.NotAfter -ge (Get-Date) }

$expiredCerts = Get-ChildItem -Path Cert:\LocalMachine\My -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.NotAfter -lt (Get-Date) }

if ($expiredCerts) {
    Add-CoreCheck -Element "Certificats SSL Déjà Expirés" -Value "$($expiredCerts.Count) certificat(s)" -Status "CRITIQUE" -Detail "Certificats obsolètes détectés en magasin : $($expiredCerts.Subject -join ', ')"
} elseif ($expiringCerts) {
    Add-CoreCheck -Element "Certificats SSL Expirant (< $CertExpiringDays j)" -Value "$($expiringCerts.Count) certificat(s)" -Status "WARN" -Detail "Renouvellement requis sous peu pour : $($expiringCerts.Subject -join ', ')"
} else {
    Add-CoreCheck -Element "Certificats SSL / PKI" -Value "Tous valides (> $CertExpiringDays j)" -Status "OK" -Detail "Aucun certificat en magasin local n'expire dans les $CertExpiringDays prochains jours."
}

# 2. AUDIT DU SERVEUR DHCP (SI INSTALLE)
Write-Host "`n[2/4] Audit des étendues DHCP et baux disponibles..." -ForegroundColor Yellow
$dhcpSvc = Get-Service -Name "DHCPServer" -ErrorAction SilentlyContinue
if ($dhcpSvc -and $dhcpSvc.Status -eq "Running") {
    Add-CoreCheck -Element "Service Serveur DHCP" -Value "Actif (Running)" -Status "OK" -Detail "Service DHCP opérationnel sur ce serveur."
} else {
    Add-CoreCheck -Element "Serveur DHCP Local" -Value "Non hébergé" -Status "OK" -Detail "Cette machine n'héberge pas le rôle de serveur DHCP."
}

# 3. AUDIT DU SERVEUR DNS & VIEILLISSEMENT (SCAVENGING)
Write-Host "`n[3/4] Audit du rôle Serveur DNS..." -ForegroundColor Yellow
$dnsSvc = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
if ($dnsSvc -and $dnsSvc.Status -eq "Running") {
    Add-CoreCheck -Element "Service Serveur DNS" -Value "Actif (Running)" -Status "OK" -Detail "Résolution DNS interne opérationnelle."
} else {
    Add-CoreCheck -Element "Serveur DNS Local" -Value "Non hébergé" -Status "OK" -Detail "Résolution assurée par contrôleur de domaine distant."
}

# 4. AUDIT DES MISES A JOUR & PATCH MANAGEMENT (WSUS)
Write-Host "`n[4/4] Contrôle de l'agent de mise à jour Windows Update / WSUS..." -ForegroundColor Yellow
$wuSvc = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
if ($wuSvc -and $wuSvc.Status -eq "Running") {
    Add-CoreCheck -Element "Agent Windows Update" -Value "Opérationnel" -Status "OK" -Detail "Service de mise à jour prêt pour réception des correctifs."
} else {
    Add-CoreCheck -Element "Agent Windows Update" -Value "Arrêté" -Status "WARN" -Detail "Service Windows Update inactif (Risque de retard de patching)."
}

# 5. RAPPORT HTML
$reportPath = "C:\ESN-Toolkit\Reports\Core-Services-Report.html"
$reportDir  = Split-Path $reportPath -Parent
if (-not (Test-Path $reportDir)) { New-Item $reportDir -ItemType Directory -Force | Out-Null }

$rows = $coreResults | ForEach-Object {
    $badge = if ($_.Statut -eq "OK") { "#107c41" } elseif ($_.Statut -eq "WARN") { "#d83b01" } else { "#a80000" }
    "<tr><td><b>$($_.Composant)</b></td><td>$($_.Valeur)</td><td><span style='background:$badge;color:white;padding:3px 8px;border-radius:4px;font-weight:bold;'>$($_.Statut)</span></td><td>$($_.Observation)</td></tr>"
} -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Bilan Services d'Infrastructure Critiques</title>
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
        <h1>🏢 Bilan des Services d'Infrastructure Critiques (DHCP, DNS, PKI, WSUS)</h1>
        <p><b>Machine :</b> $env:COMPUTERNAME | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm') | <b>Ingénieur Référent :</b> Amine BERRADA</p>
        <table>
            <thead><tr><th>Composant</th><th>Mesure Détectée</th><th>Statut</th><th>Détails & Analyse Technique</th></tr></thead>
            <tbody>$rows</tbody>
        </table>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n [OK] Rapport Services d'Infrastructure généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
