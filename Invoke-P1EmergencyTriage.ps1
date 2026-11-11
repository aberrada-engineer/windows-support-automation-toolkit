#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-P1EmergencyTriage v3.0 - Diagnostic d'Urgence & Triage Flash P1/P2 (Astreinte 24/7).
    Conçu pour les incidents critiques sur environnements de production (Porsche, TAG Heuer, Hublot).

.DESCRIPTION
    En moins de 30 secondes, extrait et analyse la boîte noire de la machine :
    1. Détection et analyse des Crash Dumps / BSOD récents (Minidumps)
    2. Extraction des 50 dernières erreurs critiques des journaux Système et Application
    3. Audit matériel et alertes disques / contrôleurs RAID (statut SMART, pannes secteurs)
    4. Test de connectivité réseau d'urgence (Passerelle, DNS, Cœur de réseau)
    5. Génération immédiate d'un "Bilan Flash Incident P1" pour communication client / direction
#>

[CmdletBinding()]
param(
    [int]$HoursBack = 4,
    [switch]$OpenReport = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Red
Write-Host "   🚨  TRIAGE D'URGENCE P1/P2 (ASTREINTE 24/7) — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Analyse Boîte Noire & Diagnostic Flash d'Incident Majeur — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Red
Write-Host "  Hôte : $env:COMPUTERNAME  |  Heure : $(Get-Date -Format 'HH:mm:ss')  |  Fenêtre : Dernières $HoursBack heures`n" -ForegroundColor DarkCyan

$triageReport = [PSCustomObject]@{
    HostName       = $env:COMPUTERNAME
    Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    BSODDetected   = $false
    DumpFiles      = @()
    StorageAlerts  = @()
    NetworkStatus  = "Inconnu"
    CriticalEvents = [System.Collections.Generic.List[PSCustomObject]]::new()
}

# 1. ANALYSE DES CRASH DUMPS (BSOD)
Write-Host " [*] Recherche de Crash Dumps / Écrans Bleus (BSOD)..." -ForegroundColor Yellow
$dumpPath = "$env:SystemRoot\Minidump"
if (Test-Path $dumpPath) {
    $dumps = Get-ChildItem $dumpPath -Filter "*.dmp" -ErrorAction SilentlyContinue |
             Where-Object { $_.LastWriteTime -ge (Get-Date).AddHours(-$HoursBack) } |
             Sort-Object LastWriteTime -Descending

    if ($dumps) {
        $triageReport.BSODDetected = $true
        $triageReport.DumpFiles = $dumps.Name
        Write-Host "  [ALERTE P1] $($dumps.Count) fichier(s) Crash Dump détecté(s) dans les dernières $HoursBack heures !" -ForegroundColor Red
        foreach ($d in $dumps) {
            Write-Host "   -> $($d.Name) ($($d.LastWriteTime.ToString('dd/MM HH:mm')))" -ForegroundColor Red
        }
    } else {
        Write-Host "  [OK] Aucun Crash Dump récent détecté." -ForegroundColor Green
    }
} else {
    Write-Host "  [OK] Répertoire Minidump vide." -ForegroundColor Green
}

# 2. EXTRACTION DES ÉVÉNEMENTS CRITIQUES (JOURNAL SYSTÈME & APPLI)
Write-Host "`n [*] Analyse des journaux d'événements critiques (System & Application)..." -ForegroundColor Yellow
$filter = @{
    LogName   = @('System', 'Application')
    Level     = @(1, 2) # 1 = Critical, 2 = Error
    StartTime = (Get-Date).AddHours(-$HoursBack)
}

$events = Get-WinEvent -FilterHashtable $filter -MaxEvents 50 -ErrorAction SilentlyContinue
if ($events) {
    Write-Host "  [!] $(@($events).Count) événement(s) critique(s) ou d'erreur extrait(s)." -ForegroundColor Yellow
    foreach ($evt in $events) {
        $triageReport.CriticalEvents.Add([PSCustomObject]@{
            Date    = $evt.TimeCreated.ToString("HH:mm:ss")
            Source  = $evt.ProviderName
            EventID = $evt.Id
            Message = ($evt.Message -split "`n")[0]
        })
    }
} else {
    Write-Host "  [OK] Zéro événement critique dans les dernières $HoursBack heures." -ForegroundColor Green
}

# 3. SANTÉ DU STOCKAGE PHYSIQUE & CONTRÔLEURS
Write-Host "`n [*] Vérification de l'intégrité des disques physiques (SMART / WMI)..." -ForegroundColor Yellow
$disks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
foreach ($dk in $disks) {
    $status = $dk.Status
    $sizeGB = [math]::Round($dk.Size / 1GB, 0)
    if ($status -eq "OK") {
        Write-Host "  [OK] $($dk.Model) ($sizeGB Go) — Statut : $status" -ForegroundColor Green
    } else {
        Write-Host "  [ALERTE MATERIELLE] $($dk.Model) — Statut défaillant : $status" -ForegroundColor Red
        $triageReport.StorageAlerts += "$($dk.Model) ($status)"
    }
}

# 4. CONNECTIVITÉ RÉSEAU D'URGENCE
Write-Host "`n [*] Test des liaisons réseaux d'urgence..." -ForegroundColor Yellow
$gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
$gwPing = if ($gw) { Test-Connection -ComputerName $gw -Count 1 -Quiet -TimeoutSeconds 1 } else { $false }
$dnsPing = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -TimeoutSeconds 1

if ($gwPing -and $dnsPing) {
    $triageReport.NetworkStatus = "Opérationnel (Passerelle $gw joignable)"
    Write-Host "  [OK] Réseau fonctionnel (Passerelle : $gw, DNS public OK)" -ForegroundColor Green
} elseif ($gwPing) {
    $triageReport.NetworkStatus = "Dégradé (Passerelle OK, Sortie Internet KO)"
    Write-Host "  [!] Réseau dégradé (Passerelle joignable mais pas d'accès WAN)" -ForegroundColor Yellow
} else {
    $triageReport.NetworkStatus = "CRITIQUE (Passerelle injoignable)"
    Write-Host "  [CRITIQUE] Passerelle locale $gw injoignable !" -ForegroundColor Red
}

# 5. GÉNÉRATION DU BILAN FLASH P1 (HTML)
$reportDir = "C:\ESN-Toolkit\Reports"
if (-not (Test-Path $reportDir)) { New-Item $reportDir -ItemType Directory -Force | Out-Null }
$reportPath = Join-Path $reportDir "Flash-Incident-P1-$($env:COMPUTERNAME).html"

$eventRows = $triageReport.CriticalEvents | Select-Object -First 20 | ForEach-Object {
    "<tr><td><b>$($_.Date)</b></td><td>$($_.Source)</td><td><code>ID $($_.EventID)</code></td><td>$($_.Message)</td></tr>"
} -join "`n"

$bsodBadge = if ($triageReport.BSODDetected) { "<span style='background:#d83b01;color:white;padding:4px 8px;border-radius:4px;'>CRASH DUMP DETECTE</span>" } else { "<span style='background:#107c41;color:white;padding:4px 8px;border-radius:4px;'>AUCUN CRASH BSOD</span>" }

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Bilan Flash Incident P1 - $env:COMPUTERNAME</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #0f141c; color: #e6edf3; padding: 25px; }
        .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 25px; max-width: 950px; margin: auto; }
        h1 { color: #f85149; margin-top: 0; }
        .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin: 20px 0; }
        .box { background: #21262d; padding: 15px; border-radius: 6px; border: 1px solid #30363d; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 13px; }
        th, td { padding: 8px 10px; text-align: left; border-bottom: 1px solid #30363d; }
        th { background: #21262d; color: #58a6ff; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>🚨 Bilan Flash Incident P1 / P2 — Astreinte</h1>
        <p><b>Machine :</b> $env:COMPUTERNAME | <b>Horodatage :</b> $($triageReport.Timestamp) | <b>Analyste :</b> Amine BERRADA</p>
        <div class='grid'>
            <div class='box'><b>État Système / BSOD :</b><br><br>$bsodBadge</div>
            <div class='box'><b>Connectivité Réseau :</b><br><br>$($triageReport.NetworkStatus)</div>
            <div class='box'><b>Alertes Matériel Disque :</b><br><br>$(if ($triageReport.StorageAlerts.Count -gt 0) { $triageReport.StorageAlerts -join ', ' } else { 'Intégrité Matérielle OK' })</div>
        </div>
        <h3>Derniers Événements d'Erreur & Faits Marquants (Extrait 20 derniers)</h3>
        <table>
            <thead><tr><th>Heure</th><th>Source</th><th>Event ID</th><th>Description</th></tr></thead>
            <tbody>$eventRows</tbody>
        </table>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n [OK] Bilan Flash Incident généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
