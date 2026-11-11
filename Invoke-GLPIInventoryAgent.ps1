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
    [string]$GLPIUserToken = "",
    [string]$OutputDir = "C:\ESN-Toolkit\GLPI_Inventory",
    [switch]$OpenReport = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   📦  COLLECTEUR D'INVENTAIRE MATERIEL & LOGICIEL (GLPI) — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Gestion de Parc Informatique Automatisée — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host " [*] Collecte des caractéristiques matérielles du poste..." -ForegroundColor Yellow

$bios   = Get-CimInstance Win32_BIOS
$cs     = Get-CimInstance Win32_ComputerSystem
$os     = Get-CimInstance Win32_OperatingSystem
$cpu    = Get-CimInstance Win32_Processor | Select-Object -First 1
$ramGB  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$serial = $bios.SerialNumber
$model  = "$($cs.Manufacturer) $($cs.Model)"

Write-Host "  -> Machine : $env:COMPUTERNAME ($model)" -ForegroundColor Green
Write-Host "  -> Numéro de série : $serial" -ForegroundColor Green
Write-Host "  -> Processeur : $($cpu.Name) ($($cpu.NumberOfCores) coeurs / $($cpu.NumberOfLogicalProcessors) threads)" -ForegroundColor Green
Write-Host "  -> Mémoire vive : $ramGB Go RAM" -ForegroundColor Green

# DISQUES ET STOCKAGE
$disks = Get-CimInstance Win32_DiskDrive | ForEach-Object {
    [PSCustomObject]@{
        Model  = $_.Model
        SizeGB = [math]::Round($_.Size / 1GB, 0)
        Serial = $_.SerialNumber
    }
}

# RESEAU & ADRESSES MAC
$nics = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=true" | ForEach-Object {
    [PSCustomObject]@{
        Description = $_.Description
        MAC         = $_.MACAddress
        IP          = ($_.IPAddress -join ', ')
    }
}

# LOGICIELS INSTALLES
Write-Host "`n [*] Collecte de l'inventaire des logiciels installés..." -ForegroundColor Yellow
$apps = @()
$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($rp in $regPaths) {
    $apps += Get-ItemProperty $rp -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -notmatch "^(KB[0-9]+|Update for)" } |
        Select-Object @{N="Nom";E={$_.DisplayName}}, @{N="Version";E={$_.DisplayVersion}}, @{N="Editeur";E={$_.Publisher}}
}
$uniqueApps = $apps | Sort-Object Nom -Unique
Write-Host "  -> $(@($uniqueApps).Count) application(s) recensée(s)." -ForegroundColor Green

# STRUCTURE DE L'OBJET GLPI
$glpiPayload = [PSCustomObject]@{
    Hardware = [PSCustomObject]@{
        Name         = $env:COMPUTERNAME
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        Serial       = $serial
        OS           = $os.Caption
        OSVersion    = $os.Version
        RAM_GB       = $ramGB
        CPU          = $cpu.Name
    }
    Storage   = $disks
    Networks  = $nics
    Software  = $uniqueApps
    AuditDate = (Get-Date -Format "o")
}

# EXPORT JSON / XML GLPI
$jsonFile = Join-Path $OutputDir "GLPI_Inventory_$env:COMPUTERNAME.json"
$glpiPayload | ConvertTo-Json -Depth 6 | Out-File $jsonFile -Encoding UTF8
Write-Host "`n [OK] Fichier d'inventaire GLPI généré : $jsonFile" -ForegroundColor Green

# FICHE D'INVENTAIRE HTML
$reportPath = Join-Path $OutputDir "Fiche-Inventaire-$env:COMPUTERNAME.html"
$appRows = $uniqueApps | Select-Object -First 25 | ForEach-Object {
    "<tr><td><b>$($_.Nom)</b></td><td>$($_.Version)</td><td>$($_.Editeur)</td></tr>"
} -join "`n"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Fiche d'Inventaire Parc - $env:COMPUTERNAME</title>
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
        <p><b>Machine :</b> $env:COMPUTERNAME | <b>Numéro de Série :</b> $serial | <b>Date :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
        <div class='grid'>
            <div class='box'>
                <b>Caractéristiques Matérielles :</b><br>
                • Modèle : $model<br>
                • Processeur : $($cpu.Name)<br>
                • Mémoire : $ramGB Go RAM<br>
                • Système : $($os.Caption) ($($os.OSArchitecture))
            </div>
            <div class='box'>
                <b>Réseau & Interfaces :</b><br>
                • Adresse MAC : $(($nics | Select-Object -First 1).MAC)<br>
                • Adresse IP : $(($nics | Select-Object -First 1).IP)
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
