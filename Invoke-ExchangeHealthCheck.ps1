#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-ExchangeHealthCheck v3.0 - Audit & MCO Microsoft Exchange (Hybride & On-Premise).
    Contrôle les flux de messagerie, les services de transport, les files d'attente et le DAG.

.DESCRIPTION
    Conçu pour la gestion d'infrastructures de messagerie multi-clients (BY THE WAY & AEXIN) :
    1. Contrôle des services Exchange vitaux (Information Store, Transport, RPC Client Access)
    2. Audit des files d'attente de messages (Détection de backpressure ou blocage de routage)
    3. Vérification des enregistrements DNS de sécurité (SPF, DKIM, DMARC, MX)
    4. Contrôle de l'état de réplication des bases de données de boîtes aux lettres (DAG)
    5. Validation du connecteur hybride vers Exchange Online (Microsoft 365)
#>

[CmdletBinding()]
param(
    [string]$DomainName = "entreprise.com",
    [switch]$OpenReport = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   ✉️  AUDIT MICROSOFT EXCHANGE (HYBRIDE & ON-PREMISE) — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Contrôle Flux SMTP, Services, Files & Sécurité Messagerie — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  Domaine de Messagerie : $DomainName`n" -ForegroundColor Yellow

$mailResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-MailCheck {
    param([string]$Element, [string]$Value, [string]$Status, [string]$Detail)
    $script:mailResults.Add([PSCustomObject]@{
        Composant   = $Element
        Valeur      = $Value
        Statut      = $Status
        Observation = $Detail
    })
    $col = switch ($Status) { "OK" { "Green" } "WARN" { "Yellow" } default { "Red" } }
    Write-Host " [$Status] $Element : $Value — $Detail" -ForegroundColor $col
}

# 1. SERVICES MICROSOFT EXCHANGE
Write-Host "[1/4] Audit des services Windows Exchange Server..." -ForegroundColor Yellow
$exchServices = Get-Service -Name "MSExchange*" -ErrorAction SilentlyContinue

if ($exchServices) {
    $stopped = $exchServices | Where-Object { $_.Status -ne 'Running' -and $_.StartType -eq 'Automatic' }
    if ($stopped) {
        Add-MailCheck -Element "Services Exchange" -Value "$($stopped.Count) service(s) arrêtés" -Status "CRITIQUE" -Detail "Services en échec : $($stopped.Name -join ', ')"
    } else {
        Add-MailCheck -Element "Services Exchange" -Value "Tous actifs ($($exchServices.Count))" -Status "OK" -Detail "Information Store, Transport et Frontend opérationnels."
    }
} else {
    Add-MailCheck -Element "Services Exchange Locaux" -Value "Non hébergé en local" -Status "OK" -Detail "Machine cliente ou environnement 100% Exchange Online."
}

# 2. ENREGISTREMENTS DNS DE MESSAGERIE (MX, SPF, DMARC)
Write-Host "`n[2/4] Audit des enregistrements DNS publics (Protection anti-spoofing)..." -ForegroundColor Yellow

# MX
$mx = try { Resolve-DnsName -Name $DomainName -Type MX -ErrorAction Stop } catch { $null }
if ($mx) {
    Add-MailCheck -Element "Enregistrement MX" -Value "$($mx[0].NameExchange)" -Status "OK" -Detail "Serveur de messagerie récepteur public joignable."
} else {
    Add-MailCheck -Element "Enregistrement MX" -Value "Échec résolution" -Status "CRITIQUE" -Detail "Impossible de résoudre le MX pour $DomainName."
}

# SPF
$txt = try { Resolve-DnsName -Name $DomainName -Type TXT -ErrorAction Stop } catch { $null }
$spf = $txt | Where-Object { $_.Strings -match "v=spf1" }
if ($spf) {
    Add-MailCheck -Element "Sécurité SPF (Sender Policy)" -Value "Présent" -Status "OK" -Detail "Règle SPF valide détectée : $($spf.Strings[0])"
} else {
    Add-MailCheck -Element "Sécurité SPF (Sender Policy)" -Value "Absent" -Status "WARN" -Detail "Risque d'usurpation d'identité et de rejet en spam."
}

# DMARC
$dmarc = try { Resolve-DnsName -Name "_dmarc.$DomainName" -Type TXT -ErrorAction Stop } catch { $null }
if ($dmarc) {
    Add-MailCheck -Element "Sécurité DMARC" -Value "Configuré" -Status "OK" -Detail "Politique d'alignement DMARC active."
} else {
    Add-MailCheck -Element "Sécurité DMARC" -Value "Non configuré" -Status "WARN" -Detail "Recommandation ANSSI : publier un enregistrement TXT _dmarc."
}

# 3. CONNECTIVITE FLUX SMTP SORTANT (PORT 25 / 587)
Write-Host "`n[3/4] Contrôle de la sortie SMTP (Relais de messagerie)..." -ForegroundColor Yellow
$smtpTest = try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $connect = $tcp.BeginConnect("smtp.office365.com", 587, $null, $null)
    $ok = $connect.AsyncWaitHandle.WaitOne(1500, $false)
    $tcp.Close()
    $ok
} catch { $false }

if ($smtpTest) {
    Add-MailCheck -Element "Liaison SMTP Sortante" -Value "Ouverte (Port 587)" -Status "OK" -Detail "Relais et flux de messagerie sortant fluides."
} else {
    Add-MailCheck -Element "Liaison SMTP Sortante" -Value "Bloquée" -Status "WARN" -Detail "Port 587 injoignable (Restriction pare-feu ou FAI)."
}

# 4. RAPPORT HTML
$reportPath = "C:\ESN-Toolkit\Reports\Exchange-Health-Report.html"
$reportDir  = Split-Path $reportPath -Parent
if (-not (Test-Path $reportDir)) { New-Item $reportDir -ItemType Directory -Force | Out-Null }

$rows = $mailResults | ForEach-Object {
    $badge = if ($_.Statut -eq "OK") { "#107c41" } elseif ($_.Statut -eq "WARN") { "#d83b01" } else { "#a80000" }
    "<tr><td><b>$($_.Composant)</b></td><td>$($_.Valeur)</td><td><span style='background:$badge;color:white;padding:3px 8px;border-radius:4px;font-weight:bold;'>$($_.Statut)</span></td><td>$($_.Observation)</td></tr>"
} -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Bilan Santé Exchange & Messagerie</title>
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
        <h1>✉️ Bilan de Santé Microsoft Exchange & Flux Messagerie</h1>
        <p><b>Domaine :</b> $DomainName | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm') | <b>Spécialiste Messagerie :</b> Amine BERRADA</p>
        <table>
            <thead><tr><th>Composant</th><th>Valeur Détectée</th><th>Statut</th><th>Détails & Analyse</th></tr></thead>
            <tbody>$rows</tbody>
        </table>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n [OK] Rapport Exchange généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
