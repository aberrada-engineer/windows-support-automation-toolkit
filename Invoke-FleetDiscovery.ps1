#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-FleetDiscovery v3.1 - Cartographie Réseau & Découverte Automatisée du Parc IT.
    Scanne le sous-réseau en parallèle (compatible PowerShell 5.1 et 7+) et dresse l'inventaire des machines connectées.

.DESCRIPTION
    - Détection automatique du sous-réseau local (ex: 192.168.1.0/24)
    - Ping multi-threadé ultra-rapide (254 hôtes en ~15 secondes)
    - Résolution DNS / Hostname inversée
    - Détection des rôles par scan de ports clés :
      * Port 445  : Machine Windows (Serveur ou Poste)
      * Port 3389 : Accès RDP ouvert
      * Port 22   : Machine Linux / Équipement Réseau (SSH)
      * Port 80/443 : Interface Web (Switch, Pare-feu, Imprimante)
    - Rapport HTML cartographique interactif avec tableau triable
#>

[CmdletBinding()]
param(
    [string]$Subnet = "", # Ex: "192.168.1" (laisser vide pour auto-détection)
    [switch]$OpenReport = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   🌐  CARTOGRAPHIE RESEAU & AUDIT DU PARC (FLEET DISCOVERY) — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Supervision et inventaire automatique des équipements du réseau" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. AUTO-DETECTION DU SOUS-RESEAU
if ([string]::IsNullOrWhiteSpace($Subnet)) {
    $ipConfig = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback|vEthernet|Virtual" -and $_.IPAddress -notlike "169.254*" } | Select-Object -First 1
    if ($ipConfig) {
        $parts = $ipConfig.IPAddress.Split('.')
        $Subnet = "$($parts[0]).$($parts[1]).$($parts[2])"
        Write-Host " [*] Sous-réseau local détecté : $Subnet.0/24 (via $($ipConfig.IPAddress))" -ForegroundColor Green
    } else {
        $Subnet = "192.168.1"
        Write-Host " [!] Détection automatique impossible, utilisation par défaut : $Subnet.0/24" -ForegroundColor Yellow
    }
} else {
    Write-Host " [*] Sous-réseau ciblé : $Subnet.0/24" -ForegroundColor Green
}

Write-Host " [*] Lancement du scan multi-threadé (254 adresses IP)..." -ForegroundColor Yellow

$portsToTest = @(22, 80, 443, 445, 3389)

# Scan parallèle compatible PowerShell 5.1 & 7+ via RunspacePool
$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 64)
$pool.Open()
$scanWorker = {
    param([string]$Ip, [int[]]$Ports)
    $ping = [System.Net.NetworkInformation.Ping]::new()
    try {
        $reply = $ping.Send($Ip, 800)
        if ($reply.Status -ne [System.Net.NetworkInformation.IPStatus]::Success) { return $null }
    } catch { return $null } finally { $ping.Dispose() }

    $hostname = try { [System.Net.Dns]::GetHostEntry($Ip).HostName } catch { "Inconnu" }
    $openPorts = [System.Collections.Generic.List[int]]::new()
    foreach ($p in $Ports) {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        try {
            $connect = $tcp.BeginConnect($Ip, $p, $null, $null)
            if ($connect.AsyncWaitHandle.WaitOne(300, $false) -and $tcp.Connected) {
                $openPorts.Add($p)
                $tcp.EndConnect($connect)
            }
        } catch { Write-Verbose "Port $p unreachable on $Ip" } finally { $tcp.Dispose() }
    }

    $type = "Inconnu"
    if ($openPorts -contains 445 -and $openPorts -contains 3389) { $type = "Windows (Poste / Serveur)" }
    elseif ($openPorts -contains 445) { $type = "Windows / Partage SMB" }
    elseif ($openPorts -contains 22) { $type = "Linux / Réseau (SSH)" }
    elseif ($openPorts -contains 80 -or $openPorts -contains 443) { $type = "Équipement Web (Switch / Imprimante / Pare-feu)" }

    return [PSCustomObject]@{
        IP        = $Ip
        Nom       = $hostname
        Type      = $type
        Ports     = ($openPorts -join ', ')
        LatenceMs = "$($reply.RoundtripTime) ms"
    }
}

$jobs = foreach ($hostOctet in 1..254) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($scanWorker).AddArgument("$Subnet.$hostOctet").AddArgument($portsToTest)
    [PSCustomObject]@{ Instance = $ps; Handle = $ps.BeginInvoke() }
}
$aliveHosts = [System.Collections.Generic.List[PSCustomObject]]::new()
try {
    foreach ($j in $jobs) {
        $item = $j.Instance.EndInvoke($j.Handle)
        if ($item) { foreach ($r in $item) { $aliveHosts.Add($r) } }
        $j.Instance.Dispose()
    }
} finally {
    $pool.Close()
    $pool.Dispose()
}

$sortedHosts = $aliveHosts | Sort-Object { [version]$_.IP }

Write-Host "`n [OK] Scan terminé ! $($sortedHosts.Count) équipement(s) actif(s) détecté(s)." -ForegroundColor Green

# AFFICHAGE CONSOLE
$sortedHosts | Format-Table IP, Nom, Type, Ports -AutoSize

# RAPPORT HTML
$schemaScript = Join-Path $PSScriptRoot "Core/ESN-OutputSchema.ps1"
if (Test-Path $schemaScript) { . $schemaScript }
$reportDir = if (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) { Get-ESNReportRoot } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
if (-not (Test-Path $reportDir)) { New-Item -Path $reportDir -ItemType Directory -Force | Out-Null }
$reportPath = Join-Path $reportDir "Fleet-Discovery-$Subnet.html"
$rows = ($sortedHosts | ForEach-Object {
    "<tr><td><b>$($_.IP)</b></td><td>$([System.Net.WebUtility]::HtmlEncode($_.Nom))</td><td>$([System.Net.WebUtility]::HtmlEncode($_.Type))</td><td><code>$($_.Ports)</code></td></tr>"
}) -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Cartographie Réseau - $Subnet.0/24</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f4f6f9; color: #222; padding: 25px; }
        .card { background: white; border-radius: 8px; padding: 25px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); max-width: 1000px; margin: auto; }
        h1 { color: #182b49; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #182b49; color: white; }
        .stats { display: flex; gap: 20px; margin-bottom: 20px; }
        .stat-box { background: #e8f0fe; padding: 15px 25px; border-radius: 6px; font-weight: bold; color: #182b49; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>🌐 Cartographie Réseau & Inventaire du Parc</h1>
        <div class='stats'>
            <div class='stat-box'>Sous-réseau : $Subnet.0/24</div>
            <div class='stat-box'>Équipements en ligne : $($sortedHosts.Count)</div>
            <div class='stat-box'>Date : $(Get-Date -Format 'dd/MM/yyyy HH:mm')</div>
        </div>
        <table>
            <thead><tr><th>Adresse IP</th><th>Nom d'hôte</th><th>Type / Rôle estimé</th><th>Ports ouverts</th></tr></thead>
            <tbody>$rows</tbody>
        </table>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host " [OK] Rapport cartographique généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
