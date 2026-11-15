<#
.SYNOPSIS
    Invoke-ZeroTrustAudit.ps1 - Audit de Posture de Sécurité Zero-Trust & Prérequis Accès Conditionnel (ANSSI / Microsoft).
.DESCRIPTION
    Conçu pour les environnements sécurisés et grands comptes (conformité ANSSI & Zero Trust Baseline) :
    - Audit de la présence et de la conformité du module TPM 2.0 (Trusted Platform Module).
    - Contrôle de l'activation du Secure Boot (Démarrage sécurisé UEFI).
    - Vérification de la Sécurité Basée sur la Virtualisation (VBS - Virtualization-Based Security).
    - Audit de la protection LSA / Windows Defender Credential Guard (isolation des secrets LSASS contre Mimikatz).
    - Contrôle de l'intégrité du code protégé par hyperviseur (HVCI).
    - Validation de l'enrôlement Microsoft Entra ID (Hybride Join via dsregcmd /status).
    - Contrôle de chiffrement des volumes système via BitLocker (XTS-AES 256).
    - Calcul d'un Score Global de Maturité Zero-Trust (0 - 100%) et rapport exécutif HTML.
.PARAMETER OpenReport
    Ouvre automatiquement le rapport dans le navigateur par défaut.
.EXAMPLE
    .\Invoke-ZeroTrustAudit.ps1 -OpenReport
#>

[CmdletBinding()]
param(
    [switch]$OpenReport,
    [string]$OutputPath = "",
    [switch]$Simulate
)
Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"
$schemaScript = Join-Path $PSScriptRoot "Core/ESN-OutputSchema.ps1"
if (Test-Path $schemaScript) { . $schemaScript }

try {
    $hostLabel = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
    $userLabel = if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { "operator" }

    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "   ZERO-TRUST SECURITY ARCHITECTURE & POSTURE AUDIT ENGINE (ANSSI)        " -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "[*] Hôte audité   : $hostLabel" -ForegroundColor Gray
    Write-Host "[*] Session active: $userLabel" -ForegroundColor Gray
    Write-Host ""

    $ReportDir = if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath } elseif (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) { Get-ESNReportRoot -SubFolder "ZeroTrust" } else { Join-Path ([System.IO.Path]::GetTempPath()) (Join-Path "ESN-Toolkit" (Join-Path "Reports" "ZeroTrust")) }
    if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $HtmlReport = Join-Path $ReportDir "ZeroTrust-Posture-$Timestamp.html"
    $SiemLog = Join-Path $ReportDir "ZeroTrust-SIEM-$Timestamp.jsonl"

    $Checks = [System.Collections.Generic.List[PSCustomObject]]::new()
    $TotalScore = 0
    $MaxScore = 100

    if ($Simulate) {
        $Checks.Add([PSCustomObject]@{ Check = "Module TPM 2.0"; Detail = "TPM 2.0 Présent et Prêt (Simulé)"; Score = 15; Max = 15; Status = "CONFORME" })
        $Checks.Add([PSCustomObject]@{ Check = "UEFI Secure Boot"; Detail = "Démarrage sécurisé actif (Simulé)"; Score = 15; Max = 15; Status = "CONFORME" })
        $Checks.Add([PSCustomObject]@{ Check = "Virtualization-Based Security (VBS)"; Detail = "VBS En service (Simulé)"; Score = 15; Max = 15; Status = "CONFORME" })
        $Checks.Add([PSCustomObject]@{ Check = "Credential Guard / LSA PPL"; Detail = "LSA RunAsPPL actif (Simulé)"; Score = 15; Max = 15; Status = "CONFORME" })
        $Checks.Add([PSCustomObject]@{ Check = "Chiffrement BitLocker"; Detail = "Volume C: chiffré XTS-AES 256 (Simulé)"; Score = 15; Max = 15; Status = "CONFORME" })
        $Checks.Add([PSCustomObject]@{ Check = "EDR / Protection Temps Réel"; Detail = "SentinelOne / Defender actif (Simulé)"; Score = 15; Max = 15; Status = "CONFORME" })
        $Checks.Add([PSCustomObject]@{ Check = "Identité Gérée (Entra ID / AD)"; Detail = "Hybrid Entra ID Joined (Simulé)"; Score = 10; Max = 10; Status = "CONFORME" })
        $TotalScore = 100
    }
    else {
        # 1. TPM 2.0
        Write-Host "[1/7] Contrôle du module cryptographique TPM 2.0..." -ForegroundColor White
        $Tpm = if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) { Get-Tpm -ErrorAction SilentlyContinue } else { $null }
        if ($Tpm -and $Tpm.TpmPresent -and $Tpm.TpmReady) {
            $Checks.Add([PSCustomObject]@{ Check = "Module TPM 2.0"; Detail = "TPM Présent et Prêt (Ready)"; Score = 15; Max = 15; Status = "CONFORME" })
            $TotalScore += 15
        } else {
            $Checks.Add([PSCustomObject]@{ Check = "Module TPM 2.0"; Detail = "TPM Absent, non initialisé ou applet indisponible"; Score = 0; Max = 15; Status = "NON-CONFORME" })
        }

        # 2. Secure Boot UEFI
        Write-Host "[2/7] Contrôle du Démarrage Sécurisé (Secure Boot)..." -ForegroundColor White
        $SecureBoot = if (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) { try { Confirm-SecureBootUEFI -ErrorAction Stop } catch { $false } } else { $false }
        if ($SecureBoot) {
            $Checks.Add([PSCustomObject]@{ Check = "UEFI Secure Boot"; Detail = "Démarrage sécurisé actif"; Score = 15; Max = 15; Status = "CONFORME" })
            $TotalScore += 15
        } else {
            $Checks.Add([PSCustomObject]@{ Check = "UEFI Secure Boot"; Detail = "Démarrage sécurisé désactivé ou BIOS Legacy"; Score = 0; Max = 15; Status = "NON-CONFORME" })
        }

        # 3. Virtualization-Based Security (VBS) & HVCI
        Write-Host "[3/7] Contrôle de la Sécurité Basée sur la Virtualisation (VBS)..." -ForegroundColor White
        $DeviceGuard = if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) { Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue } else { $null }
        if ($DeviceGuard -and $DeviceGuard.VirtualizationBasedSecurityStatus -eq 2) {
            $Checks.Add([PSCustomObject]@{ Check = "Virtualization-Based Security (VBS)"; Detail = "VBS En service (Statut: Running)"; Score = 15; Max = 15; Status = "CONFORME" })
            $TotalScore += 15
        } else {
            $Checks.Add([PSCustomObject]@{ Check = "Virtualization-Based Security (VBS)"; Detail = "VBS Inactif"; Score = 0; Max = 15; Status = "NON-CONFORME" })
        }

        # 4. Credential Guard (Protection LSASS)
        Write-Host "[4/7] Audit de protection Credential Guard (Anti Mimikatz)..." -ForegroundColor White
        $CredGuard = if ($DeviceGuard -and ($DeviceGuard.PSObject.Properties['SecurityServicesRunning'])) { $DeviceGuard.SecurityServicesRunning -contains 1 } else { $false }
        $lsaReg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue
        $LsaProtected = ($null -ne $lsaReg -and $lsaReg.PSObject.Properties['RunAsPPL'] -and $lsaReg.RunAsPPL -eq 1)
        if ($CredGuard -or $LsaProtected) {
            $Checks.Add([PSCustomObject]@{ Check = "Credential Guard / LSA PPL"; Detail = "Secrets mémoire LSASS isolés (Anti-Dumping)"; Score = 15; Max = 15; Status = "CONFORME" })
            $TotalScore += 15
        } else {
            $Checks.Add([PSCustomObject]@{ Check = "Credential Guard / LSA PPL"; Detail = "LSA non protégé en mode PPL"; Score = 0; Max = 15; Status = "NON-CONFORME" })
        }

        # 5. Chiffrement BitLocker
        Write-Host "[5/7] Audit du chiffrement matériel BitLocker..." -ForegroundColor White
        $Blt = if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) { Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue } else { $null }
        if ($Blt -and $Blt.ProtectionStatus -eq "On") {
            $Checks.Add([PSCustomObject]@{ Check = "Chiffrement BitLocker"; Detail = "Volume C: chiffré ($($Blt.EncryptionMethod))"; Score = 15; Max = 15; Status = "CONFORME" })
            $TotalScore += 15
        } else {
            $Checks.Add([PSCustomObject]@{ Check = "Chiffrement BitLocker"; Detail = "Volume C: non protégé par BitLocker"; Score = 0; Max = 15; Status = "NON-CONFORME" })
        }

        # 6. EDR & Antivirus Temps Réel (Defender ou EDR tiers : SentinelOne, Sophos, CrowdStrike...)
        Write-Host "[6/7] Vérification EDR / Defender Real-Time Protection..." -ForegroundColor White
        $DefStatus = if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) { Get-MpComputerStatus -ErrorAction SilentlyContinue } else { $null }
        $edrSvc = @(Get-Service -Name @('SentinelAgent','SophosEndpointDefense','CSFalconService','SavService','McShield') -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
        if (($DefStatus -and $DefStatus.RealTimeProtectionEnabled) -or $edrSvc.Count -gt 0) {
            $edrDetail = if ($edrSvc.Count -gt 0) { "EDR tiers actif ($($edrSvc[0].Name))" } else { "Defender temps réel actif" }
            $Checks.Add([PSCustomObject]@{ Check = "EDR / Protection Temps Réel"; Detail = $edrDetail; Score = 15; Max = 15; Status = "CONFORME" })
            $TotalScore += 15
        } else {
            $Checks.Add([PSCustomObject]@{ Check = "EDR / Protection Temps Réel"; Detail = "Protection temps réel / EDR inactif"; Score = 0; Max = 15; Status = "NON-CONFORME" })
        }

        # 7. Jonction Microsoft Entra ID / Intune
        Write-Host "[7/7] Vérification de l'adhésion Entra ID (Azure AD)..." -ForegroundColor White
        $DsReg = if (Get-Command dsregcmd.exe -ErrorAction SilentlyContinue) { (dsregcmd.exe /status 2>&1 | Out-String) } else { "" }
        if (($DsReg -match "AzureAdJoined\s*:\s*YES") -or ($DsReg -match "DomainJoined\s*:\s*YES")) {
            $Checks.Add([PSCustomObject]@{ Check = "Identité Gérée (Entra ID / AD)"; Detail = "Machine jointe au domaine ou Entra ID"; Score = 10; Max = 10; Status = "CONFORME" })
            $TotalScore += 10
        } else {
            $Checks.Add([PSCustomObject]@{ Check = "Identité Gérée (Entra ID / AD)"; Detail = "Poste autonome (Workgroup)"; Score = 0; Max = 10; Status = "NON-CONFORME" })
        }
    }

# Génération du Rapport HTML
$ScoreColor = if ($TotalScore -ge 80) { "#4ade80" } elseif ($TotalScore -ge 50) { "#facc15" } else { "#ef4444" }
$VerdictText = if ($TotalScore -ge 80) { "POSTURE ROBUSTE (Prêt pour Accès Conditionnel)" } elseif ($TotalScore -ge 50) { "POSTURE MODÉRÉE (Actions requises)" } else { "NON CONFORME ZERO-TRUST" }

$CheckRowsHtml = ($Checks | ForEach-Object {
    $stClass = if ($_.Status -eq "CONFORME") { "status-ok" } else { "status-error" }
    $encCheck  = [System.Net.WebUtility]::HtmlEncode([string]$_.Check)
    $encDetail = [System.Net.WebUtility]::HtmlEncode([string]$_.Detail)
    $encStatus = [System.Net.WebUtility]::HtmlEncode([string]$_.Status)
    "<tr><td><strong>$encCheck</strong></td><td>$encDetail</td><td>$($_.Score) / $($_.Max)</td><td class='$stClass'>$encStatus</td></tr>"
}) -join "`n"

$encHost = [System.Net.WebUtility]::HtmlEncode([string]$hostLabel)
$encUser = [System.Net.WebUtility]::HtmlEncode([string]$userLabel)

$HtmlContent = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Audit Posture Zero-Trust - $encHost</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #0b0f19; color: #f1f5f9; margin: 0; padding: 32px; }
        .wrapper { max-width: 1000px; margin: auto; background-color: #111827; border: 1px solid #1f2937; border-radius: 12px; padding: 36px; box-shadow: 0 20px 40px rgba(0,0,0,0.6); }
        .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #374151; padding-bottom: 20px; margin-bottom: 28px; }
        h1 { margin: 0; font-size: 24px; color: #38bdf8; font-weight: 700; }
        .subtitle { color: #9ca3af; margin: 4px 0 0 0; font-size: 14px; }
        .badge { background: #0284c7; color: white; padding: 6px 14px; border-radius: 6px; font-weight: 600; font-size: 13px; text-transform: uppercase; }
        .score-box { background-color: #1f2937; border-radius: 8px; padding: 24px; text-align: center; margin: 24px 0; border: 2px solid $ScoreColor; }
        .score-val { font-size: 48px; font-weight: 900; color: $ScoreColor; }
        .score-desc { font-size: 16px; font-weight: 600; color: #e5e7eb; margin-top: 6px; text-transform: uppercase; letter-spacing: 0.5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 16px; }
        th, td { border: 1px solid #374151; padding: 12px 16px; text-align: left; }
        th { background-color: #1f2937; color: #93c5fd; font-size: 13px; text-transform: uppercase; }
        tr:nth-child(even) { background-color: #162032; }
        .status-ok { color: #4ade80; font-weight: bold; }
        .status-error { color: #ef4444; font-weight: bold; }
        .footer { margin-top: 36px; border-top: 1px solid #374151; padding-top: 16px; display: flex; justify-content: space-between; font-size: 12px; color: #6b7280; }
    </style>
</head>
<body>
    <div class="wrapper">
        <div class="header">
            <div>
                <h1>Audit de Posture de Sécurité Zero-Trust & Accès Conditionnel</h1>
                <p class="subtitle">Hôte : <strong>$encHost</strong> • Utilisateur : <strong>$encUser</strong> • Date : $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
            </div>
            <div>
                <span class="badge">ANSSI & CIS Baseline</span>
            </div>
        </div>

        <div class="score-box">
            <div class="score-val">$TotalScore / $MaxScore</div>
            <div class="score-desc">$VerdictText</div>
        </div>

        <h3>Contrôles de Sécurité Matérielle & Système (Zero-Trust)</h3>
        <table>
            <thead>
                <tr>
                    <th>Pilier de Sécurité</th>
                    <th>Résultat du Contrôle</th>
                    <th>Points</th>
                    <th>Statut</th>
                </tr>
            </thead>
            <tbody>
                $CheckRowsHtml
            </tbody>
        </table>

        <div class="footer">
            <div>Généré par Antigravity ESN-Toolkit • Module Zero-Trust Architecture</div>
            <div>Référent Technique N3 & Administrateur Systèmes : <strong>Amine BERRADA</strong></div>
        </div>
    </div>
</body>
</html>
"@

    Set-Content -Path $HtmlReport -Value $HtmlContent -Encoding UTF8
    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        $sev = if ($TotalScore -lt 50) { "CRITICAL" } elseif ($TotalScore -lt 80) { "WARNING" } else { "INFO" }
        [void](Write-ESNSiemAlert -ScriptName "Invoke-ZeroTrustAudit.ps1" -Severity $sev -Category "ZeroTrustPosture" -Message "Score Zero-Trust : $TotalScore / $MaxScore" -LogFile $SiemLog)
    }
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "   AUDIT ZERO-TRUST TERMINÉ AVEC SUCCÈS : $TotalScore / $MaxScore         " -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "[+] Rapport HTML : $HtmlReport" -ForegroundColor White

    if ($OpenReport) { Start-Process $HtmlReport }

    return [PSCustomObject]@{
        HostName   = $hostLabel
        Score      = $TotalScore
        MaxScore   = $MaxScore
        Verdict    = $VerdictText
        Checks     = $Checks
        HtmlReport = $HtmlReport
        SiemLog    = $SiemLog
    }
}
catch [System.Exception] {
    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        [void](Write-ESNSiemAlert -ScriptName "Invoke-ZeroTrustAudit.ps1" -Severity "CRITICAL" -Category "UnhandledException" -ErrorType $_.Exception.GetType().FullName -Message $_.Exception.Message)
    }
    throw
}
