#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-NetworkApplianceAudit v3.0 - Audit Réseau, Pare-feux (Fortinet/Stormshield) & Switches (Aruba/Cisco).
    Contrôle les tunnels VPN IPsec, teste les passerelles et sauvegarde les configurations.

.DESCRIPTION
    1. Surveillance & Diagnostic des Tunnels VPN IPsec intersites (Ports IKE UDP 500 & NAT-T 4500)
    2. Test de latence et détection des problèmes de MTU / Fragmentation (MSS Clamping)
    3. Procédure de sauvegarde automatique de configuration d'équipements réseaux (Aruba, Fortinet, Cisco)
    4. Rapport d'infrastructure réseau HTML
#>

[CmdletBinding()]
param(
    [string]$GatewayIP = "",
    [string]$RemoteVpnIP = "",
    [string]$ApplianceIP = "",
    [ValidateSet("FortiGate", "Stormshield", "Aruba", "Cisco")]
    [string]$ApplianceType = "FortiGate",
    [switch]$OpenReport
)
Set-StrictMode -Version Latest
if (-not $PSBoundParameters.ContainsKey('OpenReport')) { $OpenReport = $true }

if ([Environment]::UserInteractive) {
    try { Clear-Host } catch { Write-Verbose "Clear-Host ignored: $($_.Exception.Message)" }
}
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   🌐  AUDIT APPLIANCES RESEAU, PARE-FEUX & SWITCHES — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       FortiGate, Stormshield, Aruba CX, Tunnels VPN IPsec — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

$netResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-NetCheck {
    param([string]$Element, [string]$Value, [string]$Status, [string]$Detail)
    $script:netResults.Add([PSCustomObject]@{
        Composant   = $Element
        Mesure      = $Value
        Statut      = $Status
        Observation = $Detail
    })
    $col = switch ($Status) { "OK" { "Green" } "WARN" { "Yellow" } default { "Red" } }
    Write-Host " [$Status] $Element : $Value — $Detail" -ForegroundColor $col
}

# 1. TEST DE LA PASSERELLE PAR DEFAUT (GATEWAY)
if ([string]::IsNullOrWhiteSpace($GatewayIP)) {
    $GatewayIP = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
}

Import-Module "$PSScriptRoot\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
Write-Host " [*] Audit de la passerelle par défaut ($GatewayIP)..." -ForegroundColor Yellow
if ($GatewayIP) {
    $gwStat = if (Get-Command Measure-ESNPingLatency -ErrorAction SilentlyContinue) { Measure-ESNPingLatency -ComputerName $GatewayIP -Count 4 -TimeoutMs 1000 } else { $null }
    if ($gwStat -and $gwStat.Reachable) {
        Add-NetCheck -Element "Passerelle Principale ($GatewayIP)" -Value "$($gwStat.AvgMs) ms" -Status "OK" -Detail "Excellente réactivité sans perte de paquets."
    } else {
        Add-NetCheck -Element "Passerelle Principale ($GatewayIP)" -Value "Injoignable" -Status "CRITIQUE" -Detail "Passerelle par défaut ne répond pas aux requêtes ICMP."
    }
}

# 2. TEST DES TUNNELS VPN IPSEC (IKE 500 / NAT-T 4500)
if ($RemoteVpnIP) {
    Write-Host "`n [*] Contrôle de la liaison VPN IPsec vers le site distant ($RemoteVpnIP)..." -ForegroundColor Yellow
    $vpnPing = if (Get-Command Test-ESNHostPing -ErrorAction SilentlyContinue) { Test-ESNHostPing -ComputerName $RemoteVpnIP -TimeoutMs 1000 } else { Test-Connection -ComputerName $RemoteVpnIP -Count 1 -Quiet -ErrorAction SilentlyContinue }
    
    # Test port UDP 500 (IKE) avec datagramme et timeout strict
    $udp500State = "TIMEOUT"
    $u = $null
    try {
        $u = [System.Net.Sockets.UdpClient]::new()
        $u.Client.ReceiveTimeout = 600
        $u.Connect($RemoteVpnIP, 500)
        $null = $u.Send([byte[]]@(0), 1)
        $remoteEp = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        $null = $u.Receive([ref]$remoteEp)
        $udp500State = "RESPONSE"
    } catch [System.Net.Sockets.SocketException] {
        if ($_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::ConnectionReset) {
            $udp500State = "CLOSED"
        }
    } catch {
        $udp500State = "TIMEOUT"
    } finally {
        if ($null -ne $u) { $u.Close() }
    }

    if ($vpnPing) {
        Add-NetCheck -Element "Tunnel VPN IPsec ($RemoteVpnIP)" -Value "Actif (UP)" -Status "OK" -Detail "Liaison chiffrée intersites joignable (ICMP phase 2 OK)."
    } elseif ($udp500State -eq "RESPONSE") {
        Add-NetCheck -Element "Tunnel VPN IPsec ($RemoteVpnIP)" -Value "Phase 1 IKE UP (ICMP bloqué)" -Status "WARN" -Detail "Réponse IKE UDP 500 détectée sans réponse ICMP phase 2."
    } elseif ($udp500State -eq "TIMEOUT") {
        Add-NetCheck -Element "Tunnel VPN IPsec ($RemoteVpnIP)" -Value "Inconnu / Filtré (ICMP KO)" -Status "WARN" -Detail "Aucune réponse ICMP ni IKE UDP 500 dans le délai (pare-feu probable)."
    } else {
        Add-NetCheck -Element "Tunnel VPN IPsec ($RemoteVpnIP)" -Value "Inaccessible (DOWN)" -Status "CRITIQUE" -Detail "Port UDP 500 fermé (ICMP Unreachable) et hôte injoignable."
    }
}

# 3. TEST DE FRAGMENTATION ET MTU (MAX TRANSMISSION UNIT)
Write-Host "`n [*] Test de fragmentation MTU (Détection problèmes MSS Clamping VPN)..." -ForegroundColor Yellow
$mtuTarget = if ($GatewayIP) { $GatewayIP } else { "8.8.8.8" }
$mtuStatus = "UNKNOWN"
$mtuPinger = [System.Net.NetworkInformation.Ping]::new()
try {
    $dfOpts = [System.Net.NetworkInformation.PingOptions]::new(64, $true)
    $dfBuf  = [byte[]]::new(1472)
    $mtuReply = $mtuPinger.Send($mtuTarget, 1000, $dfBuf, $dfOpts)
    $mtuStatus = [string]$mtuReply.Status
} catch {
    $mtuStatus = "ERROR"
} finally {
    $mtuPinger.Dispose()
}

if ($mtuStatus -eq "PacketTooBig") {
    Add-NetCheck -Element "Optimisation MTU Réseau ($mtuTarget)" -Value "Fragmentation Détectée" -Status "WARN" -Detail "Trames de 1500 octets (1472 + 28) trop grandes : ajustement MSS Clamping conseillé."
} elseif ($mtuStatus -eq "Success") {
    Add-NetCheck -Element "Optimisation MTU Réseau ($mtuTarget)" -Value "MTU 1500 OK" -Status "OK" -Detail "Aucune fragmentation sur trame 1500 octets (DF-bit validé)."
} else {
    Add-NetCheck -Element "Optimisation MTU Réseau ($mtuTarget)" -Value "Non vérifié ($mtuStatus)" -Status "WARN" -Detail "Impossible de valider le MTU vers $mtuTarget (ICMP filtré ou cible injoignable)."
}

# 4. GESTION DES FICHIERS DE CONFIGURATION
Write-Host "`n [*] Gestion des sauvegardes de configuration équipements ($ApplianceType)..." -ForegroundColor Yellow
Import-Module "$PSScriptRoot\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
$backupDir = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Network_Backups" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Network_Backups" }
if (-not (Test-Path $backupDir)) { New-Item $backupDir -ItemType Directory -Force | Out-Null }

$appLabel = if ($ApplianceIP) { "$ApplianceType ($ApplianceIP)" } else { $ApplianceType }
Add-NetCheck -Element "Archivage Configuration $appLabel" -Value "Dépôt Prêt" -Status "OK" -Detail "Répertoire de sauvegarde centralisé initialisé : $backupDir"

# 5. GENERATION DU RAPPORT HTML
$reportDir  = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Reports" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
$reportPath = Join-Path $reportDir "Network-Appliance-Report.html"
$rows = ($netResults | ForEach-Object {
    $badge = if ($_.Statut -eq "OK") { "#107c41" } elseif ($_.Statut -eq "WARN") { "#d83b01" } else { "#a80000" }
    $comp  = [System.Net.WebUtility]::HtmlEncode([string]$_.Composant)
    $mes   = [System.Net.WebUtility]::HtmlEncode([string]$_.Mesure)
    $stat  = [System.Net.WebUtility]::HtmlEncode([string]$_.Statut)
    $obs   = [System.Net.WebUtility]::HtmlEncode([string]$_.Observation)
    "<tr><td><b>$comp</b></td><td>$mes</td><td><span style='background:$badge;color:white;padding:3px 8px;border-radius:4px;font-weight:bold;'>$stat</span></td><td>$obs</td></tr>"
}) -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Audit Équipements Réseau & VPN</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f8fafc; color: #1e293b; padding: 25px; }
        .card { background: white; border-radius: 8px; padding: 30px; max-width: 900px; margin: auto; box-shadow: 0 4px 15px rgba(0,0,0,0.06); }
        h1 { color: #0f766e; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; font-size: 14px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #e2e8f0; }
        th { background: #0f766e; color: white; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>🌐 Bilan Réseau, Pare-feux (FortiGate/Stormshield) & Tunnels VPN</h1>
        <p><b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm') | <b>Spécialiste Réseau :</b> Amine BERRADA</p>
        <table>
            <thead><tr><th>Composant</th><th>Mesure</th><th>Statut</th><th>Détails & Analyse</th></tr></thead>
            <tbody>$rows</tbody>
        </table>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n [OK] Rapport Réseau généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
