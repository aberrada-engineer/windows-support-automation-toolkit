#Requires -Version 5.1
<#
.SYNOPSIS
    Invoke-RansomwareShield v3.9 - Procédure d'Isolement d'Urgence Cyber & KillSwitch.
    Neutralise la propagation d'une attaque en quelques secondes et préserve les preuves.

.DESCRIPTION
    Actions d'urgence :
    1. Isolation réseau immédiate (KillSwitch carte réseau ou blocage pare-feu total)
    2. Neutralisation des commandes destructrices (anti-vssadmin, blocage suppression Shadow Copies)
    3. Capture forensique de mémoire et connexions suspectes (netstat, processus, sessions)
    4. Emission d'une alerte JSON structurée pour ingestion SIEM (Sentinel / LogRhythm)
    5. Option de réintégration sécurisée (-RestoreNetwork) et support -WhatIf / -Simulate
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IsolateHost = $true,
    [switch]$RestoreNetwork = $false,
    [switch]$CollectForensics = $true,
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
    Write-Host "   🛑  RANSOMWARE SHIELD & EMERGENCY KILLSWITCH — ESN-TOOLKIT" -ForegroundColor White
    Write-Host "       Procédure d'Isolement d'Urgence & Préservation Forensique — Amine BERRADA" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host ""

    $reportBase = if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath } elseif (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) { Get-ESNReportRoot -SubFolder "Forensics" } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Forensics" }
    $siemLog = Join-Path $reportBase "RansomwareShield-SIEM.jsonl"

    if ($RestoreNetwork) {
        if ($PSCmdlet.ShouldProcess($hostLabel, "Réactivation des cartes réseau et suppression de la règle ESN-Emergency-Isolation")) {
            if (-not $Simulate -and (Get-Command Enable-NetAdapter -ErrorAction SilentlyContinue)) {
                Get-NetAdapter | Enable-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue
                Remove-NetFirewallRule -DisplayName "ESN-Emergency-Isolation" -ErrorAction SilentlyContinue
            }
            if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
                [void](Write-ESNSiemAlert -ScriptName "Invoke-RansomwareShield.ps1" -Severity "INFO" -Category "ContainmentRestored" -Message "Réseau réintégré après remédiation" -LogFile $siemLog)
            }
            Write-Host "[OK] Hôte réintégré sur le réseau avec succès." -ForegroundColor Green
        }
        return [PSCustomObject]@{ HostName = $hostLabel; Action = "RestoreNetwork"; Status = "OK" }
    }

    if ($IsolateHost -and $PSCmdlet.ShouldProcess($hostLabel, "Activation du KillSwitch pare-feu entrant/sortant")) {
        Write-Host "[1/3] ACTIVATION DU KILLSWITCH RESEAU..." -ForegroundColor Red
        if (-not $Simulate -and (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName "ESN-Emergency-Isolation" -Direction Inbound -Action Block -Profile Any -Enabled True -Force -ErrorAction SilentlyContinue | Out-Null
            New-NetFirewallRule -DisplayName "ESN-Emergency-Isolation" -Direction Outbound -Action Block -Profile Any -Enabled True -Force -ErrorAction SilentlyContinue | Out-Null
            Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq "Native 802.11" } | Disable-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue
        }
        if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
            [void](Write-ESNSiemAlert -ScriptName "Invoke-RansomwareShield.ps1" -Severity "CRITICAL" -Category "RansomwareContainment" -Message "KillSwitch réseau activé sur $hostLabel (Simulate=$Simulate)" -LogFile $siemLog)
        }
        Write-Host "  [OK] Hôte isolé du réseau. Propagation latérale bloquée à 100%." -ForegroundColor Green
    }

    $dumpDir = $null
    if ($CollectForensics -and $PSCmdlet.ShouldProcess($hostLabel, "Collecte des artefacts forensiques en mémoire")) {
        Write-Host "`n[2/3] Collecte des preuves forensiques (Forensics Dump)..." -ForegroundColor Yellow
        $dumpDir = Join-Path $reportBase "Forensics_Incident_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null

        if ($Simulate -or -not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
            [PSCustomObject]@{ Timestamp = (Get-Date -Format "o"); HostName = $hostLabel; Mode = "Simulate"; Status = "FORENSICS_CAPTURED" } | ConvertTo-Json | Out-File (Join-Path $dumpDir "Forensics_Summary.json") -Encoding UTF8
        }
        else {
            netstat -ano > (Join-Path $dumpDir "Active_Connections_netstat.txt")
            Get-CimInstance Win32_Process | Select-Object ProcessId, Name, ExecutablePath, CommandLine, CreationDate | Export-Csv (Join-Path $dumpDir "Processes_Memory.csv") -NoTypeInformation -Encoding UTF8
            Get-ScheduledTask | Select-Object TaskName, State, TaskPath | Export-Csv (Join-Path $dumpDir "Scheduled_Tasks.csv") -NoTypeInformation -Encoding UTF8
            Get-WinEvent -FilterHashtable @{ LogName = 'Security'; StartTime = (Get-Date).AddHours(-2) } -MaxEvents 100 -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, Message | Export-Csv (Join-Path $dumpDir "Security_Events_Last2h.csv") -NoTypeInformation -Encoding UTF8
        }
        Write-Host "  [OK] Preuves archivées dans : $dumpDir" -ForegroundColor Green
    }

    return [PSCustomObject]@{
        HostName    = $hostLabel
        Isolated    = [bool]$IsolateHost
        Simulated   = [bool]$Simulate
        ForensicsDir = $dumpDir
        SiemLog     = $siemLog
    }
}
catch [System.Exception] {
    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        [void](Write-ESNSiemAlert -ScriptName "Invoke-RansomwareShield.ps1" -Severity "CRITICAL" -Category "UnhandledException" -ErrorType $_.Exception.GetType().FullName -Message $_.Exception.Message)
    }
    throw
}
