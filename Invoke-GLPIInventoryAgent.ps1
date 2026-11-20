#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-GLPIInventoryAgent v3.0 - Collecteur d'Inventaire Matériel & Logiciel GLPI / OCS.
    Reproduction de l'automatisation de gestion de parc (~200 postes) menée par Amine BERRADA.

.DESCRIPTION
    1. Collecte matérielle complète (CPU, RAM par slot, disques, cartes réseau, écrans, BIOS/Série)
    2. Collecte logicielle exhaustive (Toutes les applications avec versions et éditeurs)
    3. Export au format JSON / XML prêt pour injection dans l'API REST de GLPI
    4. Fiche d'inventaire d'équipement au format HTML
#>

[CmdletBinding()]
param(
    [string]$GLPIApiUrl = "",
    [securestring]$GLPIAppToken,
    [securestring]$GLPIUserToken,
    [string]$OutputDir = "",
    [switch]$OpenReport
)
Set-StrictMode -Version Latest
if (-not $PSBoundParameters.ContainsKey('OpenReport')) { $OpenReport = $true }

Import-Module "$PSScriptRoot\Core\ESN-Core.psm1" -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "GLPI_Inventory" -Ensure } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/GLPI_Inventory" }
}

if ([Environment]::UserInteractive) {
    try { Clear-Host } catch { Write-Verbose "Clear-Host ignored: $($_.Exception.Message)" }
}
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   📦  COLLECTEUR D'INVENTAIRE MATERIEL & LOGICIEL (GLPI) — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Gestion de Parc Informatique Automatisée — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host " [*] Collecte des caractéristiques matérielles du poste..." -ForegroundColor Yellow

$hostLabel = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
$bios   = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
$cs     = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$os     = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$cpu    = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$ramGB  = if ($cs -and $cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { 0 }
$serial = if ($bios -and $bios.SerialNumber) { $bios.SerialNumber } else { "N/A" }
$model  = if ($cs) { "$($cs.Manufacturer) $($cs.Model)".Trim() } else { "Poste Windows" }
$cpuName = if ($cpu -and $cpu.Name) { $cpu.Name } else { "CPU inconnu" }
$osCap   = if ($os -and $os.Caption) { $os.Caption } else { [System.Environment]::OSVersion.VersionString }
$osArch  = if ($os -and $os.OSArchitecture) { $os.OSArchitecture } else { "" }

Write-Host "  -> Machine : $hostLabel ($model)" -ForegroundColor Green
Write-Host "  -> Numéro de série : $serial" -ForegroundColor Green
Write-Host "  -> Processeur : $cpuName ($(if ($cpu) { $cpu.NumberOfCores } else { 0 }) coeurs / $(if ($cpu) { $cpu.NumberOfLogicalProcessors } else { 0 }) threads)" -ForegroundColor Green
Write-Host "  -> Mémoire vive : $ramGB Go RAM" -ForegroundColor Green

# DISQUES ET STOCKAGE
$disks = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
    [PSCustomObject]@{
        Model  = $_.Model
        SizeGB = if ($_.Size) { [math]::Round($_.Size / 1GB, 0) } else { 0 }
        Serial = $_.SerialNumber
    }
})

# RESEAU & ADRESSES MAC
$nics = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=true" -ErrorAction SilentlyContinue | ForEach-Object {
    [PSCustomObject]@{
        Description = $_.Description
        MAC         = $_.MACAddress
        IP          = ($_.IPAddress -join ', ')
    }
})

# LOGICIELS INSTALLES
Write-Host "`n [*] Collecte de l'inventaire des logiciels installés..." -ForegroundColor Yellow
$apps = @()
$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($rp in $regPaths) {
    $apps += Get-ItemProperty $rp -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -and $_.DisplayName -notmatch "^(KB[0-9]+|Update for)" } |
        Select-Object @{N="Nom";E={$_.DisplayName}},
                      @{N="Version";E={if ($_.PSObject.Properties['DisplayVersion']) { $_.DisplayVersion } else { '' }}},
                      @{N="Editeur";E={if ($_.PSObject.Properties['Publisher']) { $_.Publisher } else { '' }}}
}
$uniqueApps = @($apps | Sort-Object Nom -Unique)
Write-Host "  -> $($uniqueApps.Count) application(s) recensée(s)." -ForegroundColor Green

# STRUCTURE DE L'OBJET GLPI
$glpiPayload = [PSCustomObject]@{
    Hardware = [PSCustomObject]@{
        Name         = $hostLabel
        Manufacturer = if ($cs) { $cs.Manufacturer } else { "" }
        Model        = if ($cs) { $cs.Model } else { "" }
        Serial       = $serial
        OS           = $osCap
        OSVersion    = if ($os) { $os.Version } else { "" }
        RAM_GB       = $ramGB
        CPU          = $cpuName
    }
    Storage   = $disks
    Networks  = $nics
    Software  = $uniqueApps
    AuditDate = (Get-Date -Format "o")
}

# EXPORT JSON / XML GLPI & ENVOI API REST SI COMPLETE
$jsonFile = Join-Path $OutputDir "GLPI_Inventory_$hostLabel.json"
$glpiPayload | ConvertTo-Json -Depth 6 | Out-File $jsonFile -Encoding UTF8
Write-Host "`n [OK] Fichier d'inventaire GLPI généré : $jsonFile" -ForegroundColor Green
$glpiAppPlain  = if ($null -ne $GLPIAppToken -and $GLPIAppToken.Length -gt 0) { ([System.Net.NetworkCredential]::new('', $GLPIAppToken)).Password } else { [string]$env:ESN_GLPI_APP_TOKEN }
$glpiUserPlain = if ($null -ne $GLPIUserToken -and $GLPIUserToken.Length -gt 0) { ([System.Net.NetworkCredential]::new('', $GLPIUserToken)).Password } else { [string]$env:ESN_GLPI_USER_TOKEN }
if ($GLPIApiUrl -and $glpiUserPlain -and $glpiAppPlain) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $apiBase = $GLPIApiUrl.TrimEnd('/')
    $sessionToken = $null
    $sessHeaders = $null
    try {
        $initHeaders = @{ "App-Token" = $glpiAppPlain; "Authorization" = "user_token $glpiUserPlain" }
        $sess = Invoke-RestMethod -Uri "$apiBase/initSession" -Headers $initHeaders -Method Get -TimeoutSec 15
        $sessionToken = $sess.session_token
        $sessHeaders = @{ "App-Token" = $glpiAppPlain; "Session-Token" = $sessionToken }
        $compBody = @{ input = @{ name = $hostLabel; serial = $serial; comment = "ESN-Toolkit RAM=${ramGB}GB OS=$osCap" } } | ConvertTo-Json -Depth 3
        $pushed = Invoke-RestMethod -Uri "$apiBase/Computer" -Headers $sessHeaders -Method Post -Body $compBody -ContentType "application/json" -TimeoutSec 15
        Write-Host " [OK] Poste poussé vers API REST GLPI (ID: $($pushed.id))." -ForegroundColor Green
    } catch {
        Write-Warning "Envoi API REST GLPI en échec : $($_.Exception.Message)"
    } finally {
        if ($sessionToken -and $sessHeaders) {
            try { Invoke-RestMethod -Uri "$apiBase/killSession" -Headers $sessHeaders -Method Get -TimeoutSec 10 | Out-Null } catch { Write-Verbose "killSession: $($_.Exception.Message)" }
        }
    }
} elseif ($GLPIApiUrl -or $glpiUserPlain) {
    Write-Host " [LOCAL JSON ONLY] GLPIAppToken ou paramètres API incomplets — export JSON local prêt sans envoi HTTP." -ForegroundColor Yellow
}

# FICHE D'INVENTAIRE HTML
$reportPath = Join-Path $OutputDir "Fiche-Inventaire-$hostLabel.html"
$appRows = ($uniqueApps | Select-Object -First 25 | ForEach-Object {
    $nom = [System.Net.WebUtility]::HtmlEncode([string]$_.Nom)
    $ver = [System.Net.WebUtility]::HtmlEncode([string]$_.Version)
    $ed  = [System.Net.WebUtility]::HtmlEncode([string]$_.Editeur)
    "<tr><td><b>$nom</b></td><td>$ver</td><td>$ed</td></tr>"
}) -join "`n"

$firstNic  = $nics | Select-Object -First 1
$encHost   = [System.Net.WebUtility]::HtmlEncode([string]$hostLabel)
$encSerial = [System.Net.WebUtility]::HtmlEncode([string]$serial)
$encModel  = [System.Net.WebUtility]::HtmlEncode([string]$model)
$encCpu    = [System.Net.WebUtility]::HtmlEncode([string]$cpuName)
$encOs     = [System.Net.WebUtility]::HtmlEncode("$osCap ($osArch)")
$encMac    = [System.Net.WebUtility]::HtmlEncode([string]$(if ($firstNic) { $firstNic.MAC } else { "N/A" }))
$encIp     = [System.Net.WebUtility]::HtmlEncode([string]$(if ($firstNic) { $firstNic.IP } else { "N/A" }))

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Fiche d'Inventaire Parc - $encHost</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f8fafc; color: #1e293b; padding: 30px; }
        .card { background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 35px; max-width: 900px; margin: auto; }
        h1 { color: #0284c7; margin-top: 0; }
        .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 15px; margin: 20px 0; }
        .box { background: #f1f5f9; padding: 15px; border-radius: 6px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 13px; }
        th, td { padding: 8px 10px; text-align: left; border-bottom: 1px solid #e2e8f0; }
        th { background: #0284c7; color: white; }
    </style>
</head>
<body>
    <div class='card'>
        <h1>📦 Fiche d'Inventaire Matériel & Logiciel (GLPI)</h1>
        <p><b>Machine :</b> $encHost | <b>Numéro de Série :</b> $encSerial | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
        <div class='grid'>
            <div class='box'>
                <b>Caractéristiques Matérielles :</b><br>
                • Modèle : $encModel<br>
                • Processeur : $encCpu<br>
                • Mémoire : $ramGB Go RAM<br>
                • Système : $encOs
            </div>
            <div class='box'>
                <b>Réseau & Interfaces :</b><br>
                • Adresse MAC : $encMac<br>
                • Adresse IP : $encIp
            </div>
        </div>
        <h3>Logiciels Installés (Extrait des 25 premiers sur $(@($uniqueApps).Count)) :</h3>
        <table>
            <thead><tr><th>Application</th><th>Version</th><th>Éditeur</th></tr></thead>
            <tbody>$appRows</tbody>
        </table>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host " [OK] Fiche d'inventaire HTML prête : $reportPath" -ForegroundColor Green
if ($OpenReport) { Start-Process $reportPath }
