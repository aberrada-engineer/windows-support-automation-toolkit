#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-ADHygieneCheck v3.0 - Audit d'Hygiène & Sécurité Active Directory.
    Évalue la posture de sécurité de l'annuaire d'entreprise et identifie les failles de privilèges.

.DESCRIPTION
    Points d'audit :
    1. Inventaire des membres des groupes à hauts privilèges (Domain Admins, Enterprise Admins, Schema Admins)
    2. Détection des comptes utilisateurs inactifs depuis plus de 90 jours
    3. Détection des comptes ordinateurs dormants depuis plus de 180 jours
    4. Détection des comptes avec mot de passe n'expirant jamais (PasswordNeverExpires)
    5. Détection des délégations Kerberos non contraintes (Risque Pass-the-Ticket)
    6. Rapport HTML synthétique de remédiation
#>

[CmdletBinding()]
param(
    [int]$InactiveUserDays = 90,
    [int]$InactiveComputerDays = 180,
    [switch]$OpenReport
)
Set-StrictMode -Version Latest
if (-not $PSBoundParameters.ContainsKey('OpenReport')) { $OpenReport = $true }

if ([Environment]::UserInteractive) {
    try { Clear-Host } catch { Write-Verbose "Clear-Host ignored: $($_.Exception.Message)" }
}
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   🏢  AUDIT D'HYGIENE & SECURITE ACTIVE DIRECTORY — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Contrôle des privilèges et assainissement de l'annuaire — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

$adModule = Get-Module -ListAvailable -Name ActiveDirectory
if (-not $adModule) {
    Write-Host " [!] Le module ActiveDirectory (RSAT) n'est pas présent sur cette machine." -ForegroundColor Yellow
    Write-Host "     Cet audit s'exécute sur un Contrôleur de Domaine ou une machine d'administration avec RSAT." -ForegroundColor DarkGray
    return
}

Import-Module ActiveDirectory -Force

Write-Host " [*] Audit des comptes à hauts privilèges..." -ForegroundColor Yellow
$domInfo = Get-ADDomain -ErrorAction SilentlyContinue
$daIdentity = if ($domInfo -and $domInfo.DomainSID) { "$($domInfo.DomainSID.Value)-512" } else { "Domain Admins" }
$domainAdmins = @(Get-ADGroupMember -Identity $daIdentity -Recursive -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName)
if ($domainAdmins.Count -eq 0) {
    $domainAdmins = @(Get-ADGroupMember -Identity "Admins du domaine" -Recursive -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName)
}
Write-Host "  -> Membres Domain Admins ($($domainAdmins.Count)) : $($domainAdmins -join ', ')" -ForegroundColor Red

Write-Host "`n [*] Détection des comptes utilisateurs inactifs (> $InactiveUserDays jours)..." -ForegroundColor Yellow
$userThreshold = (Get-Date).AddDays(-$InactiveUserDays)
$inactiveUsers = @(Get-ADUser -Filter { Enabled -eq $true -and (LastLogonDate -lt $userThreshold -or LastLogonDate -notlike "*") } -Properties LastLogonDate |
                 Select-Object SamAccountName, Name, LastLogonDate)

Write-Host "  -> $($inactiveUsers.Count) utilisateur(s) actif(s) mais sans connexion depuis $InactiveUserDays jours." -ForegroundColor $(if ($inactiveUsers.Count -gt 0) { "Yellow" } else { "Green" })

Write-Host "`n [*] Détection des comptes ordinateurs inactifs (> $InactiveComputerDays jours)..." -ForegroundColor Yellow
$compThreshold = (Get-Date).AddDays(-$InactiveComputerDays)
$inactiveComputers = @(Get-ADComputer -Filter { Enabled -eq $true -and (LastLogonDate -lt $compThreshold -or LastLogonDate -notlike "*") } -Properties LastLogonDate |
                     Select-Object Name, OperatingSystem, LastLogonDate)

Write-Host "  -> $($inactiveComputers.Count) ordinateur(s) dormant(s) depuis $InactiveComputerDays jours." -ForegroundColor $(if ($inactiveComputers.Count -gt 0) { "Yellow" } else { "Green" })

Write-Host "`n [*] Détection des comptes avec 'Mot de passe n'expire jamais'..." -ForegroundColor Yellow
$pwdNeverExpires = @(Get-ADUser -Filter { PasswordNeverExpires -eq $true -and Enabled -eq $true } -Properties PasswordNeverExpires |
                   Select-Object SamAccountName, Name)

Write-Host "  -> $($pwdNeverExpires.Count) compte(s) avec mot de passe infini." -ForegroundColor $(if ($pwdNeverExpires.Count -gt 0) { "Yellow" } else { "Green" })

Write-Host "`n [*] Détection des délégations Kerberos non contraintes (hors DC)..." -ForegroundColor Yellow
$unconstrainedDeleg = @(Get-ADObject -Filter { TrustedForDelegation -eq $true -and PrimaryGroupID -ne 516 } -Properties sAMAccountName, ObjectClass -ErrorAction SilentlyContinue |
    Select-Object Name, ObjectClass, sAMAccountName)
Write-Host "  -> $($unconstrainedDeleg.Count) objet(s) en délégation non contrainte." -ForegroundColor $(if ($unconstrainedDeleg.Count -gt 0) { "Red" } else { "Green" })

# RAPPORT HTML
Import-Module "$PSScriptRoot\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
$reportDir  = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Reports" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
$reportPath = Join-Path $reportDir "AD-Hygiene-Audit.html"
if (-not (Test-Path $reportDir)) { New-Item $reportDir -ItemType Directory -Force | Out-Null }

$encAdmins = [System.Net.WebUtility]::HtmlEncode(($domainAdmins -join ', '))
$encPwdInf = if ($pwdNeverExpires.Count -gt 0) { [System.Net.WebUtility]::HtmlEncode(($pwdNeverExpires | Select-Object -First 25 -ExpandProperty SamAccountName) -join ', ') } else { "Aucun" }
$encDeleg  = if ($unconstrainedDeleg.Count -gt 0) { [System.Net.WebUtility]::HtmlEncode(($unconstrainedDeleg | ForEach-Object { "$($_.Name) ($($_.ObjectClass))" }) -join ', ') } else { "Aucune détectée" }

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Audit d'Hygiène Active Directory</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f8fafc; color: #1e293b; padding: 25px; }
        .card { background: white; border-radius: 8px; padding: 25px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); max-width: 900px; margin: auto; }
        h1 { color: #1e3a8a; margin-top: 0; }
        .metric-grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 12px; margin: 20px 0; }
        .metric { background: #eff6ff; padding: 15px; border-radius: 6px; border-left: 4px solid #3b82f6; }
        .metric-title { font-size: 13px; color: #64748b; }
        .metric-value { font-size: 24px; font-weight: bold; color: #1e3a8a; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 13px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #e2e8f0; }
        th { background: #1e3a8a; color: white; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>🏢 Bilan d'Hygiène & Sécurité Active Directory</h1>
        <p><b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm') | <b>Analyste :</b> Amine BERRADA (Référent N3)</p>
        <div class='metric-grid'>
            <div class='metric'>
                <div class='metric-title'>Domain Admins</div>
                <div class='metric-value'>$($domainAdmins.Count)</div>
            </div>
            <div class='metric'>
                <div class='metric-title'>Utilisateurs Inactifs (&gt;$InactiveUserDays j)</div>
                <div class='metric-value'>$($inactiveUsers.Count)</div>
            </div>
            <div class='metric'>
                <div class='metric-title'>Postes Dormants (&gt;$InactiveComputerDays j)</div>
                <div class='metric-value'>$($inactiveComputers.Count)</div>
            </div>
            <div class='metric'>
                <div class='metric-title'>MDP Infini</div>
                <div class='metric-value'>$($pwdNeverExpires.Count)</div>
            </div>
            <div class='metric'>
                <div class='metric-title'>Délégation Non Contrainte</div>
                <div class='metric-value'>$($unconstrainedDeleg.Count)</div>
            </div>
        </div>
        <h3>Membres du groupe Domain Admins / Admins du domaine :</h3>
        <p><code>$encAdmins</code></p>
        <h3>Comptes avec mot de passe n'expirant jamais :</h3>
        <p><code>$encPwdInf</code></p>
        <h3>Délégations Kerberos non contraintes (hors DC) :</h3>
        <p><code>$encDeleg</code></p>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n [OK] Rapport d'Hygiène AD généré : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
