#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-Infra — Module d'audit d'infrastructure, Active Directory, SecOps & Sauvegardes.
    Conçu pour Administrateurs Systèmes & Réseaux et Ingénieurs Système.
#>

Set-StrictMode -Version Latest

# ─────────────────────────────────────────────
# 1. AUDIT ACTIVE DIRECTORY & INFRASTRUCTURE
# ─────────────────────────────────────────────
function Test-ESNADHealth {
    [CmdletBinding()]
    param()

    Write-Host "`n[+] Audit Active Directory & Infrastructure..." -ForegroundColor Cyan

    $domainRole = (Get-CimInstance Win32_ComputerSystem).DomainRole
    # 0 = Standalone Workstation, 1 = Member Workstation, 2 = Standalone Server, 3 = Member Server, 4 = Backup Domain Controller, 5 = Primary Domain Controller
    $isDomainJoined = $domainRole -in @(1, 3, 4, 5)
    $isDC = $domainRole -in @(4, 5)

    $adReport = [PSCustomObject]@{
        ComputerName   = $env:COMPUTERNAME
        IsDomainJoined = $isDomainJoined
        DomainName     = (Get-CimInstance Win32_ComputerSystem).Domain
        IsDomainCtrl   = $isDC
        ReplicationOK  = $null
        FSMOReachable  = $null
        IssuesFound    = [System.Collections.Generic.List[string]]::new()
    }

    if (-not $isDomainJoined) {
        Write-Host "  [-] Machine hors domaine (Workgroup : $($adReport.DomainName))" -ForegroundColor Yellow
        $adReport.IssuesFound.Add("Machine non jointe au domaine")
        return $adReport
    }

    Write-Host "  [OK] Domaine rejoint : $($adReport.DomainName)" -ForegroundColor Green

    # Test résolution contrôleur de domaine
    try {
        $dcInfo = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        Write-Host "  [OK] Controleurs de domaine detectes : $($dcInfo.DomainControllers.Name -join ', ')" -ForegroundColor Green
        $adReport.FSMOReachable = $true
    } catch {
        Write-Host "  [!] Impossible de contacter le contrôleur de domaine principal : $($_.Exception.Message)" -ForegroundColor Red
        $adReport.IssuesFound.Add("Contrôleur de domaine injoignable")
        $adReport.FSMOReachable = $false
    }

    # Si c'est un contrôleur de domaine, test réplication
    if ($isDC) {
        Write-Host "  [*] Analyse de la réplication Active Directory (repadmin)..." -ForegroundColor Cyan
        $repadmin = Get-Command repadmin.exe -ErrorAction SilentlyContinue
        if ($repadmin) {
            $repOutput = & repadmin.exe /replsummary 2>&1 | Out-String
            if ($repOutput -match "fails") {
                Write-Host "  [!] Des erreurs de réplication ont été détectées dans /replsummary" -ForegroundColor Red
                $adReport.ReplicationOK = $false
                $adReport.IssuesFound.Add("Échec de réplication AD détecté")
            } else {
                Write-Host "  [OK] Réplication Active Directory saine." -ForegroundColor Green
                $adReport.ReplicationOK = $true
            }
        }
    }

    return $adReport
}

# ─────────────────────────────────────────────
# 2. AUDIT SAUVEGARDE & VEEAM
# ─────────────────────────────────────────────
function Test-ESNVeeamStatus {
    [CmdletBinding()]
    param()

    Write-Host "`n[+] Audit Sauvegardes & Veeam Backup..." -ForegroundColor Cyan

    $veeamServices = Get-Service -Name "*Veeam*" -ErrorAction SilentlyContinue

    if (-not $veeamServices) {
        Write-Host "  [i] Aucun service Veeam installé sur cette machine (Machine cliente ou serveur sans agent Veeam)." -ForegroundColor DarkGray
        return [PSCustomObject]@{
            VeeamInstalled = $false
            ServicesCount  = 0
            Status         = "Not Applicable"
        }
    }

    Write-Host "  [OK] Services Veeam détectés : $($veeamServices.Count) service(s)" -ForegroundColor Green
    $stoppedServices = $veeamServices | Where-Object { $_.Status -ne 'Running' }

    if ($stoppedServices) {
        Write-Host "  [!] Service(s) Veeam arrêté(s) : $($stoppedServices.Name -join ', ')" -ForegroundColor Yellow
    } else {
        Write-Host "  [OK] Tous les services Veeam sont en cours d'exécution." -ForegroundColor Green
    }

    # Vérification des erreurs de backup dans le journal d'événements (24h)
    $veeamErrors = Get-WinEvent -FilterHashtable @{
        LogName   = 'Veeam Backup'
        StartTime = (Get-Date).AddHours(-24)
        Level     = 2 # Error
    } -ErrorAction SilentlyContinue

    $statusStr = if ($veeamErrors) { "Warning - $($veeamErrors.Count) erreur(s) recente(s)" } else { "OK - 0 erreur 24h" }
    Write-Host "  [$statusStr]" -ForegroundColor $(if ($veeamErrors) { "Yellow" } else { "Green" })

    return [PSCustomObject]@{
        VeeamInstalled   = $true
        ServicesRunning  = ($stoppedServices.Count -eq 0)
        RecentErrors24h  = ($veeamErrors | Measure-Object).Count
        Status           = $statusStr
    }
}

# ─────────────────────────────────────────────
# 3. AUDIT POSTURE DE SECURITE & EDR
# ─────────────────────────────────────────────
function Test-ESNSecurityPosture {
    [CmdletBinding()]
    param()

    Write-Host "`n[+] Audit Posture de Sécurité & SecOps..." -ForegroundColor Cyan

    # A. BitLocker
    $bitlockerStatus = "Non supporte"
    $blCmd = Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue
    if ($blCmd) {
        $cVol = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
        if ($cVol) {
            $bitlockerStatus = "$($cVol.VolumeStatus) ($($cVol.ProtectionStatus))"
            $color = if ($cVol.ProtectionStatus -eq 'On') { "Green" } else { "Yellow" }
            Write-Host "  [BitLocker C:] $bitlockerStatus" -ForegroundColor $color
        }
    } else {
        Write-Host "  [BitLocker] Module BitLocker non présent sur ce système." -ForegroundColor DarkGray
    }

    # B. Protocole SMBv1 (Risque critique ransomware)
    $smbv1 = "Inconnu"
    try {
        $smbConfig = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
        if ($smbConfig) {
            if ($smbConfig.EnableSMB1Protocol) {
                Write-Host "  [ALERTE] SMBv1 est ACTIVÉ ! (Vulnérabilité critique - désactivation recommandée)" -ForegroundColor Red
                $smbv1 = "Actif (DANGER)"
            } else {
                Write-Host "  [OK] SMBv1 est désactivé." -ForegroundColor Green
                $smbv1 = "Désactivé (Conforme)"
            }
        }
    } catch {
        $smbv1 = "Non auditable"
    }

    # C. Détection Agents EDR / Antivirus
    $edrDetected = [System.Collections.Generic.List[string]]::new()
    $edrList = @(
        @{ Name = "SentinelOne"; Process = "SentinelAgent" },
        @{ Name = "Microsoft Defender"; Process = "MsMpEng" },
        @{ Name = "Sophos Endpoint"; Process = "SophosEDR" },
        @{ Name = "Trend Micro"; Process = "NTRTscan" }
    )

    foreach ($edr in $edrList) {
        if (Get-Process -Name $edr.Process -ErrorAction SilentlyContinue) {
            $edrDetected.Add($edr.Name)
            Write-Host "  [OK] Agent EDR actif : $($edr.Name)" -ForegroundColor Green
        }
    }

    if ($edrDetected.Count -eq 0) {
        Write-Host "  [!] Aucun agent EDR standard détecté en mémoire." -ForegroundColor Yellow
    }

    return [PSCustomObject]@{
        BitLockerStatus = $bitlockerStatus
        SMBv1Status     = $smbv1
        EDRActive       = ($edrDetected -join ', ')
    }
}

Export-ModuleMember -Function Test-ESNADHealth, Test-ESNVeeamStatus, Test-ESNSecurityPosture
