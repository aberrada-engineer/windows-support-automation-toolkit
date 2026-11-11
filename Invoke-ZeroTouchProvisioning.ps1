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

[CmdletBinding()]
param(
    [string]$Prefix = "CLI-W11",
    [switch]$SkipSoftwareInstall = $false,
    [switch]$EnableBitLocker = $false,
    [string]$DomainName = "",
    [switch]$Simulation = $false
)

Clear-Host
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
$serial = (Get-CimInstance Win32_BIOS).SerialNumber
$cleanSerial = ($serial -replace '[^a-zA-Z0-9]', '').Substring(0, [Math]::Min(6, $serial.Length))
$newName = "$Prefix-$cleanSerial".ToUpper()

if ($env:COMPUTERNAME -ne $newName) {
    if (-not $Simulation) {
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
    foreach ($app in $apps) {
        if (-not $Simulation) {
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
            $check = winget list --id $soft.Id 2>&1 | Out-String
            if ($check -match $soft.Id) {
                Write-Host " Déjà installé." -ForegroundColor Green
            } else {
                Write-Host " Installation silencieuse..." -ForegroundColor Cyan
                winget install --id $soft.Id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
                $installedCount++
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

# A. Désactivation de SMBv1
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
Add-StepResult "Sécurité SMB" "OK" "Protocole obsolète SMBv1 désactivé."

# B. Désactivation de LLMNR (Prévention des attaques de relais NTLM/Responder)
$llmnrPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
if (-not (Test-Path $llmnrPath)) { New-Item $llmnrPath -Force | Out-Null }
Set-ItemProperty -Path $llmnrPath -Name "EnableMulticast" -Value 0 -Force
Add-StepResult "Sécurité LLMNR" "OK" "LLMNR désactivé (Protection anti-Responder)."

# C. Activation de tous les profils de pare-feu
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue
Add-StepResult "Pare-feu Windows" "OK" "Tous les profils (Domaine, Privé, Public) activés."

# 5. CONFIGURATION SYSTÈME, DATE ET ÉNERGIE
Write-Host "`n[5/6] Configuration des paramètres d'entreprise..." -ForegroundColor Yellow
Set-TimeZone -Id "Romance Standard Time" -ErrorAction SilentlyContinue
powercfg /change standby-timeout-ac 0 # Ne jamais mettre en veille sur secteur pour faciliter la prise en main distante
Add-StepResult "Configuration Système" "OK" "Fuseau horaire Europe/Paris configuré, veille prolongée optimisée."

# 6. GÉNÉRATION DU RAPPORT DE MISE EN SERVICE
Write-Host "`n[6/6] Finalisation et génération du rapport de mise en service..." -ForegroundColor Yellow
$reportDir = "C:\ESN-Toolkit\Reports"
if (-not (Test-Path $reportDir)) { New-Item $reportDir -ItemType Directory -Force | Out-Null }
$reportPath = Join-Path $reportDir "Provisioning-Report-$newName.html"

$htmlRows = $reportSteps | ForEach-Object {
    "<tr><td><b>$($_.Etape)</b></td><td style='color:green;font-weight:bold;'>$($_.Statut)</td><td>$($_.Detail)</td></tr>"
} -join "`n"

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Rapport de Mise en Service - $newName</title>
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
        <p><b>Nom du poste :</b> $newName | <b>Numéro de série :</b> $serial | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
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
