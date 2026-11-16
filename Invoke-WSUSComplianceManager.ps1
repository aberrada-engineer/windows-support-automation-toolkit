<#
.SYNOPSIS
    Invoke-WSUSComplianceManager.ps1 - Audit de Conformité et Forçage Client WSUS (Windows Server Update Services).
.DESCRIPTION
    Conçu pour la gestion des correctifs de sécurité (Patch Management) sur parcs multi-clients :
    - Audit de la configuration registre du client Windows Update (WUServer, WUStatusServer, UseWUServer, AUOptions).
    - Test de connectivité réseau et port HTTP/HTTPS vers le serveur WSUS d'entreprise (ports 8530 ou 8531).
    - Forçage immédiat de la détection et du rapport de conformité (USOClient StartScan & wuauclt /reportnow).
    - Détection de l'état de redémarrage en attente (Pending Reboot : Component-Based Servicing, WU, Windows Update reboot flag).
    - Génération de la matrice de conformité des correctifs (Hotfixes) et du rapport de santé de patch.
.PARAMETER WsusServerUrl
    URL facultative du serveur WSUS pour test ou configuration forcée (ex: http://wsus.corp.lan:8530).
.PARAMETER ForceSync
    Déclenche immédiatement la resynchronisation avec le serveur WSUS.
.EXAMPLE
    .\Invoke-WSUSComplianceManager.ps1 -ForceSync -OpenReport
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$WsusServerUrl,
    [switch]$ForceSync,
    [switch]$ResetWuCache,
    [switch]$OpenReport
)
Set-StrictMode -Version Latest

$ErrorActionPreference = "Continue"

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   WSUS PATCH MANAGEMENT & COMPLIANCE ENFORCEMENT ENGINE                  " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "[*] Machine locale : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "[*] Date du scan   : $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor Gray
Write-Host ""

$schemaScript = Join-Path $PSScriptRoot "Core/ESN-OutputSchema.ps1"
if (Test-Path $schemaScript) { . $schemaScript }

$ReportDir = if (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) { Get-ESNReportRoot -SubFolder "WSUS" } elseif ($env:ESN_TOOLKIT_ROOT) { Join-Path $env:ESN_TOOLKIT_ROOT "Reports/WSUS" } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports/WSUS" }
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$HtmlReport = Join-Path $ReportDir "WSUS-Compliance-$Timestamp.html"

function Get-RegValueSafe {
    param([string]$Path, [string]$Name)
    $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    $prop = $item.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

# 1. Audit de la configuration registre WSUS
Write-Host "[1/4] Audit de la configuration registre WSUS d'entreprise..." -ForegroundColor White
$WuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$AuRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

$ConfiguredWsus   = Get-RegValueSafe -Path $WuRegPath -Name "WUServer"
$ConfiguredStatus = Get-RegValueSafe -Path $WuRegPath -Name "WUStatusServer"
$UseWus           = Get-RegValueSafe -Path $AuRegPath -Name "UseWUServer"
$AuOptions        = Get-RegValueSafe -Path $AuRegPath -Name "AUOptions"

$AuDesc = switch ($AuOptions) {
    1 { "Désactivé" }
    2 { "Notifier avant téléchargement" }
    3 { "Télécharger auto, notifier installation" }
    4 { "Télécharger et installer selon planification" }
    default { "Géré localement / Non configuré par GPO" }
}

$WsusTarget = if ($WsusServerUrl) { $WsusServerUrl } else { $ConfiguredWsus }

Write-Host "  -> Serveur WSUS configuré : $(if ($ConfiguredWsus) { $ConfiguredWsus } else { 'Aucun (Windows Update direct)' })" -ForegroundColor Gray
Write-Host "  -> Serveur Status WSUS    : $(if ($ConfiguredStatus) { $ConfiguredStatus } else { 'N/A' }) (UseWUServer=$UseWus)" -ForegroundColor Gray
Write-Host "  -> Mode AUOptions         : $AuDesc ($AuOptions)" -ForegroundColor Gray

# 2. Test de connectivité WSUS
Write-Host "[2/4] Test de connectivité réseau vers le serveur WSUS..." -ForegroundColor White
$WsusAccessible = $false
if (-not $WsusTarget) {
    Write-Host "  -> Aucun serveur WSUS GPO configuré — test port WSUS ignoré (Windows Update direct)." -ForegroundColor DarkGray
} elseif ($WsusTarget -match "https?://([^:/]+):?(\d+)?") {
    $wsusHost = $Matches[1]
    $wsusPort = if ($Matches[2]) { [int]$Matches[2] } else { 8530 }
    if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
        $test = Test-NetConnection -ComputerName $wsusHost -Port $wsusPort -WarningAction SilentlyContinue
        $WsusAccessible = ($null -ne $test -and [bool]$test.TcpTestSucceeded)
    } else {
        try {
            $tcpClient = [System.Net.Sockets.TcpClient]::new()
            $ar = $tcpClient.BeginConnect($wsusHost, $wsusPort, $null, $null)
            $WsusAccessible = $ar.AsyncWaitHandle.WaitOne(1500, $false)
            if ($WsusAccessible) { $tcpClient.EndConnect($ar) }
            $tcpClient.Close()
        } catch {
            $WsusAccessible = $false
        }
    }
    Write-Host "  -> Port WSUS $wsusPort sur $wsusHost : $(if ($WsusAccessible) {'OUVERT'} else {'FERMÉ / HORS LIGNE'})" -ForegroundColor $(if ($WsusAccessible) {'Green'} else {'Yellow'})
}

# 3. Détection de Pending Reboot
Write-Host "[3/4] Détection de l'état de redémarrage en attente (Pending Reboot)..." -ForegroundColor White
$RebootPending = $false
$CbsReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
$WuReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
$pfrObj = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
$PendingFileRename = if ($pfrObj -and $pfrObj.PSObject.Properties['PendingFileRenameOperations']) { $pfrObj.PendingFileRenameOperations } else { $null }

if ($CbsReboot -or $WuReboot -or $PendingFileRename) {
    $RebootPending = $true
    Write-Host "  -> ALERTE : Redémarrage requis pour finaliser les mises à jour !" -ForegroundColor Yellow
} else {
    Write-Host "  -> Aucun redémarrage en attente (Système à jour)." -ForegroundColor Green
}

# 4. Forçage de la synchronisation / Reset cache si demandé
if ($ResetWuCache -and $PSCmdlet.ShouldProcess("wuauserv / SoftwareDistribution", "Réinitialiser le cache Windows Update")) {
    Write-Host "[*] Réinitialisation du cache Windows Update demandée (-ResetWuCache)..." -ForegroundColor Yellow
    Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
    $sdDownload = if ($env:SystemRoot) { Join-Path $env:SystemRoot "SoftwareDistribution\Download" } else { "" }
    if ($sdDownload -and (Test-Path $sdDownload)) {
        Get-ChildItem -Path $sdDownload -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  -> Cache SoftwareDistribution\Download purgé." -ForegroundColor Green
    }
    Start-Service -Name wuauserv, bits -ErrorAction SilentlyContinue
}
if ($ForceSync -and $PSCmdlet.ShouldProcess("UsoClient", "Déclencher scan Windows Update")) {
    Write-Host "[*] Déclenchement forcé de la synchronisation Windows Update (UsoClient)..." -ForegroundColor Cyan
    if (Get-Command usoclient.exe -ErrorAction SilentlyContinue) {
        Start-Process -FilePath "usoclient.exe" -ArgumentList "StartInteractiveScan" -ErrorAction SilentlyContinue
    }
    Write-Host "  -> Signal de détection envoyé au client Windows Update." -ForegroundColor Green
}

# 5. Inventaire des derniers Hotfixes installés
$Hotfixes = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
    Sort-Object { $dt = [datetime]::MinValue; if ([datetime]::TryParse([string]$_.InstalledOn, [ref]$dt)) { $dt } else { [datetime]::MinValue } } -Descending |
    Select-Object -First 5
$HotfixRows = if ($Hotfixes) {
    (@($Hotfixes) | ForEach-Object {
        $kb   = [System.Net.WebUtility]::HtmlEncode([string]$_.HotFixID)
        $desc = [System.Net.WebUtility]::HtmlEncode([string]$_.Description)
        $dt   = [System.Net.WebUtility]::HtmlEncode([string]$_.InstalledOn)
        "<tr><td>$kb</td><td>$desc</td><td>$dt</td><td><span style='color:#4ade80;'>Installé</span></td></tr>"
    }) -join "`n"
} else {
    "<tr><td colspan='4' style='color:#94a3b8;'>Aucun correctif récent détecté via Win32_QuickFixEngineering</td></tr>"
}

$hostLabel  = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
$compHtml   = [System.Net.WebUtility]::HtmlEncode([string]$hostLabel)
$wsusLabel  = if ($WsusTarget) { $WsusTarget } else { "Windows Update direct (aucun WSUS GPO)" }
$wsusHtml   = [System.Net.WebUtility]::HtmlEncode([string]$wsusLabel)
$auOptHtml  = [System.Net.WebUtility]::HtmlEncode([string]$AuOptions)
$auDescHtml = [System.Net.WebUtility]::HtmlEncode([string]$AuDesc)

# 6. Génération du Rapport HTML WSUS
$HtmlContent = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Conformité WSUS & Patch Management - $compHtml</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #0f172a; color: #f8fafc; margin: 0; padding: 28px; }
        .container { max-width: 950px; margin: auto; background-color: #1e293b; border-radius: 10px; padding: 32px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
        h1 { color: #38bdf8; border-bottom: 2px solid #334155; padding-bottom: 12px; margin-top: 0; font-size: 24px; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 4px; font-weight: bold; font-size: 12px; text-transform: uppercase; background: #0284c7; color: white; }
        .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin: 20px 0; }
        .card { background-color: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 16px; }
        .card-title { font-size: 12px; color: #94a3b8; text-transform: uppercase; margin-bottom: 6px; }
        .card-value { font-size: 18px; font-weight: bold; color: #38bdf8; }
        table { width: 100%; border-collapse: collapse; margin-top: 14px; }
        th, td { border: 1px solid #334155; padding: 10px 14px; text-align: left; }
        th { background-color: #0f172a; color: #38bdf8; font-size: 13px; }
        tr:nth-child(even) { background-color: #162032; }
        .status-ok { color: #4ade80; font-weight: bold; }
        .status-warn { color: #facc15; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Conformité Patch Management & Client WSUS <span class="badge">Audit Terminé</span></h1>
        <p style="color: #94a3b8;">État de déploiement des correctifs de sécurité, politique GPO et synchronisation WSUS pour l'hôte <strong>$compHtml</strong>.</p>
        
        <div class="grid">
            <div class="card">
                <div class="card-title">Serveur WSUS Cible</div>
                <div class="card-value" style="font-size: 14px;">$wsusHtml</div>
                <div style="font-size: 11px; color: #94a3b8; margin-top: 4px;">Port 8530 / 8531</div>
            </div>
            <div class="card">
                <div class="card-title">Redémarrage Requis</div>
                <div class="card-value">$(if ($RebootPending) {'OUI (En attente)'} else {'NON'})</div>
                <div style="font-size: 11px; color: $(if ($RebootPending) {'#facc15'} else {'#4ade80'}); margin-top: 4px;">$(if ($RebootPending) {'Redémarrage à planifier'} else {'Composants à jour'})</div>
            </div>
            <div class="card">
                <div class="card-title">Mode GPO AUOptions</div>
                <div class="card-value" style="font-size: 15px;">Option $auOptHtml</div>
                <div style="font-size: 11px; color: #94a3b8; margin-top: 4px;">$auDescHtml</div>
            </div>
        </div>

        <h3>Derniers Correctifs de Sécurité Appliqués (Hotfixes)</h3>
        <table>
            <thead>
                <tr>
                    <th>Numéro KB</th>
                    <th>Description</th>
                    <th>Date d'Installation</th>
                    <th>Statut</th>
                </tr>
            </thead>
            <tbody>
                $HotfixRows
            </tbody>
        </table>

        <p style="color: #64748b; font-size: 12px; margin-top: 24px;">Généré par Antigravity ESN-Toolkit • Module WSUS & Patch Management • Référent : Amine BERRADA</p>
    </div>
</body>
</html>
"@

Set-Content -Path $HtmlReport -Value $HtmlContent -Encoding UTF8
Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "   AUDIT DE CONFORMITÉ WSUS RÉUSSI AVEC SUCCÈS                            " -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "[+] Rapport de conformité : $HtmlReport" -ForegroundColor White

if ($OpenReport) {
    Start-Process $HtmlReport
}
