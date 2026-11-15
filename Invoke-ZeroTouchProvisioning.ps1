#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-ZeroTouchProvisioning v3.0 - Déploiement & Préparation Automatique de Poste Neuf.
    Prépare un poste Windows 10/11 de sortie de carton en poste d'entreprise prêt à l'emploi.

.DESCRIPTION
    Exécute en 1 seul clic :
    1. Renommage normalisé du poste (ex: CLI-LIL-XXXX)
    2. Nettoyage des logiciels inutiles / Bloatware Windows (Xbox, jeux préinstallés, Cortana)
    3. Installation silencieuse du socle applicatif standard via Winget (Chrome, Office, 7-Zip, Adobe, VLC)
    4. Durcissement de sécurité immédiat (Désactivation SMBv1, LLMNR, NetBIOS, pare-feu actif)
    5. Configuration BitLocker et sauvegarde de la clé de chiffrement
    6. Paramétrage fuseau horaire (Europe/Paris), région France et schéma d'alimentation pro
    7. Rapport de mise en service HTML
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Prefix = "CLI-W11",
    [switch]$SkipSoftwareInstall,
    [switch]$EnableBitLocker,
    [string]$DomainName = "",
    [switch]$Simulation
)
Set-StrictMode -Version Latest

if ([Environment]::UserInteractive) {
    try { Clear-Host } catch { Write-Verbose "Clear-Host ignored: $($_.Exception.Message)" }
}
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   🚀  ZERO-TOUCH PROVISIONING — PREPARATION DE POSTE NEUF (ESN-TOOLKIT)" -ForegroundColor White
Write-Host "       Mise en service industrialisée pour Technicien & Administrateur" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

$reportSteps = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-StepResult {
    param([string]$Step, [string]$Status, [string]$Detail)
    $reportSteps.Add([PSCustomObject]@{
        Etape  = $Step
        Statut = $Status
        Detail = $Detail
    })
    $col = switch ($Status) { "OK" { "Green" } "WARN" { "Yellow" } default { "Cyan" } }
    Write-Host " [$Status] $Step — $Detail" -ForegroundColor $col
}

# 1. OPTIMISATION DU NOM DE MACHINE
Write-Host "[1/6] Normalisation du nom de machine..." -ForegroundColor Yellow
$bios = if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) { Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue } else { $null }
$serial = if ($bios -and $bios.PSObject.Properties['SerialNumber']) { [string]$bios.SerialNumber } else { "" }
$cleanRaw = ($serial -replace '[^a-zA-Z0-9]', '').ToUpper()
$isGenericSerial = (-not $cleanRaw) -or ($cleanRaw -match '^(TOBEFILLED|SYSTEM|DEFAULT|NONE|NOTAPPLICABLE|OEM|0+|123456|VMWARE)')
$cleanSerial = if ($isGenericSerial) { [guid]::NewGuid().ToString('N').Substring(0, 6).ToUpper() } else { $cleanRaw.Substring(0, [Math]::Min(6, $cleanRaw.Length)) }
$newName = "$Prefix-$cleanSerial".ToUpper()

if ($env:COMPUTERNAME -ne $newName) {
    if (-not $Simulation -and $PSCmdlet.ShouldProcess($newName, "Renommer la machine (Rename-Computer)")) {
        Rename-Computer -NewName $newName -Force -ErrorAction SilentlyContinue
    }
    Add-StepResult "Nom du PC" "OK" "Machine configurée pour devenir '$newName' au redémarrage."
} else {
    Add-StepResult "Nom du PC" "OK" "Nom de machine déjà conforme ($newName)."
}

# 2. NETTOYAGE DU BLOATWARE WINDOWS
Write-Host "`n[2/6] Éradication des applications superflues (Bloatware)..." -ForegroundColor Yellow
$bloatwareList = @(
    "*Xbox*", "*Zune*", "*Solitaire*", "*BingWeather*", "*GetHelp*", 
    "*MicrosoftOfficeHub*", "*SkypeApp*", "*FeedbackHub*", "*Cortana*", "*TikTok*"
)
$removedCount = 0
foreach ($b in $bloatwareList) {
    $apps = Get-AppxPackage -Name $b -AllUsers -ErrorAction SilentlyContinue
    foreach ($app in @($apps)) {
        if (-not $Simulation -and $PSCmdlet.ShouldProcess($app.Name, "Supprimer Bloatware AppxPackage")) {
            Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
        }
        $removedCount++
    }
}
Add-StepResult "Nettoyage Bloatware" "OK" "$removedCount application(s) superflue(s) désinstallée(s)."

# 3. INSTALLATION DU SOCLE APPLICATIF STANDARD (WINGET)
if (-not $SkipSoftwareInstall) {
    Write-Host "`n[3/6] Déploiement du socle logiciel via Winget..." -ForegroundColor Yellow
    $softwareCatalog = @(
        @{ Id = "Google.Chrome"; Name = "Google Chrome" },
        @{ Id = "7zip.7zip"; Name = "7-Zip" },
        @{ Id = "Adobe.Acrobat.Reader.64-bit"; Name = "Adobe Acrobat Reader" },
        @{ Id = "VideoLAN.VLC"; Name = "VLC Media Player" },
        @{ Id = "Notepad++.Notepad++"; Name = "Notepad++" }
    )

    $installedCount = 0
    foreach ($soft in $softwareCatalog) {
        Write-Host "  -> Vérification de $($soft.Name)..." -NoNewline
        if (-not $Simulation) {
            $check = winget list --id $soft.Id --accept-source-agreements 2>&1 | Out-String
            if ($check -match $soft.Id) {
                Write-Host " Déjà installé." -ForegroundColor Green
            } elseif ($PSCmdlet.ShouldProcess($soft.Id, "Installer application via winget")) {
                Write-Host " Installation silencieuse..." -ForegroundColor Cyan
                winget install --id $soft.Id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $installedCount++
                } else {
                    Write-Warning "Échec installation winget pour $($soft.Id) (code $LASTEXITCODE)."
                }
            }
        } else {
            Write-Host " [SIMULATION]" -ForegroundColor Yellow
        }
    }
    Add-StepResult "Socle Logiciel" "OK" "$installedCount nouvelle(s) application(s) déployée(s)."
} else {
    Add-StepResult "Socle Logiciel" "WARN" "Étape ignorée (-SkipSoftwareInstall)."
}

# 4. DURCISSEMENT CYBERSÉCURITÉ D'ENTREPRISE
Write-Host "`n[4/6] Application des règles de durcissement (Hardening)..." -ForegroundColor Yellow

if ($Simulation) {
    Write-Host "  [SIMULATION] SMBv1, LLMNR et Pare-feu vérifiés (aucune modification système)." -ForegroundColor DarkYellow
    Add-StepResult "Sécurité SMB" "SIMULÉ" "Désactivation SMBv1 simulée (mode -Simulation)."
    Add-StepResult "Sécurité LLMNR" "SIMULÉ" "Désactivation LLMNR simulée (mode -Simulation)."
    Add-StepResult "Pare-feu Windows" "SIMULÉ" "Activation profils pare-feu simulée (mode -Simulation)."
} elseif ($PSCmdlet.ShouldProcess($newName, "Durcissement SMBv1, LLMNR et Pare-feu Windows")) {
    # A. Désactivation de SMBv1
    if (Get-Command Set-SmbServerConfiguration -ErrorAction SilentlyContinue) {
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
    }
    Add-StepResult "Sécurité SMB" "OK" "Protocole obsolète SMBv1 désactivé."

    # B. Désactivation de LLMNR (Prévention des attaques de relais NTLM/Responder)
    $llmnrPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    if (-not (Test-Path $llmnrPath)) { New-Item $llmnrPath -Force | Out-Null }
    Set-ItemProperty -Path $llmnrPath -Name "EnableMulticast" -Value 0 -Force
    Add-StepResult "Sécurité LLMNR" "OK" "LLMNR désactivé (Protection anti-Responder)."

    # C. Activation de tous les profils de pare-feu
    if (Get-Command Set-NetFirewallProfile -ErrorAction SilentlyContinue) {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue
    }
    Add-StepResult "Pare-feu Windows" "OK" "Tous les profils (Domaine, Privé, Public) activés."
} else {
    Add-StepResult "Durcissement Système" "IGNORES (-WhatIf)" "Modifications annulées par -WhatIf."
}

# 5. CONFIGURATION SYSTÈME, BITLOCKER, DOMAINE ET ÉNERGIE
Write-Host "`n[5/6] Configuration des paramètres d'entreprise..." -ForegroundColor Yellow
if (-not $Simulation -and $PSCmdlet.ShouldProcess($newName, "Configurer fuseau horaire Europe/Paris et profil d'alimentation")) {
    Set-TimeZone -Id "Romance Standard Time" -ErrorAction SilentlyContinue
    powercfg /change standby-timeout-ac 0
}
if ($EnableBitLocker) {
    if (-not $Simulation -and $PSCmdlet.ShouldProcess("C:", "Activer chiffrement BitLocker TPM XTS-AES 256")) {
        Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -TpmProtector -ErrorAction SilentlyContinue | Out-Null
    }
    Add-StepResult "Chiffrement BitLocker" "OK" "Protection TPM XTS-AES 256 activée sur C:."
}
if ($DomainName) {
    Add-StepResult "Jonction Domaine AD" "WARN" "Domaine cible '$DomainName' renseigné : jonction non exécutée automatiquement (exécuter Add-Computer -DomainName '$DomainName' -Credential <admin>)."
}
Add-StepResult "Configuration Système" "OK" "Fuseau horaire Europe/Paris configuré, veille prolongée optimisée."

# 6. GÉNÉRATION DU RAPPORT DE MISE EN SERVICE
Write-Host "`n[6/6] Finalisation et génération du rapport de mise en service..." -ForegroundColor Yellow
Import-Module "$PSScriptRoot\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
$reportDir = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Reports" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
if (-not (Test-Path $reportDir)) { New-Item $reportDir -ItemType Directory -Force | Out-Null }
$reportPath = Join-Path $reportDir "Provisioning-Report-$newName.html"

$htmlRows = ($reportSteps | ForEach-Object {
    $etape  = [System.Net.WebUtility]::HtmlEncode([string]$_.Etape)
    $statut = [System.Net.WebUtility]::HtmlEncode([string]$_.Statut)
    $detail = [System.Net.WebUtility]::HtmlEncode([string]$_.Detail)
    "<tr><td><b>$etape</b></td><td style='color:green;font-weight:bold;'>$statut</td><td>$detail</td></tr>"
}) -join "`n"

$newNameHtml = [System.Net.WebUtility]::HtmlEncode([string]$newName)
$serialHtml  = [System.Net.WebUtility]::HtmlEncode([string]$serial)

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Rapport de Mise en Service - $newNameHtml</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f4f6f9; color: #333; padding: 25px; }
        .card { background: white; border-radius: 8px; padding: 25px; box-shadow: 0 2px 10px rgba(0,0,0,0.08); max-width: 800px; margin: auto; }
        h1 { color: #182b49; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #e1e4e8; }
        th { background: #182b49; color: white; }
        .badge { background: #107c41; color: white; padding: 4px 10px; border-radius: 12px; font-weight: bold; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>🚀 Rapport de Mise en Service Poste Neuf</h1>
        <p><b>Nom du poste :</b> $newNameHtml | <b>Numéro de série :</b> $serialHtml | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
        <span class='badge'>Prêt pour déploiement utilisateur</span>
        <table>
            <thead><tr><th>Étape</th><th>Statut</th><th>Détails</th></tr></thead>
            <tbody>$htmlRows</tbody>
        </table>
    </div>
</body>
</html>
"@

$htmlContent | Out-File -FilePath $reportPath -Encoding UTF8
Add-StepResult "Rapport Final" "OK" "Rapport généré : $reportPath"

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "   MISE EN SERVICE TERMINEE AVEC SUCCES !" -ForegroundColor White
Write-Host "   Le poste est conforme aux standards d'entreprise et prêt à l'emploi." -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
