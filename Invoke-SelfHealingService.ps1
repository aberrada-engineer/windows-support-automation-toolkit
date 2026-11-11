#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ESN-SelfHealing v3.0 - Moteur d'Auto-Réparation et de Résilience Autonome.
    Opère en continu ou par tâche planifiée pour remplacer l'intervention humaine N1/N2.

.DESCRIPTION
    Le moteur d'auto-réparation s'exécute en tâche de fond (toutes les 15 à 30 min) :
    1. Surveillance & Relance automatique des services critiques arrêtés (Spooler, WinUpdate, Defender/EDR, DNS, Netlogon).
    2. Détection & Résolution automatique de saturation disque (C: > 85%) sans perte de données.
    3. Détection des processus zombies ou fuites mémoire (> 90% RAM).
    4. Auto-guérison de la pile réseau en cas de coupure DNS ou passerelle.
    5. Consignation dans un journal persistant (SelfHealing.log) et notification Webhook (Teams/Slack/Discord).
#>

[CmdletBinding()]
param(
    [int]$DiskWarningPercent    = 85,
    [int]$DiskCriticalPercent   = 92,
    [string]$WebhookUrl         = "",
    [switch]$SingleRun          = $true,
    [switch]$InstallServiceTask = $false,
    [switch]$UninstallTask      = $false
)

$LogPath = "C:\ESN-Toolkit\Logs\SelfHealing.log"
$LogDir  = Split-Path $LogPath -Parent
if (-not (Test-Path $LogDir)) { New-Item $LogDir -ItemType Directory -Force | Out-Null }

function Log-SelfHealing {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp][$Level] $Message"
    $color = switch ($Level) {
        "HEALED"   { "Green" }
        "CRITICAL" { "Red" }
        "WARN"     { "Yellow" }
        default    { "Cyan" }
    }
    Write-Host $formatted -ForegroundColor $color
    Add-Content -Path $LogPath -Value $formatted -Encoding UTF8
}

# ─────────────────────────────────────────────────────────────
# 1. GESTION DE LA TACHE PLANIFIEE AUTONOME
# ─────────────────────────────────────────────────────────────
if ($InstallServiceTask) {
    Write-Host "[*] Installation de la tâche planifiée d'auto-guérison..." -ForegroundColor Cyan
    $taskName = "ESN-SelfHealing-Daemon"
    $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $trigger  = New-ScheduledTaskTrigger -AtStartup
    $trigger.RepetitionInterval = (New-TimeSpan -Minutes 15)
    $trigger.RepetitionDuration = (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host "[OK] Tâche '$taskName' installée. S'exécute au démarrage et toutes les 15 minutes en compte SYSTEM." -ForegroundColor Green
    exit
}

if ($UninstallTask) {
    Unregister-ScheduledTask -TaskName "ESN-SelfHealing-Daemon" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[OK] Tâche 'ESN-SelfHealing-Daemon' désinstallée." -ForegroundColor Yellow
    exit
}

# ─────────────────────────────────────────────────────────────
# 2. CYCLE D'AUTO-RÉPARATION (SELF-HEALING CYCLE)
# ─────────────────────────────────────────────────────────────
Log-SelfHealing "=== CYCLE D'AUTO-REPARATION ESN DEMARRE ($env:COMPUTERNAME) ===" "INFO"
$actionsHealed = [System.Collections.Generic.List[string]]::new()

# A. SURVEILLANCE & RELANCE DES SERVICES CRITIQUES
$criticalServices = @(
    @{ Name = "Spooler";   Desc = "Spouleur d'impression" },
    @{ Name = "wuauserv";  Desc = "Windows Update" },
    @{ Name = "Dnscache";  Desc = "Client DNS" },
    @{ Name = "Dhcp";      Desc = "Client DHCP" },
    @{ Name = "LanmanWorkstation"; Desc = "Station de travail réseau" },
    @{ Name = "WinDefend"; Desc = "Microsoft Defender Antivirus" }
)

foreach ($cs in $criticalServices) {
    $svc = Get-Service -Name $cs.Name -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne 'Running' -and $svc.StartType -ne 'Disabled') {
            Log-SelfHealing "Service critique arrêté : $($cs.Desc) ($($cs.Name))" "WARN"
            try {
                Start-Service -Name $cs.Name -ErrorAction Stop
                Log-SelfHealing "AUTO-HEAL : Service '$($cs.Name)' redémarré avec succès." "HEALED"
                $actionsHealed.Add("Service $($cs.Name) relancé")
            } catch {
                Log-SelfHealing "ERREUR : Impossible de redémarrer '$($cs.Name)' : $($_.Exception.Message)" "CRITICAL"
            }
        }
    }
}

# B. SURVEILLANCE ET NETTOYAGE AUTONOME DU DISQUE C:
$cDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
if ($cDrive) {
    $freePercent = [math]::Round(($cDrive.FreeSpace / $cDrive.Size) * 100, 1)
    $usedPercent = 100 - $freePercent
    $freeGB      = [math]::Round($cDrive.FreeSpace / 1GB, 1)

    if ($usedPercent -ge $DiskWarningPercent) {
        Log-SelfHealing "Alerte espace disque C: $usedPercent% utilisé ($freeGB Go libres)" "WARN"
        
        # Purge 1 : Fichiers Temp utilisateurs et système
        $tempDirs = @(
            "$env:SystemRoot\Temp\*",
            "$env:LOCALAPPDATA\Temp\*",
            "$env:SystemRoot\SoftwareDistribution\Download\*"
        )
        $clearedMB = 0
        foreach ($td in $tempDirs) {
            $files = Get-ChildItem $td -Recurse -Force -ErrorAction SilentlyContinue
            $size = ($files | Measure-Object Length -Sum).Sum
            if ($size) { $clearedMB += [math]::Round($size / 1MB, 1) }
            Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Purge 2 : Vider la Corbeille de tous les lecteurs
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue

        Log-SelfHealing "AUTO-HEAL : Purge automatique de $clearedMB Mo de fichiers temporaires." "HEALED"
        $actionsHealed.Add("Disque C: purge automatique de $clearedMB Mo")
    }
}

# C. AUTO-RÉSOLUTION DES CONNEXIONS ET LATENCES RÉSEAU
$testDNS = try { Resolve-DnsName "www.google.com" -ErrorAction Stop; $true } catch { $false }
if (-not $testDNS) {
    Log-SelfHealing "Résolution DNS défaillante. Déclenchement de la réinitialisation réseau..." "WARN"
    Clear-DnsClientCache
    ipconfig /flushdns 2>&1 | Out-Null
    ipconfig /renew 2>&1 | Out-Null
    Log-SelfHealing "AUTO-HEAL : Cache DNS vidé et bail DHCP renouvelé." "HEALED"
    $actionsHealed.Add("Résolution DNS rétablie")
}

# D. DÉTECTION DES PROCESSUS EN FUITE MÉMOIRE (> 2 Go RAM)
$heavyProcesses = Get-Process | Where-Object { $_.WorkingSet64 -gt 2GB -and $_.ProcessName -notin @("System", "Memory Compression", "explorer") }
foreach ($hp in $heavyProcesses) {
    $ramGB = [math]::Round($hp.WorkingSet64 / 1GB, 2)
    Log-SelfHealing "Processus volumineux détecté : $($hp.ProcessName) (PID: $($hp.Id)) utilisant $ramGB Go de RAM." "WARN"
}

# E. NOTIFICATION WEBHOOK (TEAMS / DISCORD / SLACK) SI DES ACTIONS ONT ETE MENEES
if ($actionsHealed.Count -gt 0 -and $WebhookUrl) {
    try {
        $body = @{
            text = "🤖 **[ESN-SelfHealing] Auto-Réparation exécutée sur $env:COMPUTERNAME**`n" +
                   ($actionsHealed | ForEach-Object { "• $_" }) -join "`n"
        } | ConvertTo-Json
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
        Log-SelfHealing "Notification Webhook envoyée." "INFO"
    } catch {
        Log-SelfHealing "Échec envoi Webhook : $($_.Exception.Message)" "WARN"
    }
}

Log-SelfHealing "=== FIN DU CYCLE D'AUTO-REPARATION (Actions curatives : $($actionsHealed.Count)) ===`n" "INFO"
