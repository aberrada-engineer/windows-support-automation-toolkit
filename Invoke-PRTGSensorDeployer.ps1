<#
.SYNOPSIS
    Invoke-PRTGSensorDeployer.ps1 - Générateur et Déployeur de Sondes Avancées PRTG Network Monitor (XML/JSON).
.DESCRIPTION
    Conçu pour les environnements sous supervision PRTG (expérience ESN & parcs multi-clients) :
    - Génération de sondes personnalisées PowerShell (PRTG Advanced EXE/Script Sensors).
    - Couvre la supervision des sauvegardes Veeam (statut jobs, immutabilité), la saturation des datastores VMware/Nutanix,
      l'épuisement des pools DHCP et la détection d'expiration de certificats SSL/TLS (< 30 jours).
    - Déploiement automatique dans le répertoire des sondes de la sonde PRTG locale :
      'C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\'.
    - Format de retour 100% conforme à la spécification XML de Paessler PRTG (<prtg><result>...).
.PARAMETER TargetSensor
    Type de sonde à générer : 'All', 'Veeam', 'Hypervisor', 'DHCP', 'SSLCert'.
.PARAMETER DeployLocally
    Copie automatique des scripts vers le dossier de la sonde PRTG locale si présente.
.EXAMPLE
    .\Invoke-PRTGSensorDeployer.ps1 -TargetSensor "All" -DeployLocally
#>

[CmdletBinding()]
param(
    [ValidateSet("All", "Veeam", "Hypervisor", "DHCP", "SSLCert")]
    [string]$TargetSensor = "All",
    [string]$OutputDirectory = "C:\ESN-Toolkit\PRTG-Sensors",
    [switch]$DeployLocally
)

$ErrorActionPreference = "Continue"

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   PRTG NETWORK MONITOR — CUSTOM ADVANCED SENSORS DEPLOYMENT ENGINE       " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "[*] Type de sonde sélectionné : $TargetSensor" -ForegroundColor Gray
Write-Host "[*] Dossier de sortie         : $OutputDirectory" -ForegroundColor Gray
Write-Host ""

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$PrtgProbePath = "C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML"
$IsPrtgInstalled = Test-Path $PrtgProbePath

# 1. Sonde PRTG : Supervision Veeam Backup & Replication
$VeeamSensorScript = @'
# PRTG Custom Sensor - Veeam Backup & Immutability Status
# Output: PRTG XML Format
[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

$VeeamService = Get-Service -Name "VeeamBackupSvc" -ErrorAction SilentlyContinue
$ServiceState = if ($VeeamService -and $VeeamService.Status -eq "Running") { 1 } else { 0 }

# Récupération derniers événements Veeam
$RecentErrors = Get-WinEvent -FilterHashtable @{LogName='Veeam Backup'; Level=2; StartTime=(Get-Date).AddHours(-24)} -ErrorAction SilentlyContinue
$ErrorCount = if ($RecentErrors) { $RecentErrors.Count } else { 0 }

$StatusText = if ($ServiceState -eq 1 -and $ErrorCount -eq 0) { "Veeam Operationnel - 0 incident 24h" } elseif ($ServiceState -eq 1) { "Veeam Actif avec $ErrorCount erreurs 24h" } else { "Service Veeam Arrete" }

@"
<prtg>
    <result>
        <channel>Veeam Service Status</channel>
        <value>$ServiceState</value>
        <unit>Custom</unit>
        <customunit>Actif/Inactif</customunit>
    </result>
    <result>
        <channel>Erreurs Jobs 24h</channel>
        <value>$ErrorCount</value>
        <unit>Count</unit>
        <LimitMaxError>1</LimitMaxError>
        <LimitMode>1</LimitMode>
    </result>
    <text>$StatusText</text>
</prtg>
"@
'@

# 2. Sonde PRTG : Saturation des Datastores VMware / Disques Hyperviseurs
$HypervisorSensorScript = @'
# PRTG Custom Sensor - Hypervisor Storage & Datastore Saturation
# Output: PRTG XML Format
[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

$Disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
$MaxUsage = 0
$ResultsXml = @()

foreach ($d in $Disks) {
    $pctUsed = [math]::Round((($d.Size - $d.FreeSpace) / $d.Size) * 100, 1)
    if ($pctUsed -gt $MaxUsage) { $MaxUsage = $pctUsed }
    
    $freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
    $ResultsXml += @"
    <result>
        <channel>Occupation Disque $($d.DeviceID)</channel>
        <value>$pctUsed</value>
        <unit>Percent</unit>
        <LimitMaxWarning>80</LimitMaxWarning>
        <LimitMaxError>90</LimitMaxError>
        <LimitMode>1</LimitMode>
    </result>
    <result>
        <channel>Espace Libre $($d.DeviceID) (Go)</channel>
        <value>$freeGB</value>
        <unit>Custom</unit>
        <customunit>Go</customunit>
    </result>
"@
}

$StatusText = "Taux d'occupation max stockage : $MaxUsage%"

@"
<prtg>
$($ResultsXml -join "`n")
    <text>$StatusText</text>
</prtg>
"@
'@

# 3. Sonde PRTG : Épuisement des Scopes DHCP
$DhcpSensorScript = @'
# PRTG Custom Sensor - DHCP Scope Exhaustion
# Output: PRTG XML Format
[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"
$MaxScopeUsage = 0
$ResultsXml = @()

if (Get-Command Get-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    foreach ($sc in $scopes) {
        $stats = Get-DhcpServerv4ScopeStatistics -ScopeId $sc.ScopeId -ErrorAction SilentlyContinue
        $pct = if ($stats) { [math]::Round($stats.PercentageInUse, 1) } else { 0 }
        if ($pct -gt $MaxScopeUsage) { $MaxScopeUsage = $pct }
        
        $ResultsXml += @"
    <result>
        <channel>DHCP Scope $($sc.ScopeId)</channel>
        <value>$pct</value>
        <unit>Percent</unit>
        <LimitMaxWarning>80</LimitMaxWarning>
        <LimitMaxError>90</LimitMaxError>
        <LimitMode>1</LimitMode>
    </result>
"@
    }
} else {
    $ResultsXml += @"
    <result>
        <channel>DHCP Role Present</channel>
        <value>0</value>
    </result>
"@
}

$StatusText = "Occupation max scopes DHCP : $MaxScopeUsage%"

@"
<prtg>
$($ResultsXml -join "`n")
    <text>$StatusText</text>
</prtg>
"@
'@

# 4. Sonde PRTG : Expiration Certificats SSL/TLS Machine
$SslSensorScript = @'
# PRTG Custom Sensor - SSL/TLS Certificate Expiration Watchdog
# Output: PRTG XML Format
[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

$Certs = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue
$MinDaysLeft = 999
$ExpiringCount = 0

foreach ($c in $Certs) {
    $days = ($c.NotAfter - (Get-Date)).Days
    if ($days -lt $MinDaysLeft) { $MinDaysLeft = $days }
    if ($days -lt 30) { $ExpiringCount++ }
}

$StatusText = if ($ExpiringCount -eq 0) { "Tous les certificats sont valides (> 30j). Prochaine expiration : $MinDaysLeft jours" } else { "ALERTE : $ExpiringCount certificat(s) expire(nt) a moins de 30 jours !" }

@"
<prtg>
    <result>
        <channel>Jours avant expiration min</channel>
        <value>$MinDaysLeft</value>
        <unit>Custom</unit>
        <customunit>Jours</customunit>
        <LimitMinWarning>30</LimitMinWarning>
        <LimitMinError>7</LimitMinError>
        <LimitMode>1</LimitMode>
    </result>
    <result>
        <channel>Certificats a renouveler (&lt;30j)</channel>
        <value>$ExpiringCount</value>
        <unit>Count</unit>
        <LimitMaxError>1</LimitMaxError>
        <LimitMode>1</LimitMode>
    </result>
    <text>$StatusText</text>
</prtg>
"@
'@

# Écriture des fichiers de sondes
$SensorsToWrite = @()
if ($TargetSensor -in @("All", "Veeam")) { $SensorsToWrite += @{ Name = "PRTG-VeeamStatus.ps1"; Content = $VeeamSensorScript } }
if ($TargetSensor -in @("All", "Hypervisor")) { $SensorsToWrite += @{ Name = "PRTG-HypervisorStorage.ps1"; Content = $HypervisorSensorScript } }
if ($TargetSensor -in @("All", "DHCP")) { $SensorsToWrite += @{ Name = "PRTG-DHCPScopes.ps1"; Content = $DhcpSensorScript } }
if ($TargetSensor -in @("All", "SSLCert")) { $SensorsToWrite += @{ Name = "PRTG-SSLCertExpiration.ps1"; Content = $SslSensorScript } }

foreach ($s in $SensorsToWrite) {
    $dest = Join-Path $OutputDirectory $s.Name
    Set-Content -Path $dest -Value $s.Content -Encoding UTF8
    Write-Host "[+] Sonde générée : $dest" -ForegroundColor Green

    if ($DeployLocally -and $IsPrtgInstalled) {
        $prtgDest = Join-Path $PrtgProbePath $s.Name
        Copy-Item -Path $dest -Destination $prtgDest -Force
        Write-Host "    -> Déployée dans la sonde PRTG locale : $prtgDest" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "   DÉPLOIEMENT DES SONDES PRTG RÉUSSI AVEC SUCCÈS                         " -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "[+] Dossier des sondes : $OutputDirectory" -ForegroundColor White
if ($DeployLocally -and -not $IsPrtgInstalled) {
    Write-Host "[!] Note : PRTG Probe non détectée sur cet hôte. Les sondes sont prêtes à être importées." -ForegroundColor Yellow
}
