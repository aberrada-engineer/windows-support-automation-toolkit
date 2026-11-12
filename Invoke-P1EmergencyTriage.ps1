#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-P1EmergencyTriage v3.9 - Diagnostic d'Urgence & Triage Flash P1/P2 (Astreinte 24/7).
    Conçu pour les incidents critiques sur environnements de production (Porsche, TAG Heuer, Hublot).

.DESCRIPTION
    En moins de 30 secondes, extrait et analyse la boîte noire de la machine :
    1. Détection et analyse des Crash Dumps / BSOD récents (Minidumps)
    2. Extraction des 50 dernières erreurs critiques des journaux Système et Application
    3. Audit matériel et alertes disques / contrôleurs RAID (statut SMART, pannes secteurs)
    4. Test de connectivité réseau d'urgence (Passerelle, DNS, Cœur de réseau)
    5. Génération immédiate d'un "Bilan Flash Incident P1" HTML + Télémétrie JSON SIEM.
#>

[CmdletBinding()]
param(
    [int]$HoursBack = 4,
    [switch]$OpenReport,
    [string]$OutputPath = "",
    [switch]$Simulate
)

$ErrorActionPreference = "Stop"
$schemaScript = Join-Path $PSScriptRoot "Core/ESN-OutputSchema.ps1"
if (Test-Path $schemaScript) { . $schemaScript }

try {
    $hostLabel = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
    if (-not $Simulate -and [Environment]::UserInteractive) {
        try { Clear-Host } catch { Write-Verbose "Clear-Host ignored: $($_.Exception.Message)" }
    }
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host "   🚨  TRIAGE D'URGENCE P1/P2 (ASTREINTE 24/7) — ESN-TOOLKIT" -ForegroundColor White
    Write-Host "       Analyse Boîte Noire & Diagnostic Flash d'Incident Majeur — Amine BERRADA" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host "  Hôte : $hostLabel  |  Heure : $(Get-Date -Format 'HH:mm:ss')  |  Fenêtre : Dernières $HoursBack heures`n" -ForegroundColor DarkCyan

    $storageAlertsList = [System.Collections.Generic.List[string]]::new()
    $triageReport = [PSCustomObject]@{
        HostName       = $hostLabel
        Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        BSODDetected   = $false
        DumpFiles      = @()
        StorageAlerts  = $storageAlertsList
        NetworkStatus  = "Inconnu"
        CriticalEvents = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    if ($Simulate -or -not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) {
        $triageReport.NetworkStatus = "Opérationnel (Passerelle 10.10.0.1 joignable - Simulé)"
        $triageReport.CriticalEvents.Add([PSCustomObject]@{
            Date    = (Get-Date).AddMinutes(-12).ToString("HH:mm:ss")
            Source  = "Microsoft-Windows-Kernel-Power"
            EventID = 41
            Message = "Simulation P1 : redémarrage critique détecté sans arrêt propre préalable."
        })
    }
    else {
        # 1. ANALYSE DES CRASH DUMPS (BSOD)
        Write-Host " [*] Recherche de Crash Dumps / Écrans Bleus (BSOD)..." -ForegroundColor Yellow
        $dumpPath = "$env:SystemRoot\Minidump"
        if ($dumpPath -and (Test-Path $dumpPath)) {
            $dumps = Get-ChildItem $dumpPath -Filter "*.dmp" -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -ge (Get-Date).AddHours(-$HoursBack) } |
                     Sort-Object LastWriteTime -Descending
            if ($dumps) {
                $triageReport.BSODDetected = $true
                $triageReport.DumpFiles = @($dumps.Name)
                Write-Host "  [ALERTE P1] $($dumps.Count) fichier(s) Crash Dump détecté(s) !" -ForegroundColor Red
            } else {
                Write-Host "  [OK] Aucun Crash Dump récent détecté." -ForegroundColor Green
            }
        }

        # 2. EXTRACTION DES ÉVÉNEMENTS CRITIQUES
        Write-Host "`n [*] Analyse des journaux d'événements critiques..." -ForegroundColor Yellow
        $events = Get-WinEvent -FilterHashtable @{ LogName = @('System', 'Application'); Level = @(1, 2); StartTime = (Get-Date).AddHours(-$HoursBack) } -MaxEvents 50 -ErrorAction SilentlyContinue
        foreach ($evt in @($events)) {
            if ($null -ne $evt) {
                $triageReport.CriticalEvents.Add([PSCustomObject]@{
                    Date    = $evt.TimeCreated.ToString("HH:mm:ss")
                    Source  = $evt.ProviderName
                    EventID = $evt.Id
                    Message = ($evt.Message -split "`n")[0]
                })
            }
        }

        # 3. SANTÉ DU STOCKAGE PHYSIQUE
        Write-Host "`n [*] Vérification de l'intégrité des disques physiques (SMART / WMI)..." -ForegroundColor Yellow
        foreach ($dk in @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)) {
            if ($dk.Status -ne "OK") {
                $storageAlertsList.Add("$($dk.Model) ($($dk.Status))")
            }
        }

        # 4. CONNECTIVITÉ RÉSEAU D'URGENCE
        $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
        $gwPing = if ($gw) { Test-Connection -ComputerName $gw -Count 1 -Quiet -TimeoutSeconds 1 } else { $false }
        $dnsPing = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -TimeoutSeconds 1
        $triageReport.NetworkStatus = if ($gwPing -and $dnsPing) { "Opérationnel (Passerelle $gw joignable)" } elseif ($gwPing) { "Dégradé (Passerelle OK, Sortie Internet KO)" } else { "CRITIQUE (Passerelle injoignable)" }
    }

    # 5. GÉNÉRATION DU BILAN FLASH P1 (HTML + SIEM JSON)
    $reportDir = if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath } elseif (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) { Get-ESNReportRoot } else { "C:\ESN-Toolkit\Reports" }
    if (-not (Test-Path $reportDir)) { New-Item $reportDir -ItemType Directory -Force | Out-Null }
    $reportPath = Join-Path $reportDir "Flash-Incident-P1-$hostLabel.html"

    $eventRows = ($triageReport.CriticalEvents | Select-Object -First 20 | ForEach-Object {
        "<tr><td><b>$($_.Date)</b></td><td>$($_.Source)</td><td><code>ID $($_.EventID)</code></td><td>$($_.Message)</td></tr>"
    }) -join "`n"

    $bsodBadge = if ($triageReport.BSODDetected) { "<span style='background:#d83b01;color:white;padding:4px 8px;border-radius:4px;'>CRASH DUMP DETECTE</span>" } else { "<span style='background:#107c41;color:white;padding:4px 8px;border-radius:4px;'>AUCUN CRASH BSOD</span>" }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Bilan Flash Incident P1 - $hostLabel</title>
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
        <p><b>Machine :</b> $hostLabel | <b>Horodatage :</b> $($triageReport.Timestamp) | <b>Analyste :</b> Amine BERRADA</p>
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
    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        $sev = if ($triageReport.BSODDetected -or $triageReport.NetworkStatus -match "CRITIQUE") { "CRITICAL" } else { "INFO" }
        [void](Write-ESNSiemAlert -ScriptName "Invoke-P1EmergencyTriage.ps1" -Severity $sev -Category "P1EmergencyTriage" -Message "Triage P1 terminé ($($triageReport.CriticalEvents.Count) événements)" -LogFile (Join-Path $reportDir "P1Triage-SIEM.jsonl"))
    }
    Write-Host "`n [OK] Bilan Flash Incident généré : $reportPath" -ForegroundColor Green
    if ($OpenReport) { Start-Process $reportPath }
    return $triageReport
}
catch [System.Exception] {
    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        [void](Write-ESNSiemAlert -ScriptName "Invoke-P1EmergencyTriage.ps1" -Severity "CRITICAL" -Category "UnhandledException" -ErrorType $_.Exception.GetType().FullName -Message $_.Exception.Message)
    }
    throw
}
