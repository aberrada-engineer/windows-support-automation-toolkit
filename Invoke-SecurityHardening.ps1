#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-SecurityHardening v3.0 - Audit & Durcissement de Sécurité ANSSI / CIS Benchmark.
    Évalue la posture de sécurité d'un poste ou serveur et remédie immédiatement aux failles.

.DESCRIPTION
    Points d'audit & remédiation :
    1. Désactivation protocoles obsolètes (SMBv1, LLMNR, NetBIOS)
    1. Désactivation du protocole vulnérable SMBv1 (WannaCry / EternalBlue)
    2. Désactivation LLMNR (anti-poisoning / vol de hash NTLM)
    3. Activation et durcissement UAC (User Account Control)
    4. Exigence NLA (Network Level Authentication) pour les connexions RDP
    5. Désactivation du compte Invité local (SID *-501)
    6. Désactivation de l'Exécution Automatique (AutoRun / AutoPlay - anti-BadUSB)
    7. Activation de la journalisation avancée PowerShell (Script Block Logging)
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Enforce, # Applique les corrections si vrai, sinon audit seul
    [switch]$OpenReport
)
Set-StrictMode -Version Latest
if (-not $PSBoundParameters.ContainsKey('OpenReport')) { $OpenReport = $true }

if ([Environment]::UserInteractive) {
    try { Clear-Host } catch { Write-Verbose "Clear-Host ignored: $($_.Exception.Message)" }
}
Write-Host "================================================================================" -ForegroundColor Red
Write-Host "   🛡️  AUDIT DE DURCISSEMENT & CYBERSECURITE (ANSSI / CIS) — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Contrôle de conformité et remédiation de surface d'attaque" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Red
Write-Host ""

$auditResults = [System.Collections.Generic.List[PSCustomObject]]::new()
$totalPoints = 0
$earnedPoints = 0

function Check-Rule {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Name,
        [int]$Weight,
        [scriptblock]$TestLogic,
        [scriptblock]$FixLogic,
        [string]$Description
    )
    $script:totalPoints += $Weight
    $isCompliant = & $TestLogic

    $actionTaken = "Aucune"
    if ($isCompliant) {
        $script:earnedPoints += $Weight
        $status = "CONFORME"
        $color  = "Green"
    } else {
        if ($Enforce -and $FixLogic -and $PSCmdlet.ShouldProcess($Name, "Appliquer durcissement système")) {
            try {
                & $FixLogic
                $status = "CORRIGE"
                $actionTaken = "Remédié automatiquement"
                $color  = "Yellow"
                $script:earnedPoints += $Weight
            } catch {
                $status = "NON CONFORME"
                $actionTaken = "Échec remédiation: $($_.Exception.Message)"
                $color  = "Red"
            }
        } else {
            $status = "NON CONFORME"
            $color  = "Red"
        }
    }

    $auditResults.Add([PSCustomObject]@{
        Regle       = $Name
        Poids       = $Weight
        Statut      = $status
        Action      = $actionTaken
        Description = $Description
    })

    Write-Host " [$status] $Name (Points: $Weight) — $Description" -ForegroundColor $color
}

# 1. SMBv1
Check-Rule -Name "Désactivation SMBv1" -Weight 20 -Description "Protection contre WannaCry et ransomwares SMB" -TestLogic {
    $c = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
    return ($null -ne $c -and $c.EnableSMB1Protocol -eq $false)
} -FixLogic {
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
}

function Get-RegValueSafe {
    param([string]$Path, [string]$Name)
    $o = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($o -and $o.PSObject.Properties[$Name]) { return $o.$Name }
    return $null
}

# 2. LLMNR
Check-Rule -Name "Désactivation LLMNR" -Weight 15 -Description "Empêche l'empoisonnement LLMNR/NBT-NS et vol de hash NTLM" -TestLogic {
    $val = Get-RegValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast"
    return ($val -eq 0)
} -FixLogic {
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
    Set-ItemProperty $p -Name "EnableMulticast" -Value 0 -Force
}

# 3. UAC (User Account Control)
Check-Rule -Name "Élévation UAC Active" -Weight 15 -Description "Contrôle des comptes utilisateurs au niveau standard entreprise" -TestLogic {
    $uac = Get-RegValueSafe "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "EnableLUA"
    return ($uac -eq 1)
} -FixLogic {
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1 -Force
}

# 4. RDP NLA (Network Level Authentication)
Check-Rule -Name "RDP avec NLA Obligatoire" -Weight 15 -Description "Exige une pré-authentification avant ouverture session bureau à distance" -TestLogic {
    $nla = Get-RegValueSafe "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "UserAuthentication"
    return ($nla -eq 1)
} -FixLogic {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -Force
}

# 5. Compte Invité (Guest — SID bien connu *-501, compatible DC / FR / EN)
Check-Rule -Name "Compte Invité Désactivé" -Weight 10 -Description "Interdiction d'accès anonyme ou invité local" -TestLogic {
    $guest = if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -match '-501$' } | Select-Object -First 1
    } else { $null }
    if (-not $guest) {
        $cimGuest = Get-CimInstance Win32_UserAccount -Filter "LocalAccount = TRUE" -ErrorAction SilentlyContinue | Where-Object { $_.SID -match '-501$' } | Select-Object -First 1
        if ($cimGuest) { return [bool]$cimGuest.Disabled }
        $csInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($csInfo -and $csInfo.DomainRole -ge 4) { return $true }
        return $false
    }
    return ($guest.Enabled -eq $false)
} -FixLogic {
    $g = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -match '-501$' } | Select-Object -First 1
    if ($g) { Disable-LocalUser -InputObject $g -ErrorAction Stop }
}

# 6. AutoPlay / AutoRun
Check-Rule -Name "Désactivation AutoRun / AutoPlay" -Weight 10 -Description "Protection contre les clés USB piégées (BadUSB)" -TestLogic {
    $ar = Get-RegValueSafe "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun"
    return ($ar -eq 255)
} -FixLogic {
    $p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
    Set-ItemProperty $p -Name "NoDriveTypeAutoRun" -Value 255 -Force
}

# 7. PowerShell Script Block Logging
Check-Rule -Name "Audit PowerShell ScriptBlock" -Weight 15 -Description "Enregistre l'exécution des scripts PowerShell dans le journal d'événements" -TestLogic {
    $sbl = Get-RegValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" "EnableScriptBlockLogging"
    return ($sbl -eq 1)
} -FixLogic {
    $p = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
    Set-ItemProperty $p -Name "EnableScriptBlockLogging" -Value 1 -Force
}

# CALCUL DU SCORE
$complianceScore = [math]::Round(($earnedPoints / $totalPoints) * 100, 0)
$scoreColor = if ($complianceScore -ge 80) { "Green" } elseif ($complianceScore -ge 60) { "Yellow" } else { "Red" }

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "   SCORE DE SECURITE & CONFORMITE : " -NoNewline -ForegroundColor Cyan
Write-Host "$complianceScore / 100" -ForegroundColor $scoreColor -NoNewline
Write-Host "  (Points : $earnedPoints / $totalPoints)" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Cyan

# RAPPORT HTML
Import-Module "$PSScriptRoot\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
$hostLabel = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
$encHost   = [System.Net.WebUtility]::HtmlEncode([string]$hostLabel)
$reportDir  = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Reports" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
$reportPath = Join-Path $reportDir "Security-Hardening-$hostLabel.html"
$rows = ($auditResults | ForEach-Object {
    $badgeCol = if ($_.Statut -eq "CONFORME") { "#107c41" } elseif ($_.Statut -eq "CORRIGE") { "#ff8c00" } else { "#d83b01" }
    $regle = [System.Net.WebUtility]::HtmlEncode([string]$_.Regle)
    $stat  = [System.Net.WebUtility]::HtmlEncode([string]$_.Statut)
    $poids = [System.Net.WebUtility]::HtmlEncode([string]$_.Poids)
    $desc  = [System.Net.WebUtility]::HtmlEncode([string]$_.Description)
    $act   = [System.Net.WebUtility]::HtmlEncode([string]$_.Action)
    "<tr><td><b>$regle</b></td><td><span style='background:$badgeCol;color:white;padding:3px 8px;border-radius:10px;font-weight:bold;'>$stat</span></td><td>$poids pts</td><td>$desc</td><td>$act</td></tr>"
}) -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Audit de Sécurité - $encHost</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f4f6f9; color: #222; padding: 25px; }
        .card { background: white; border-radius: 8px; padding: 25px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); max-width: 900px; margin: auto; }
        h1 { color: #800000; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #1b2838; color: white; }
        .score-box { font-size: 24px; font-weight: bold; padding: 15px; border-radius: 6px; text-align: center; margin: 15px 0; background: #eee; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>🛡️ Rapport de Durcissement & Posture de Sécurité</h1>
        <p><b>Machine :</b> $encHost | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm') | <b>Mode :</b> $(if ($Enforce) { 'Audit & Remédiation Automatique' } else { 'Audit Seul' })</p>
        <div class='score-box' style='color:$(if ($complianceScore -ge 80){"green"}else{"red"});'>
            Score de Conformité : $complianceScore / 100
        </div>
        <table>
            <thead><tr><th>Règle de sécurité</th><th>Statut</th><th>Pondération</th><th>Description</th><th>Action menée</th></tr></thead>
            <tbody>$rows</tbody>
        </table>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host " [OK] Rapport de sécurité généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
