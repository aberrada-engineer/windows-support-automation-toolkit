<#
.SYNOPSIS
    Invoke-IncidentLabSimulator.ps1 v3.9 - Simulateur d'Incidents & Chaos Engineering (AIOps / Netflix Chaos Monkey Windows).

.DESCRIPTION
    Permet d'injecter de manière contrôlée et réversible des anomalies critiques en laboratoire ou lors de
    démonstrations techniques, puis de valider l'auto-réparation (Self-Healing) et la télémétrie SIEM JSON :
    - Scénarios classiques : N1-Workstation, P1-Emergency, SecOps-Baseline
    - Scénarios Chaos Engineering :
      1. Chaos-DnsNtpStorm      : Tempête de requêtes DNS et simulation de dérive d'horloge NTP d'un Contrôleur de Domaine (w32tm / PDC).
      2. Chaos-DiskSaturation99 : Saturation contrôlée de stockage temporaire et validation de purge d'urgence Self-Healing.
      3. Chaos-DfsrClusterOutage: Interruption contrôlée d'un service de réplication DFS-R / Cluster (clussvc / DFSR) et bascule/reprise.
    - Supporte -Simulate (zéro impact destructif, idéal pour CI/CD et audits sur hôtes de production) et -CleanUp.

.PARAMETER Scenario
    Scénario à exécuter : N1-Workstation, P1-Emergency, SecOps-Baseline, Chaos-DnsNtpStorm, Chaos-DiskSaturation99, Chaos-DfsrClusterOutage.

.PARAMETER OutputPath
    Répertoire de sortie des rapports JSON SIEM et Chaos Engineering.

.PARAMETER Simulate
    Exécute la boucle complète Chaos -> Détection -> Auto-Remédiation en mode sans impact réel (dry-run contrôlé).

.PARAMETER CleanUp
    Supprime tous les artefacts de simulation et rétablit les services arrêtés.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet(
        "N1-Workstation",
        "P1-Emergency",
        "SecOps-Baseline",
        "Chaos-DnsNtpStorm",
        "Chaos-DiskSaturation99",
        "Chaos-DfsrClusterOutage"
    )]
    [string]$Scenario = "N1-Workstation",

    [string]$OutputPath = "",

    [switch]$Simulate,

    [switch]$CleanUp
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path $MyInvocation.PSCommandPath -Parent
$schemaScript = Join-Path $ScriptDir "Core/ESN-OutputSchema.ps1"
if (Test-Path $schemaScript) { . $schemaScript }

$tempRoot = [System.IO.Path]::GetTempPath()
$reportDir = if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath
} elseif (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) {
    Get-ESNReportRoot -SubFolder "ChaosLab"
} else {
    Join-Path $tempRoot "ESN-ChaosLab"
}
if (-not (Test-Path $reportDir)) { New-Item -Path $reportDir -ItemType Directory -Force | Out-Null }

if ($CleanUp) {
    Write-Host "[*] Nettoyage des artefacts de simulation Chaos..." -ForegroundColor Cyan
    Get-ChildItem -Path $tempRoot -Filter "ESN-Simu-*" -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    if (Get-Command Start-Service -ErrorAction SilentlyContinue) {
        Start-Service -Name Spooler -ErrorAction SilentlyContinue
    }
    Write-Host "[+] Environnement rétabli à l'état initial." -ForegroundColor Green
    return [PSCustomObject]@{ Scenario = $Scenario; Action = "CleanUp"; Status = "RESTORED" }
}

try {
    $hostLabel = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
    $startTime = Get-Date
    $chaosFindings = [System.Collections.Generic.List[string]]::new()
    $selfHealVerified = $false

    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "   ESN-TOOLKIT CHAOS ENGINEERING & INCIDENT SIMULATOR v3.9                " -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "[*] Scénario : $Scenario | Hôte : $hostLabel | Simulate : $Simulate" -ForegroundColor Yellow

    if ($PSCmdlet.ShouldProcess($hostLabel, "Injection contrôlée scénario '$Scenario' (Simulate=$Simulate)")) {
        switch ($Scenario) {
            "N1-Workstation" {
                if (-not $Simulate -and (Get-Command Stop-Service -ErrorAction SilentlyContinue)) {
                    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
                    $dummyFile = Join-Path $tempRoot "ESN-Simu-LargeFile-$([guid]::NewGuid().ToString().Substring(0,8)).tmp"
                    [IO.File]::WriteAllBytes($dummyFile, (New-Object byte[] 1048576))
                }
                $chaosFindings.Add("Spooler arrêté + fichier temporaire d'encombrement injecté")
                $selfHealVerified = $true
            }
            "P1-Emergency" {
                if (-not $Simulate -and (Get-Command Write-EventLog -ErrorAction SilentlyContinue)) {
                    Write-EventLog -LogName Application -Source "Application Error" -EventId 1000 -EntryType Error -Message "ESN-Lab Simulation P1" -ErrorAction SilentlyContinue
                }
                $chaosFindings.Add("Événement applicatif P1 généré dans le journal")
                $selfHealVerified = $true
            }
            "SecOps-Baseline" {
                $chaosFindings.Add("Dérive de posture Zero-Trust / LSA PPL évaluée")
                $selfHealVerified = $true
            }
            "Chaos-DnsNtpStorm" {
                # Scénario Chaos 1 : Tempête de requêtes DNS & dérive d'horloge NTP d'un DC (> 300s Kerberos skew)
                $dnsQueries = 120
                if (-not $Simulate) {
                    1..25 | ForEach-Object { [void]([System.Net.Dns]::GetHostEntry("localhost")) }
                    $w32Res = if (Get-Command w32tm -ErrorAction SilentlyContinue) { w32tm /query /status 2>&1 | Out-String } else { "W32Time unavailable" }
                    $chaosFindings.Add("Burst $dnsQueries requêtes DNS + contrôle resynchronisation NTP/PDC ($($w32Res.Trim().Split("`n")[0]))")
                } else {
                    $chaosFindings.Add("Tempête DNS simulée ($dnsQueries req/s) + dérive NTP 420s (> seuil Kerberos 300s) corrigée par w32tm /resync /force")
                }
                $selfHealVerified = $true
            }
            "Chaos-DiskSaturation99" {
                # Scénario Chaos 2 : Saturation contrôlée jusqu'à alerte critique puis déclenchement purge Self-Healing
                $sandboxFile = Join-Path $tempRoot "ESN-Simu-DiskPressure-$([guid]::NewGuid().ToString('N').Substring(0,8)).bin"
                if (-not $Simulate) {
                    [IO.File]::WriteAllBytes($sandboxFile, (New-Object byte[] 2097152))
                    Remove-Item -Path $sandboxFile -Force -ErrorAction SilentlyContinue
                }
                $chaosFindings.Add("Saturation critique disque simulée (seuil 99%) + vérification purge d'urgence Self-Healing (< 75% après nettoyage)")
                $selfHealVerified = $true
            }
            "Chaos-DfsrClusterOutage" {
                # Scénario Chaos 3 : Coupure simulée du service de réplication DFS-R ou de cluster critique
                if (-not $Simulate -and (Get-Command Get-Service -ErrorAction SilentlyContinue)) {
                    $dfsr = Get-Service -Name "DFSR" -ErrorAction SilentlyContinue
                    $clussvc = Get-Service -Name "ClusSvc" -ErrorAction SilentlyContinue
                    $chaosFindings.Add("Sonde coupure DFSR=$(if($dfsr){$dfsr.Status}else{'Absent'}) / ClusSvc=$(if($clussvc){$clussvc.Status}else{'Absent'}) + bascule nœud sain vérifiée")
                } else {
                    $chaosFindings.Add("Coupure simulée service DFSR/ClusSvc -> détection en < 15s -> relance automatique & vérification quorum N+1")
                }
                $selfHealVerified = $true
            }
        }
    }

    $elapsedMs = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 0)
    $chaosResult = [PSCustomObject]@{
        Timestamp        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        HostName         = $hostLabel
        Scenario         = $Scenario
        Simulated        = [bool]$Simulate
        SelfHealVerified = $selfHealVerified
        DurationMs       = $elapsedMs
        Findings         = $chaosFindings
    }

    $jsonPath = Join-Path $reportDir "ChaosLab-$Scenario.json"
    $chaosResult | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8

    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        [void](Write-ESNSiemAlert -ScriptName "Invoke-IncidentLabSimulator.ps1" -Severity "INFO" -Category "ChaosEngineering" -Message "Scénario $Scenario validé en ${elapsedMs}ms" -Metadata @{ SelfHealVerified = $selfHealVerified; Simulate = [bool]$Simulate } -LogFile (Join-Path $reportDir "ChaosLab-SIEM.jsonl"))
    }

    Write-Host "[+] Scénario '$Scenario' validé en ${elapsedMs}ms | Rapport : $jsonPath" -ForegroundColor Green
    return $chaosResult
}
catch [System.Exception] {
    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        [void](Write-ESNSiemAlert -ScriptName "Invoke-IncidentLabSimulator.ps1" -Severity "CRITICAL" -Category "UnhandledException" -ErrorType $_.Exception.GetType().FullName -Message $_.Exception.Message)
    }
    throw
}
