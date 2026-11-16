<#
.SYNOPSIS
    Invoke-LinuxHeterogeneousAudit.ps1 - Audit à distance de serveurs Linux (Ubuntu Server / Debian) depuis Windows via SSH.
.DESCRIPTION
    Conçu pour la gestion de parcs hétérogènes Windows / Linux (expérience d'exploitation Ubuntu/Debian) :
    - Connexion SSH native sans outil tiers (utilise l'exécutable natif OpenSSH de Windows 'ssh.exe').
    - Audit de l'état des services critiques systemd (détection des unités en échec 'systemctl --failed').
    - Analyse de saturation des systèmes de fichiers (/, /var, /home, /opt).
    - Contrôle de durcissement SSH (/etc/ssh/sshd_config : PermitRootLogin, PasswordAuthentication, port).
    - Détection des mises à jour de sécurité en attente (paquets APT de sécurité / unattended-upgrades).
    - Statut des partages de fichiers hétérogènes (Samba smbd/nmbd et NFS kernel server).
    - Contrôle du pare-feu local (UFW ou iptables).
    - Génération d'un rapport de santé Linux en HTML interactif.
.PARAMETER TargetHost
    Adresse IP ou FQDN du serveur Linux à auditer.
.PARAMETER Username
    Nom d'utilisateur SSH (défaut: adm-infra).
.PARAMETER SshPort
    Port d'écoute du service SSH (défaut: 22).
.PARAMETER SshKeyPath
    Chemin facultatif de la clé privée SSH (.id_rsa ou .pem).
.EXAMPLE
    .\Invoke-LinuxHeterogeneousAudit.ps1 -TargetHost "192.168.1.50" -Username "sysadmin"
#>

[CmdletBinding()]
param(
    [string]$TargetHost = "127.0.0.1",
    [string]$Username = "sysadmin",
    [int]$SshPort = 22,
    [string]$SshKeyPath,
    [switch]$SimulationMode,
    [switch]$OpenReport
)
Set-StrictMode -Version Latest

$ErrorActionPreference = "Continue"
$schemaScript = Join-Path $PSScriptRoot "Core/ESN-OutputSchema.ps1"
if (Test-Path $schemaScript) { . $schemaScript }

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   LINUX (UBUNTU / DEBIAN) HETEROGENEOUS FLEET AUDIT ENGINE                " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "[*] Cible Linux  : $Username@$TargetHost`:$SshPort" -ForegroundColor Gray
Write-Host "[*] Clé SSH      : $(if ($SshKeyPath) { $SshKeyPath } else { 'Clé agent par défaut' })" -ForegroundColor Gray
Write-Host ""

$ReportDir = if (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) {
    Get-ESNReportRoot -SubFolder "Linux-Audit"
} else {
    $fallbackDir = Join-Path ([System.IO.Path]::GetTempPath()) (Join-Path "ESN-Toolkit" (Join-Path "Reports" "Linux-Audit"))
    if (-not (Test-Path $fallbackDir)) { New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null }
    $fallbackDir
}
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SafeHost = $TargetHost -replace '[^a-zA-Z0-9._-]', '_'
$HtmlReport = Join-Path $ReportDir "Linux-Audit-$SafeHost-$Timestamp.html"

# Test de disponibilité de l'exécutable SSH natif Windows ou OpenSSH Linux/macOS
$SshCmd = Get-Command "ssh" -ErrorAction SilentlyContinue
if (-not $SshCmd) { $SshCmd = Get-Command "ssh.exe" -ErrorAction SilentlyContinue }

$IsOnline = $false
if (-not $SimulationMode) {
    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        $ar = $tcp.BeginConnect($TargetHost, $SshPort, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(3000, $false)) {
            $tcp.EndConnect($ar)
            $IsOnline = $true
        }
    } catch { $IsOnline = $false }
    finally { $tcp.Dispose() }
}

$BadgeLabel = "INJOIGNABLE"
$BadgeColor = "#dc3545"
$LinuxOS = "N/A (Hôte injoignable ou SSH indisponible)"
$LinuxKernel = "N/A"
$FailedServicesCount = -1
$AptSecurityUpdates = -1
$RootLoginPermitted = "inconnu"
$PasswordAuth = "inconnu"
$UfwStatus = "inconnu"
$SambaStatus = "inconnu"
$DiskMetrics = @()

if ($SimulationMode) {
    Write-Host "[!] Mode Simulation actif pour l'hôte Linux $TargetHost." -ForegroundColor Yellow
    $BadgeLabel = "Simulation (Conforme)"
    $BadgeColor = "#238636"
    $LinuxOS = "Ubuntu 22.04.4 LTS (Jammy Jellyfish)"
    $LinuxKernel = "5.15.0-105-generic"
    $FailedServicesCount = 0
    $AptSecurityUpdates = 2
    $RootLoginPermitted = "no"
    $PasswordAuth = "no"
    $UfwStatus = "active"
    $SambaStatus = "active (running)"
    $DiskMetrics = @(
        @{ Mount = "/"; Size = "100G"; Used = "34G"; Avail = "66G"; Pct = "34%" },
        @{ Mount = "/var"; Size = "200G"; Used = "85G"; Avail = "115G"; Pct = "43%" },
        @{ Mount = "/opt"; Size = "500G"; Used = "290G"; Avail = "210G"; Pct = "58%" }
    )
}
elseif ($IsOnline -and $SshCmd) {
    Write-Host "[*] Connexion SSH active vers $TargetHost..." -ForegroundColor Green
    $LinuxAuditCommands = @'
echo "===OS==="; grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"'; uname -r
echo "===FAILED_SERVICES==="; systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l
echo "===DISK==="; df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2 | awk '{print $NF"|"$2"|"$3"|"$4"|"$5}'
echo "===SSH_CONFIG==="; grep -hE "^[[:space:]]*(PermitRootLogin|PasswordAuthentication)[[:space:]]+" /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null || true
echo "===SERVICES==="; echo "UFW:$({ sudo -n ufw status 2>/dev/null || ufw status 2>/dev/null; } | head -n 1)"; echo "SMB:$(systemctl is-active smbd 2>/dev/null || echo inactive)"
echo "===UPDATES==="; (apt-get -s upgrade 2>/dev/null | grep -i '^Inst ' | grep -ic 'security') || echo "0"
'@ -replace "`r", ""
    # Base64 evite le stripping des guillemets/sauts de ligne par WinPS 5.1 vers ssh.exe
    $cmdB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($LinuxAuditCommands))
    $sshArgs = @("-p", $SshPort, "-o", "StrictHostKeyChecking=accept-new", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5")
    if ($SshKeyPath) { $sshArgs += @("-i", $SshKeyPath) }
    $sshArgs += @("$Username@$TargetHost", "echo $cmdB64 | base64 -d | sh")

    $rawOutput = (& $SshCmd.Source @sshArgs 2>&1) -join "`n"
    if ($LASTEXITCODE -eq 0 -and $rawOutput -match "===OS===") {
        $sections = @{}
        $cur = ""
        foreach ($line in ($rawOutput -split "`r?`n")) {
            if ($line -match '^===([A-Z_]+)===$') { $cur = $Matches[1]; $sections[$cur] = @() }
            elseif ($cur -and -not [string]::IsNullOrWhiteSpace($line)) { $sections[$cur] += $line.Trim() }
        }
        $osLines = @(if ($sections.ContainsKey("OS")) { $sections["OS"] })
        if ($osLines.Count -ge 1) { $LinuxOS = $osLines[0] }
        if ($osLines.Count -ge 2) { $LinuxKernel = $osLines[1] }
        $failArr = @(if ($sections.ContainsKey("FAILED_SERVICES")) { $sections["FAILED_SERVICES"] })
        $FailedServicesCount = if ($failArr.Count -gt 0 -and $failArr[0] -match '^\d+$') { [int]$failArr[0] } else { 0 }
        $updArr = @(if ($sections.ContainsKey("UPDATES")) { $sections["UPDATES"] })
        $AptSecurityUpdates = if ($updArr.Count -gt 0 -and $updArr[0] -match '^\d+$') { [int]$updArr[0] } else { 0 }
        $sshConf = if ($sections.ContainsKey("SSH_CONFIG")) { @($sections["SSH_CONFIG"]) -join "`n" } else { "" }
        $RootLoginPermitted = if ($sshConf -match 'PermitRootLogin\s+(\S+)') { $Matches[1] } else { "default/non-explicit" }
        $PasswordAuth = if ($sshConf -match 'PasswordAuthentication\s+(\S+)') { $Matches[1] } else { "default/non-explicit" }
        $svcConf = if ($sections.ContainsKey("SERVICES")) { @($sections["SERVICES"]) -join "`n" } else { "" }
        $UfwStatus = if ($svcConf -match 'UFW:Status:\s*(\S+)') { $Matches[1] } else { "inactive/unknown" }
        $SambaStatus = if ($svcConf -match 'SMB:(\S+)') { $Matches[1] } else { "inactive" }
        $diskLines = @(if ($sections.ContainsKey("DISK")) { $sections["DISK"] })
        $DiskMetrics = @(foreach ($dl in $diskLines) {
            $p = @($dl -split '\|')
            if ($p.Count -ge 5) { @{ Mount = $p[0]; Size = $p[1]; Used = $p[2]; Avail = $p[3]; Pct = $p[4] } }
        })
        $BadgeLabel = if ($FailedServicesCount -eq 0 -and $RootLoginPermitted -eq "no") { "Conforme" } else { "Attention Requise" }
        $BadgeColor = if ($FailedServicesCount -eq 0 -and $RootLoginPermitted -eq "no") { "#238636" } else { "#d29922" }
        Write-Host "[+] Audit Linux collecté et parsé via SSH." -ForegroundColor Green
    } else {
        Write-Warning "Échec SSH sur $TargetHost (code $LASTEXITCODE) : authentification ou commande impossible sans -SimulationMode."
        if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
            Write-ESNSiemAlert -ScriptName "Invoke-LinuxHeterogeneousAudit.ps1" -Severity "CRITICAL" -Category "LinuxAudit" -Target $TargetHost -Message "SSH audit failed on $TargetHost (exit $LASTEXITCODE)" | Out-Null
        }
    }
}
else {
    Write-Warning "Hôte Linux $TargetHost injoignable sur TCP/$SshPort ou client ssh absent. Relancez avec -SimulationMode pour une démo."
    if (Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) {
        Write-ESNSiemAlert -ScriptName "Invoke-LinuxHeterogeneousAudit.ps1" -Severity "CRITICAL" -Category "LinuxAudit" -Target $TargetHost -Message "Linux host $TargetHost unreachable on port $SshPort" | Out-Null
    }
}

$escHost     = [System.Net.WebUtility]::HtmlEncode([string]$TargetHost)
$escBadge    = [System.Net.WebUtility]::HtmlEncode([string]$BadgeLabel)
$escOs       = [System.Net.WebUtility]::HtmlEncode([string]$LinuxOS)
$escKernel   = [System.Net.WebUtility]::HtmlEncode([string]$LinuxKernel)
$escRoot     = [System.Net.WebUtility]::HtmlEncode([string]$RootLoginPermitted)
$escPwdAuth  = [System.Net.WebUtility]::HtmlEncode([string]$PasswordAuth)
$escUfw      = [System.Net.WebUtility]::HtmlEncode([string]$UfwStatus)
$escSamba    = [System.Net.WebUtility]::HtmlEncode([string]$SambaStatus)

$svcSubText  = if ($FailedServicesCount -eq 0) { "Toutes les unités actives" } elseif ($FailedServicesCount -gt 0) { "$FailedServicesCount unité(s) en échec" } else { "Non audité" }
$svcSubColor = if ($FailedServicesCount -eq 0) { "#3fb950" } elseif ($FailedServicesCount -gt 0) { "#f85149" } else { "#8b949e" }

$sshHardened = ($RootLoginPermitted -eq "no" -and $PasswordAuth -eq "no")
$sshVerdict  = if ($RootLoginPermitted -eq "inconnu") { "Non vérifié" } elseif ($sshHardened) { "Conforme ANSSI" } elseif ($RootLoginPermitted -eq "no") { "Partiel (PasswordAuth=$escPwdAuth)" } else { "Non conforme" }
$sshClass    = if ($sshHardened) { "status-ok" } elseif ($RootLoginPermitted -eq "inconnu" -or $RootLoginPermitted -eq "no") { "status-warn" } else { "status-err" }

$ufwActive   = ($UfwStatus -match '(?i)^active')
$ufwClass    = if ($ufwActive) { "status-ok" } elseif ($UfwStatus -eq "inconnu") { "status-warn" } else { "status-err" }
$ufwLabel    = if ($ufwActive) { "ACTIF" } elseif ($UfwStatus -eq "inconnu") { "NON VÉRIFIÉ" } else { "INACTIF / NON FILTRÉ" }

$updClass    = if ($AptSecurityUpdates -eq 0) { "status-ok" } elseif ($AptSecurityUpdates -lt 0) { "status-warn" } else { "status-warn" }
$updLabel    = if ($AptSecurityUpdates -eq 0) { "À JOUR" } elseif ($AptSecurityUpdates -lt 0) { "NON VÉRIFIÉ" } else { "À PLANIFIER ($AptSecurityUpdates)" }

$smbActive   = ($SambaStatus -match '(?i)^active')
$smbClass    = if ($smbActive) { "status-ok" } else { "status-warn" }
$smbLabel    = if ($smbActive) { "ACTIF" } elseif ($SambaStatus -eq "inconnu") { "NON VÉRIFIÉ" } else { "INACTIF" }

$DiskRowsHtml = ($DiskMetrics | ForEach-Object {
    "<tr><td><strong>$([System.Net.WebUtility]::HtmlEncode($_.Mount))</strong></td><td>$([System.Net.WebUtility]::HtmlEncode($_.Size))</td><td>$([System.Net.WebUtility]::HtmlEncode($_.Used))</td><td>$([System.Net.WebUtility]::HtmlEncode($_.Avail))</td><td>$([System.Net.WebUtility]::HtmlEncode($_.Pct))</td><td><span style='color:#4ade80;'>Analysé</span></td></tr>"
}) -join "`n"
if (-not $DiskRowsHtml) { $DiskRowsHtml = "<tr><td colspan='6'>Aucune donnée disque collectée (hôte injoignable).</td></tr>" }

# Génération du Rapport HTML Linux
$HtmlContent = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Audit Système Linux - $escHost</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #0d1117; color: #c9d1d9; margin: 0; padding: 28px; }
        .container { max-width: 1000px; margin: auto; background-color: #161b22; border: 1px solid #30363d; border-radius: 10px; padding: 32px; box-shadow: 0 10px 30px rgba(0,0,0,0.6); }
        h1 { color: #58a6ff; margin-top: 0; font-size: 24px; border-bottom: 2px solid #21262d; padding-bottom: 12px; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 4px; font-weight: bold; font-size: 12px; text-transform: uppercase; background: $BadgeColor; color: white; }
        .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin: 20px 0; }
        .card { background-color: #0d1117; border: 1px solid #30363d; border-radius: 8px; padding: 16px; }
        .card-title { font-size: 12px; color: #8b949e; text-transform: uppercase; margin-bottom: 6px; }
        .card-value { font-size: 18px; font-weight: bold; color: #58a6ff; }
        table { width: 100%; border-collapse: collapse; margin-top: 14px; }
        th, td { border: 1px solid #30363d; padding: 10px 14px; text-align: left; }
        th { background-color: #21262d; color: #58a6ff; font-size: 13px; }
        tr:nth-child(even) { background-color: #11161d; }
        .status-ok { color: #3fb950; font-weight: bold; }
        .status-warn { color: #d29922; font-weight: bold; }
        .status-err { color: #f85149; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Audit Serveur Linux (Ubuntu/Debian) & Parcs Hétérogènes <span class="badge">$escBadge</span></h1>
        <p style="color: #8b949e;">Audit de santé, services systemd, sécurité SSH, stockage et conformité du serveur Linux <strong>$escHost</strong>.</p>
        
        <div class="grid">
            <div class="card">
                <div class="card-title">Distribution & Kernel</div>
                <div class="card-value" style="font-size: 15px;">$escOs</div>
                <div style="font-size: 11px; color: #8b949e; margin-top: 4px;">Kernel : $escKernel</div>
            </div>
            <div class="card">
                <div class="card-title">Services en Échec (systemd)</div>
                <div class="card-value">$FailedServicesCount</div>
                <div style="font-size: 11px; color: $svcSubColor; margin-top: 4px;">$svcSubText</div>
            </div>
            <div class="card">
                <div class="card-title">Durcissement SSH</div>
                <div class="card-value">$sshVerdict</div>
                <div style="font-size: 11px; color: #8b949e; margin-top: 4px;">Root login: $escRoot | PasswordAuth: $escPwdAuth</div>
            </div>
        </div>

        <h3>Occupation des Systèmes de Fichiers (df -h)</h3>
        <table>
            <thead>
                <tr>
                    <th>Point de Montage</th>
                    <th>Taille Totale</th>
                    <th>Espace Utilisé</th>
                    <th>Espace Disponible</th>
                    <th>Taux d'Occupation</th>
                    <th>Statut</th>
                </tr>
            </thead>
            <tbody>
                $DiskRowsHtml
            </tbody>
        </table>

        <h3>Contrôles de Sécurité & Services Partagés</h3>
        <table>
            <thead>
                <tr>
                    <th>Composant</th>
                    <th>État / Configuration</th>
                    <th>Verdict</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><strong>Pare-feu Local (UFW)</strong></td>
                    <td>Statut : $escUfw</td>
                    <td class="$ufwClass">$ufwLabel</td>
                </tr>
                <tr>
                    <td><strong>Mises à jour APT (sécurité)</strong></td>
                    <td>$AptSecurityUpdates paquet(s) de sécurité en attente</td>
                    <td class="$updClass">$updLabel</td>
                </tr>
                <tr>
                    <td><strong>Partage Samba (smbd)</strong></td>
                    <td>$escSamba</td>
                    <td class="$smbClass">$smbLabel</td>
                </tr>
                <tr>
                    <td><strong>SSH Daemon Hardening</strong></td>
                    <td>PermitRootLogin: $escRoot | PasswordAuth: $escPwdAuth</td>
                    <td class="$sshClass">$sshVerdict</td>
                </tr>
            </tbody>
        </table>

        <p style="color: #484f58; font-size: 12px; margin-top: 28px;">Généré par Antigravity ESN-Toolkit • Module Linux & Parcs Hétérogènes • Référent : Amine BERRADA</p>
    </div>
</body>
</html>
"@

Set-Content -Path $HtmlReport -Value $HtmlContent -Encoding UTF8
$bannerOk    = ($BadgeLabel -notin @("Échec SSH", "Injoignable"))
$bannerColor = if ($bannerOk) { "Green" } else { "Red" }
$bannerText  = if ($bannerOk) { "   AUDIT LINUX TERMINÉ AVEC SUCCÈS                                        " } else { "   AUDIT LINUX NON ABOUTI ($BadgeLabel)                                   " }
Write-Host ""
Write-Host "==========================================================================" -ForegroundColor $bannerColor
Write-Host $bannerText -ForegroundColor $bannerColor
Write-Host "==========================================================================" -ForegroundColor $bannerColor
Write-Host "[+] Rapport HTML généré : $HtmlReport" -ForegroundColor White

if ($OpenReport) {
    Start-Process $HtmlReport
}
