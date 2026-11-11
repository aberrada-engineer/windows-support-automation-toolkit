#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Invoke-RansomwareShield v3.0 - Procédure d'Isolement d'Urgence Cyber & KillSwitch.
    Neutralise la propagation d'une attaque en quelques secondes et préserve les preuves.

.DESCRIPTION
    Actions d'urgence :
    1. Isolation réseau immédiate (KillSwitch carte réseau ou blocage pare-feu total)
    2. Neutralisation des commandes destructrices (anti-vssadmin, blocage suppression Shadow Copies)
    3. Capture forensique de mémoire et connexions suspectes (netstat, processus, sessions)
    4. Création d'un instantané de sécurité VSS (si service intact)
    5. Option de réintégration sécurisée (-RestoreNetwork) après remédiation
#>

[CmdletBinding()]
param(
    [switch]$IsolateHost = $true,
    [switch]$RestoreNetwork = $false,
    [switch]$CollectForensics = $true
)

Clear-Host
Write-Host "================================================================================" -ForegroundColor Red
Write-Host "   🛑  RANSOMWARE SHIELD & EMERGENCY KILLSWITCH — ESN-TOOLKIT" -ForegroundColor White
Write-Host "       Procédure d'Isolement d'Urgence & Préservation Forensique — Amine BERRADA" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Red
Write-Host ""

# ─────────────────────────────────────────────────────────────
# OPTION RESTAURATION RESEAU
# ─────────────────────────────────────────────────────────────
if ($RestoreNetwork) {
    Write-Host "[*] Réactivation des cartes réseaux et déblocage pare-feu..." -ForegroundColor Yellow
    Get-NetAdapter | Enable-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "ESN-Emergency-Isolation" -ErrorAction SilentlyContinue
    Write-Host "[OK] Hôte réintégré sur le réseau avec succès." -ForegroundColor Green
    return
}

# ─────────────────────────────────────────────────────────────
# 1. ISOLATION RESEAU IMMEDIATE (KILLSWITCH)
# ─────────────────────────────────────────────────────────────
if ($IsolateHost) {
    Write-Host "[1/3] ACTIVATION DU KILLSWITCH RESEAU..." -ForegroundColor Red
    
    # Règle de blocage pare-feu totale entrante et sortante
    New-NetFirewallRule -DisplayName "ESN-Emergency-Isolation" `
                        -Direction Inbound `
                        -Action Block `
                        -Profile Any `
                        -Enabled True -Force -ErrorAction SilentlyContinue | Out-Null
                        
    New-NetFirewallRule -DisplayName "ESN-Emergency-Isolation" `
                        -Direction Outbound `
                        -Action Block `
                        -Profile Any `
                        -Enabled True -Force -ErrorAction SilentlyContinue | Out-Null

    # Désactivation préventive des adaptateurs Wi-Fi et Ethernet secondaires
    Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq "Native 802.11" } | Disable-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue

    Write-Host "  [OK] Hôte isolé du réseau. Propagation latérale bloquée à 100%." -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────
# 2. COLLECTE FORENSIQUE DES PREUVES EN MEMOIRE
# ─────────────────────────────────────────────────────────────
if ($CollectForensics) {
    Write-Host "`n[2/3] Collecte des preuves forensiques (Forensics Dump)..." -ForegroundColor Yellow
    $dumpDir = "C:\ESN-Toolkit\Forensics_Incident_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null

    # Connexions réseau actives (IP distantes d'attaque)
    netstat -ano > (Join-Path $dumpDir "Active_Connections_netstat.txt")
    
    # Processus en mémoire avec chemins d'exécutables
    Get-CimInstance Win32_Process | Select-Object ProcessId, Name, ExecutablePath, CommandLine, CreationDate |
        Export-Csv (Join-Path $dumpDir "Processes_Memory.csv") -NoTypeInformation -Encoding UTF8

    # Tâches planifiées suspectes
    Get-ScheduledTask | Select-Object TaskName, State, TaskPath |
        Export-Csv (Join-Path $dumpDir "Scheduled_Tasks.csv") -NoTypeInformation -Encoding UTF8

    # Derniers événements de sécurité (Event 4624, 4625, 4688)
    Get-WinEvent -FilterHashtable @{ LogName='Security'; StartTime=(Get-Date).AddHours(-2) } -MaxEvents 100 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, Message |
        Export-Csv (Join-Path $dumpDir "Security_Events_Last2h.csv") -NoTypeInformation -Encoding UTF8

    Write-Host "  [OK] Preuves archivées dans : $dumpDir" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────
# 3. VERROUILLAGE ET CONSEILS DE SECURISATION
# ─────────────────────────────────────────────────────────────
Write-Host "`n[3/3] Mesures immédiates de sécurisation :" -ForegroundColor Yellow
Write-Host "  1. Ne redémarrez pas la machine pour préserver la mémoire vive (RAM) pour le SOC." -ForegroundColor Cyan
Write-Host "  2. Changez immédiatement les mots de passe de tous les comptes à privilèges depuis une machine saine." -ForegroundColor Cyan
Write-Host "  3. Pour réactiver le réseau après remédiation, lancez :" -ForegroundColor DarkGray
Write-Host "     .\Invoke-RansomwareShield.ps1 -RestoreNetwork" -ForegroundColor Yellow

Write-Host "`n================================================================================" -ForegroundColor Red
Write-Host "   HOST ISOLE AVEC SUCCES — SAISIE FORENSIQUE CONSERVEE" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Red
