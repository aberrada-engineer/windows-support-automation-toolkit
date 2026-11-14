#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-HealthScore — Système de scoring santé machine pondéré, multi-domaines,
    avec recommandations automatiques et rapport HTML dédié.

.DESCRIPTION
    Calcule 6 scores indépendants pondérés :

        Domaine          Poids   Ce qui est évalué
        ─────────────────────────────────────────────────────────────
        Réseau           20 %    IP, DNS, passerelle, latence, internet
        Système          20 %    OS, RAM, CPU, uptime, crash dumps
        Sécurité         25 %    Defender, firewall, BitLocker, WDigest, SMBv1
        Stockage         20 %    Disques (% utilisé, SMART)
        Services         15 %    Services auto arrêtés, services critiques

        Score Global = moyenne pondérée des 5 domaines

    Pour chaque score, des recommandations automatiques sont générées
    selon le seuil atteint (OK ≥ 80, Dégradé ≥ 50, Critique < 50).

.PARAMETER ComputerName
    Poste à évaluer (local par défaut).
.PARAMETER HoursBack
    Fenêtre d'analyse des events Windows (défaut 24h).
.PARAMETER OpenReport
    Ouvre le rapport HTML à la fin.
.PARAMETER ExportPath
    Dossier d'export du rapport HTML.
.PARAMETER PassThru
    Retourne l'objet score complet (pour pipelines).

.EXAMPLE
    # Score local avec rapport
    Invoke-HealthScore -OpenReport

    # Score poste distant
    Invoke-HealthScore -ComputerName "PC-DUPONT" -OpenReport

    # Dans un pipeline
    $score = Invoke-HealthScore -PassThru
    if ($score.Global.Score -lt 50) { Send-Alert }

.NOTES
    Auteur  : Amine Berrada
    Version : 1.0.0
    Tags    : scoring, santé, réseau, système, sécurité, stockage, services
#>

Set-StrictMode -Version Latest

# ─────────────────────────────────────────────────────────────
# POIDS PAR DOMAINE (total = 100)
# ─────────────────────────────────────────────────────────────
$script:Weights = @{
    Network  = 20
    System   = 20
    Security = 25
    Storage  = 20
    Services = 15
}

# ─────────────────────────────────────────────────────────────
# SEUILS ET LABELS
# ─────────────────────────────────────────────────────────────
function Get-ScoreLabel([int]$score) {
    if ($score -ge 90) { return "Excellent" }
    if ($score -ge 80) { return "Bon"       }
    if ($score -ge 60) { return "Dégradé"   }
    if ($score -ge 40) { return "Mauvais"   }
    return "Critique"
}

function Get-ScoreColor([int]$score) {
    if ($score -ge 80) { return "#28a745" }
    if ($score -ge 60) { return "#ffc107" }
    if ($score -ge 40) { return "#fd7e14" }
    return "#dc3545"
}

function Get-ScoreIcon([int]$score) {
    if ($score -ge 80) { return "✅" }
    if ($score -ge 60) { return "⚠️" }
    return "❌"
}

# ─────────────────────────────────────────────────────────────
# COLLECTE DONNÉES (local ou distant)
# ─────────────────────────────────────────────────────────────
function _Collect-MachineData {
    param([string]$ComputerName, [int]$HoursBack)

    $sb = {
        param([int]$hrs)

        $data = @{}

        # ── RÉSEAU ──────────────────────────────────────────
        $data.Net = @{}

        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet' }
        $data.Net.APIPA       = ($ips | Where-Object { $_.IPAddress -like '169.254.*' }).Count -gt 0
        $data.Net.HasValidIP  = ($ips | Where-Object { $_.IPAddress -notlike '169.254.*' }).Count -gt 0
        $data.Net.IPList      = ($ips | Select-Object -ExpandProperty IPAddress) -join ', '

        $gw = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
              Sort-Object RouteMetric | Select-Object -First 1
        $data.Net.Gateway     = $gw.NextHop
        $data.Net.GatewayPing = if ($gw.NextHop) {
            Test-Connection $gw.NextHop -Count 2 -Quiet -ErrorAction SilentlyContinue
        } else { $false }

        $data.Net.DNSResolve  = try {
            Resolve-DnsName 'google.com' -ErrorAction Stop | Select-Object -First 1 | Out-Null
            $true
        } catch { $false }

        $pings = Test-Connection '8.8.8.8' -Count 5 -ErrorAction SilentlyContinue
        $data.Net.InternetOK  = ($pings | Measure-Object).Count -gt 0
        $data.Net.LatencyAvg  = if ($pings) {
            [math]::Round(($pings | Measure-Object ResponseTime -Average).Average, 0)
        } else { 9999 }
        $data.Net.PacketLoss  = if ($pings) {
            [math]::Round((1 - $pings.Count / 5) * 100, 0)
        } else { 100 }

        $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.ServerAddresses -and $_.InterfaceAlias -notmatch 'Loopback' } |
               Select-Object -First 1
        $data.Net.DNSServers  = if ($dns) { $dns.ServerAddresses -join ', ' } else { '' }

        # ── SYSTÈME ─────────────────────────────────────────
        $data.Sys = @{}
        $os  = Get-CimInstance Win32_OperatingSystem
        $cs  = Get-CimInstance Win32_ComputerSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1

        $data.Sys.OS         = $os.Caption
        $data.Sys.Build      = $os.BuildNumber
        $data.Sys.UptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
        $data.Sys.RAM_Total  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        $data.Sys.RAM_Free   = [math]::Round($os.FreePhysicalMemory / 1MB, 0)
        $data.Sys.RAM_Pct    = [math]::Round(100 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100), 1)
        $data.Sys.CPU_Load   = $cpu.LoadPercentage
        $data.Sys.CPU_Name   = $cpu.Name.Trim()
        $data.Sys.CrashDumps = (Get-ChildItem 'C:\Windows\Minidump' -Filter '*.dmp' -ErrorAction SilentlyContinue).Count

        $since = (Get-Date).AddHours(-$hrs)
        $evts  = Get-WinEvent -FilterHashtable @{
            LogName = 'System','Application'; Level = 1,2; StartTime = $since
        } -MaxEvents 500 -ErrorAction SilentlyContinue
        $data.Sys.CritEvents = if ($evts) { $evts.Count } else { 0 }

        # Page file usage
        $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue | Select-Object -First 1
        $data.Sys.PageFilePct = if ($pf -and $pf.AllocatedBaseSize -gt 0) {
            [math]::Round($pf.CurrentUsage / $pf.AllocatedBaseSize * 100, 1)
        } else { 0 }

        # ── SÉCURITÉ ────────────────────────────────────────
        $data.Sec = @{}

        $def = Get-MpComputerStatus -ErrorAction SilentlyContinue
        $data.Sec.DefenderEnabled   = $def.AntivirusEnabled -eq $true
        $data.Sec.DefenderUpdated   = if ($def.AntivirusSignatureLastUpdated) {
            ((Get-Date) - $def.AntivirusSignatureLastUpdated).TotalDays -lt 3
        } else { $false }
        $data.Sec.TamperProtection  = $def.IsTamperProtected -eq $true
        $data.Sec.DefenderScanDays  = if ($def.QuickScanStartTime) {
            [math]::Round(((Get-Date) - $def.QuickScanStartTime).TotalDays, 0)
        } else { 999 }

        $fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $data.Sec.FW_Domain  = ($fw | Where-Object Name -eq 'Domain'  | Select-Object -First 1).Enabled -eq $true
        $data.Sec.FW_Private = ($fw | Where-Object Name -eq 'Private' | Select-Object -First 1).Enabled -eq $true
        $data.Sec.FW_Public  = ($fw | Where-Object Name -eq 'Public'  | Select-Object -First 1).Enabled -eq $true

        $bl = Get-BitLockerVolume -ErrorAction SilentlyContinue |
              Where-Object VolumeType -eq 'OperatingSystem' | Select-Object -First 1
        $data.Sec.BitLocker  = $bl.ProtectionStatus -eq 'On'

        $wdigest = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' `
            -ErrorAction SilentlyContinue).UseLogonCredential
        $data.Sec.WDigest    = $wdigest -eq 1   # true = DANGEREUX

        $smb1 = (Get-SmbServerConfiguration -ErrorAction SilentlyContinue).EnableSMB1Protocol
        $data.Sec.SMBv1      = $smb1 -eq $true  # true = DANGEREUX

        $rdpNLA = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
            -ErrorAction SilentlyContinue).UserAuthentication
        $data.Sec.RDP_NLA    = $rdpNLA -eq 1

        $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
            -ErrorAction SilentlyContinue).EnableLUA
        $data.Sec.UAC        = $uac -eq 1

        $adminLocal = Get-LocalUser -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('Administrateur','Administrator') -and $_.Enabled }
        $data.Sec.AdminLocalActive = $adminLocal.Count -gt 0

        # Certificats expirant dans 30j
        $data.Sec.CertsExpiring = (Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
            Where-Object { $_.NotAfter -lt (Get-Date).AddDays(30) }).Count

        # ── STOCKAGE ────────────────────────────────────────
        $data.Storage = @{}
        $data.Storage.Drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.Used + $_.Free -gt 0 } |
            ForEach-Object {
                $pct = [math]::Round($_.Used / ($_.Used + $_.Free) * 100, 1)
                @{
                    Name    = $_.Name
                    TotalGB = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
                    FreeGB  = [math]::Round($_.Free / 1GB, 1)
                    UsedPct = $pct
                }
            }

        # SMART via CIM (PS 5.1 & 7+ compatible)
        $smart = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus `
            -ErrorAction SilentlyContinue
        $data.Storage.SMART_Failures = ($smart | Where-Object PredictFailure -eq $true).Count
        $data.Storage.SMART_Total    = ($smart | Measure-Object).Count

        # Temp size
        $tmpSize = try {
            (Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue |
                Measure-Object Length -Sum).Sum / 1MB
        } catch { 0 }
        $data.Storage.TempMB = [math]::Round($tmpSize, 0)

        # ── SERVICES ────────────────────────────────────────
        $data.Svc = @{}

        $criticalServices = @(
            'Spooler','wuauserv','WinDefend','Dnscache','W32Time',
            'BITS','CryptSvc','EventLog','Schedule','Winmgmt',
            'LanmanWorkstation','LanmanServer','NlaSvc','Netlogon',
            'RpcSs','SamSs','lsass'
        )

        $allAuto = Get-Service -ErrorAction SilentlyContinue |
                   Where-Object { $_.StartType -eq 'Automatic' }

        $data.Svc.TotalAuto    = $allAuto.Count
        $data.Svc.StoppedAuto  = ($allAuto | Where-Object Status -ne 'Running').Count
        $data.Svc.StoppedNames = ($allAuto | Where-Object Status -ne 'Running' |
            Select-Object -ExpandProperty Name) -join ', '

        $critStopped = $criticalServices | Where-Object {
            $svc = Get-Service $_ -ErrorAction SilentlyContinue
            $svc -and $svc.Status -ne 'Running'
        }
        $data.Svc.CritStopped      = $critStopped.Count
        $data.Svc.CritStoppedNames = $critStopped -join ', '

        return $data
    }

    if ($ComputerName -ne $env:COMPUTERNAME) {
        return Invoke-Command -ComputerName $ComputerName -ScriptBlock $sb -ArgumentList $HoursBack -ErrorAction Stop
    } else {
        return & $sb -hrs $HoursBack
    }
}

# ─────────────────────────────────────────────────────────────
# CALCUL SCORE RÉSEAU (max 100)
# ─────────────────────────────────────────────────────────────
function _Score-Network {
    param($net)

    # Grille de points (total possible = 100)
    $points   = 0
    $details  = @()
    $recs     = @()

    # IP valide (20 pts)
    if ($net.APIPA) {
        $details += @{ Check="Adresse IP"; Val="APIPA $($net.IPList)"; Pts=0; Max=20; Sev="critical" }
        $recs    += "CRITIQUE : Adresse APIPA détectée — vérifier le serveur DHCP ou le câble réseau"
    } elseif ($net.HasValidIP) {
        $points  += 20
        $details += @{ Check="Adresse IP"; Val=$net.IPList; Pts=20; Max=20; Sev="ok" }
    }

    # Passerelle joignable (20 pts)
    if (-not $net.Gateway) {
        $details += @{ Check="Passerelle"; Val="Non configurée"; Pts=0; Max=20; Sev="critical" }
        $recs    += "CRITIQUE : Aucune passerelle — vérifier la configuration réseau"
    } elseif (-not $net.GatewayPing) {
        $details += @{ Check="Passerelle $($net.Gateway)"; Val="Injoignable"; Pts=5; Max=20; Sev="critical" }
        $recs    += "CRITIQUE : Passerelle $($net.Gateway) injoignable — vérifier routeur/switch"
        $points  += 5
    } else {
        $points  += 20
        $details += @{ Check="Passerelle $($net.Gateway)"; Val="Joignable"; Pts=20; Max=20; Sev="ok" }
    }

    # DNS (20 pts)
    if (-not $net.DNSResolve) {
        $details += @{ Check="Résolution DNS"; Val="Échec google.com"; Pts=0; Max=20; Sev="critical" }
        $recs    += "CRITIQUE : Résolution DNS impossible — vider le cache (ipconfig /flushdns) et vérifier les serveurs DNS"
        if ($net.DNSServers) { $recs += "Serveurs DNS configurés : $($net.DNSServers)" }
    } else {
        $points  += 20
        $details += @{ Check="Résolution DNS"; Val="OK"; Pts=20; Max=20; Sev="ok" }
    }

    # Internet (20 pts)
    if (-not $net.InternetOK) {
        $details += @{ Check="Connectivité internet"; Val="Aucune (8.8.8.8)"; Pts=0; Max=20; Sev="critical" }
        $recs    += "CRITIQUE : Pas d'accès internet — vérifier FAI, proxy, firewall"
        $points  += 0
    } else {
        $points  += 20
        $details += @{ Check="Connectivité internet"; Val="OK (8.8.8.8)"; Pts=20; Max=20; Sev="ok" }
    }

    # Latence (10 pts)
    $latPts  = if ($net.LatencyAvg -le 20)  { 10 }
               elseif ($net.LatencyAvg -le 50)  { 8 }
               elseif ($net.LatencyAvg -le 100) { 5 }
               elseif ($net.LatencyAvg -le 200) { 2 }
               else { 0 }
    $latSev  = if ($latPts -ge 8) { "ok" } elseif ($latPts -ge 4) { "warn" } else { "critical" }
    $points += $latPts
    $details += @{ Check="Latence internet"; Val="$($net.LatencyAvg) ms (perte $($net.PacketLoss)%)"; Pts=$latPts; Max=10; Sev=$latSev }
    if ($latPts -lt 5) { $recs += "Latence élevée ($($net.LatencyAvg) ms) — possible saturation réseau ou problème FAI" }
    if ($net.PacketLoss -gt 10) { $recs += "Perte de paquets $($net.PacketLoss)% — vérifier câble, switch, carte réseau" }

    # Perte de paquets (10 pts) — sans ce critère le barème plafonnait à 90
    $lossPts = if ($net.PacketLoss -le 0) { 10 } elseif ($net.PacketLoss -le 5) { 7 } elseif ($net.PacketLoss -le 10) { 4 } else { 0 }
    $points += $lossPts
    $details += @{ Check="Perte de paquets"; Val="$($net.PacketLoss)%"; Pts=$lossPts; Max=10; Sev=$(if ($lossPts -ge 7) { "ok" } elseif ($lossPts -ge 4) { "warn" } else { "critical" }) }

    # Une couche réseau fondamentale en échec rend le poste inopérant : plafond du score
    if ($net.APIPA) { $points = [Math]::Min($points, 25) }
    elseif (-not $net.Gateway -or -not $net.GatewayPing -or -not $net.InternetOK -or -not $net.DNSResolve) { $points = [Math]::Min($points, 60) }

    $score = [Math]::Min(100, [Math]::Max(0, $points))
    return @{ Score=$score; Label=(Get-ScoreLabel $score); Details=$details; Recommendations=$recs }
}

# ─────────────────────────────────────────────────────────────
# CALCUL SCORE SYSTÈME (max 100)
# ─────────────────────────────────────────────────────────────
function _Score-System {
    param($sys)

    $points  = 100
    $details = @()
    $recs    = @()

    # RAM (30 pts max)
    $ramPts = if ($sys.RAM_Pct -le 60) { 30 }
              elseif ($sys.RAM_Pct -le 75) { 24 }
              elseif ($sys.RAM_Pct -le 85) { 15 }
              elseif ($sys.RAM_Pct -le 92) { 5  }
              else { 0 }
    $ramSev  = if ($ramPts -ge 24) { "ok" } elseif ($ramPts -ge 10) { "warn" } else { "critical" }
    $ramLoss = 30 - $ramPts; $points -= $ramLoss
    $details += @{ Check="RAM"; Val="$($sys.RAM_Pct)% ($($sys.RAM_Free) Mo libres / $($sys.RAM_Total) Go)"; Pts=$ramPts; Max=30; Sev=$ramSev }
    if ($sys.RAM_Pct -gt 85) { $recs += "RAM critique ($($sys.RAM_Pct)%) — identifier les processus consommateurs, envisager un upgrade" }
    elseif ($sys.RAM_Pct -gt 75) { $recs += "RAM élevée ($($sys.RAM_Pct)%) — surveiller les applications en cours" }

    # CPU (25 pts max)
    $cpuPts = if ($sys.CPU_Load -le 40) { 25 }
              elseif ($sys.CPU_Load -le 65) { 20 }
              elseif ($sys.CPU_Load -le 80) { 12 }
              elseif ($sys.CPU_Load -le 90) { 4  }
              else { 0 }
    $cpuSev  = if ($cpuPts -ge 20) { "ok" } elseif ($cpuPts -ge 8) { "warn" } else { "critical" }
    $cpuLoss = 25 - $cpuPts; $points -= $cpuLoss
    $details += @{ Check="CPU"; Val="$($sys.CPU_Load)% — $($sys.CPU_Name)"; Pts=$cpuPts; Max=25; Sev=$cpuSev }
    if ($sys.CPU_Load -gt 80) { $recs += "CPU élevé ($($sys.CPU_Load)%) — vérifier les processus avec le Gestionnaire des tâches" }

    # Uptime (15 pts max)
    $uptPts = if ($sys.UptimeDays -le 7)  { 15 }
              elseif ($sys.UptimeDays -le 14) { 12 }
              elseif ($sys.UptimeDays -le 30) { 8  }
              elseif ($sys.UptimeDays -le 60) { 3  }
              else { 0 }
    $uptSev  = if ($uptPts -ge 12) { "ok" } elseif ($uptPts -ge 6) { "warn" } else { "critical" }
    $uptLoss = 15 - $uptPts; $points -= $uptLoss
    $details += @{ Check="Uptime"; Val="$($sys.UptimeDays) jours"; Pts=$uptPts; Max=15; Sev=$uptSev }
    if ($sys.UptimeDays -gt 30) { $recs += "Uptime de $($sys.UptimeDays) jours — planifier un redémarrage (mises à jour en attente probables)" }

    # Events critiques (20 pts max)
    $evtPts = if ($sys.CritEvents -eq 0)  { 20 }
              elseif ($sys.CritEvents -le 5)  { 16 }
              elseif ($sys.CritEvents -le 15) { 10 }
              elseif ($sys.CritEvents -le 30) { 4  }
              else { 0 }
    $evtSev  = if ($evtPts -ge 16) { "ok" } elseif ($evtPts -ge 8) { "warn" } else { "critical" }
    $evtLoss = 20 - $evtPts; $points -= $evtLoss
    $details += @{ Check="Events critiques 24h"; Val="$($sys.CritEvents) événement(s)"; Pts=$evtPts; Max=20; Sev=$evtSev }
    if ($sys.CritEvents -gt 15) { $recs += "$($sys.CritEvents) événements critiques en 24h — analyser l'Event Viewer (System + Application)" }

    # Crash dumps (10 pts max)
    $crPts = if ($sys.CrashDumps -eq 0) { 10 }
             elseif ($sys.CrashDumps -le 2) { 6 }
             elseif ($sys.CrashDumps -le 5) { 2 }
             else { 0 }
    $crSev   = if ($crPts -ge 8) { "ok" } elseif ($crPts -ge 4) { "warn" } else { "critical" }
    $crLoss  = 10 - $crPts; $points -= $crLoss
    $details += @{ Check="Crash dumps (minidump)"; Val="$($sys.CrashDumps) fichier(s)"; Pts=$crPts; Max=10; Sev=$crSev }
    if ($sys.CrashDumps -gt 0) { $recs += "$($sys.CrashDumps) crash dump(s) détecté(s) dans C:\Windows\Minidump — analyser avec WinDbg ou BlueScreenView" }

    if (@($ramSev, $cpuSev, $evtSev, $crSev) -contains "critical") { $points = [Math]::Min($points, 60) }

    $score = [Math]::Min(100, [Math]::Max(0, $points))
    return @{ Score=$score; Label=(Get-ScoreLabel $score); Details=$details; Recommendations=$recs }
}

# ─────────────────────────────────────────────────────────────
# CALCUL SCORE SÉCURITÉ (max 100)
# ─────────────────────────────────────────────────────────────
function _Score-Security {
    param($sec)

    $points  = 0
    $details = @()
    $recs    = @()

    # Defender actif (20 pts)
    if ($sec.DefenderEnabled) {
        $points += 20
        $details += @{ Check="Windows Defender"; Val="Actif"; Pts=20; Max=20; Sev="ok" }
    } else {
        $details += @{ Check="Windows Defender"; Val="DÉSACTIVÉ"; Pts=0; Max=20; Sev="critical" }
        $recs    += "CRITIQUE : Antivirus désactivé — réactiver Defender ou vérifier l'EDR tiers"
    }

    # Signatures Defender (10 pts)
    if ($sec.DefenderUpdated) {
        $points += 10
        $details += @{ Check="Signatures Defender"; Val="À jour (<3j)"; Pts=10; Max=10; Sev="ok" }
    } else {
        $details += @{ Check="Signatures Defender"; Val="Obsolètes (>3j)"; Pts=3; Max=10; Sev="warn" }
        $recs    += "Signatures Defender obsolètes — forcer la mise à jour : Update-MpSignature"
        $points  += 3
    }

    # Firewall domaine (15 pts)
    if ($sec.FW_Domain) {
        $points += 15
        $details += @{ Check="Firewall domaine"; Val="Actif"; Pts=15; Max=15; Sev="ok" }
    } else {
        $details += @{ Check="Firewall domaine"; Val="DÉSACTIVÉ"; Pts=0; Max=15; Sev="critical" }
        $recs    += "CRITIQUE : Firewall domaine désactivé — Set-NetFirewallProfile -Profile Domain -Enabled True"
    }

    # Firewall public (10 pts)
    if ($sec.FW_Public) {
        $points += 10
        $details += @{ Check="Firewall public"; Val="Actif"; Pts=10; Max=10; Sev="ok" }
    } else {
        $details += @{ Check="Firewall public"; Val="DÉSACTIVÉ"; Pts=0; Max=10; Sev="critical" }
        $recs    += "CRITIQUE : Firewall public désactivé — risque exposition externe"
    }

    # BitLocker (10 pts)
    if ($sec.BitLocker) {
        $points += 10
        $details += @{ Check="BitLocker"; Val="Actif"; Pts=10; Max=10; Sev="ok" }
    } else {
        $points += 4
        $details += @{ Check="BitLocker"; Val="Inactif"; Pts=4; Max=10; Sev="warn" }
        $recs    += "BitLocker non activé — activer le chiffrement du disque OS (Enable-BitLocker)"
    }

    # WDigest (10 pts — 0 si activé = dangereux)
    if (-not $sec.WDigest) {
        $points += 10
        $details += @{ Check="WDigest"; Val="Désactivé (OK)"; Pts=10; Max=10; Sev="ok" }
    } else {
        $details += @{ Check="WDigest"; Val="ACTIVÉ — credentials en clair"; Pts=0; Max=10; Sev="critical" }
        $recs    += "CRITIQUE : WDigest activé — credentials stockés en mémoire non chiffrés (risque Pass-the-Hash)"
    }

    # SMBv1 (10 pts — 0 si activé)
    if (-not $sec.SMBv1) {
        $points += 10
        $details += @{ Check="SMBv1"; Val="Désactivé (OK)"; Pts=10; Max=10; Sev="ok" }
    } else {
        $details += @{ Check="SMBv1"; Val="ACTIVÉ — vecteur EternalBlue"; Pts=0; Max=10; Sev="critical" }
        $recs    += "CRITIQUE : SMBv1 actif — vecteur WannaCry/EternalBlue : Set-SmbServerConfiguration -EnableSMB1Protocol `$false"
    }

    # UAC (5 pts)
    if ($sec.UAC) {
        $points += 5
        $details += @{ Check="UAC"; Val="Actif"; Pts=5; Max=5; Sev="ok" }
    } else {
        $details += @{ Check="UAC"; Val="DÉSACTIVÉ"; Pts=0; Max=5; Sev="critical" }
        $recs    += "CRITIQUE : UAC désactivé — tout processus s'exécute en admin sans demande"
    }

    # RDP NLA (5 pts)
    if ($sec.RDP_NLA) {
        $points += 5
        $details += @{ Check="RDP NLA"; Val="Requis (OK)"; Pts=5; Max=5; Sev="ok" }
    } else {
        $details += @{ Check="RDP NLA"; Val="Non requis"; Pts=2; Max=5; Sev="warn" }
        $recs    += "Activer NLA pour RDP : Set-ItemProperty 'HKLM:\...\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1"
        $points  += 2
    }

    # Compte admin local actif (malus si actif)
    if ($sec.AdminLocalActive) {
        $details += @{ Check="Compte admin local"; Val="Activé — risque"; Pts=0; Max=5; Sev="warn" }
        $recs    += "Compte Administrateur local activé — désactiver si non nécessaire"
        $points  = [Math]::Max(0, $points - 5)
    } else {
        $points += 5
        $details += @{ Check="Compte admin local"; Val="Désactivé (OK)"; Pts=5; Max=5; Sev="ok" }
    }

    # Certificats expirant
    if ($sec.CertsExpiring -gt 0) {
        $recs    += "$($sec.CertsExpiring) certificat(s) expirant dans 30j — renouveler avant expiration"
        $details += @{ Check="Certificats expiration"; Val="$($sec.CertsExpiring) expirant(s) <30j"; Pts=0; Max=0; Sev="warn" }
        $points  = [Math]::Max(0, $points - 5)
    }

    $score = [Math]::Min(100, [Math]::Max(0, $points))
    return @{ Score=$score; Label=(Get-ScoreLabel $score); Details=$details; Recommendations=$recs }
}

# ─────────────────────────────────────────────────────────────
# CALCUL SCORE STOCKAGE (max 100)
# ─────────────────────────────────────────────────────────────
function _Score-Storage {
    param($storage)

    $points  = 100
    $details = @()
    $recs    = @()

    # Score par disque (pondéré : disque C: plus important)
    foreach ($disk in $storage.Drives) {
        $isSystem = $disk.Name -eq 'C'
        $weight   = if ($isSystem) { 50 } else { [math]::Round(50 / [Math]::Max(1, $storage.Drives.Count - 1), 0) }

        $pts = if ($disk.UsedPct -le 70)  { $weight }
               elseif ($disk.UsedPct -le 80) { [math]::Round($weight * 0.7, 0) }
               elseif ($disk.UsedPct -le 90) { [math]::Round($weight * 0.35, 0) }
               elseif ($disk.UsedPct -le 95) { [math]::Round($weight * 0.1, 0) }
               else { 0 }

        $sev = if ($disk.UsedPct -le 75) { "ok" } elseif ($disk.UsedPct -le 88) { "warn" } else { "critical" }
        $loss = $weight - $pts
        $points -= $loss

        $details += @{
            Check = "Disque $($disk.Name):" + $(if ($isSystem) { " [Système]" } else { "" })
            Val   = "$($disk.UsedPct)% utilisé — $($disk.FreeGB) Go libres / $($disk.TotalGB) Go"
            Pts   = $pts; Max = $weight; Sev = $sev
        }

        if ($disk.UsedPct -gt 90) {
            $recs += "CRITIQUE : Disque $($disk.Name): à $($disk.UsedPct)% — libérer de l'espace ($($disk.FreeGB) Go restants)"
        } elseif ($disk.UsedPct -gt 80) {
            $recs += "Disque $($disk.Name): à $($disk.UsedPct)% — surveiller et planifier un nettoyage"
        }
    }

    # SMART (malus si défaillance prédictive)
    if ($storage.SMART_Failures -gt 0) {
        $points -= 30
        $details += @{ Check="SMART disque"; Val="$($storage.SMART_Failures) DÉFAILLANCE(S) PRÉDICTIVE(S)"; Pts=0; Max=0; Sev="critical" }
        $recs    += "CRITIQUE : Défaillance SMART prédictive détectée — sauvegarder immédiatement et remplacer le disque"
    } elseif ($storage.SMART_Total -gt 0) {
        $details += @{ Check="SMART disque"; Val="OK ($($storage.SMART_Total) disque(s))"; Pts=0; Max=0; Sev="ok" }
    }

    # Fichiers temporaires volumineux
    if ($storage.TempMB -gt 2000) {
        $points -= 5
        $details += @{ Check="Dossier Temp"; Val="$($storage.TempMB) Mo"; Pts=0; Max=0; Sev="warn" }
        $recs    += "Dossier Temp volumineux ($($storage.TempMB) Mo) — nettoyer avec l'outil de nettoyage ou Invoke-Remediation -Fix TempFiles"
    }

    $score = [Math]::Min(100, [Math]::Max(0, $points))
    return @{ Score=$score; Label=(Get-ScoreLabel $score); Details=$details; Recommendations=$recs }
}

# ─────────────────────────────────────────────────────────────
# CALCUL SCORE SERVICES (max 100)
# ─────────────────────────────────────────────────────────────
function _Score-Services {
    param($svc)

    $points  = 100
    $details = @()
    $recs    = @()

    # Services critiques arrêtés (40 pts de malus chacun, plafonné)
    if ($svc.CritStopped -gt 0) {
        $malus = [Math]::Min(80, $svc.CritStopped * 25)
        $points -= $malus
        $details += @{
            Check = "Services critiques arrêtés"
            Val   = "$($svc.CritStopped) : $($svc.CritStoppedNames)"
            Pts   = (80 - $malus); Max = 80; Sev = "critical"
        }
        $recs += "CRITIQUE : $($svc.CritStopped) service(s) critique(s) arrêté(s) : $($svc.CritStoppedNames)"
        $recs += "Commande : Start-Service <NomService> ou sc start <NomService>"
    } else {
        $points += 0  # pas de bonus supplémentaire
        $details += @{ Check="Services critiques"; Val="Tous démarrés"; Pts=80; Max=80; Sev="ok" }
    }

    # Services auto arrêtés non critiques (20 pts de malus)
    $nonCritStopped = [Math]::Max(0, $svc.StoppedAuto - $svc.CritStopped)
    if ($nonCritStopped -gt 0) {
        $malus2 = [Math]::Min(20, $nonCritStopped * 5)
        $points -= $malus2
        $details += @{
            Check = "Services auto non-critiques arrêtés"
            Val   = "$nonCritStopped service(s)"
            Pts   = (20 - $malus2); Max = 20; Sev = "warn"
        }
        if ($nonCritStopped -gt 2) {
            $recs += "$nonCritStopped service(s) en démarrage auto arrêtés — vérifier les dépendances et journaux"
        }
    } else {
        $details += @{ Check="Services auto (non critiques)"; Val="Tous démarrés"; Pts=20; Max=20; Sev="ok" }
    }

    $score = [Math]::Min(100, [Math]::Max(0, $points))
    return @{ Score=$score; Label=(Get-ScoreLabel $score); Details=$details; Recommendations=$recs }
}

# ─────────────────────────────────────────────────────────────
# SCORE GLOBAL PONDÉRÉ
# ─────────────────────────────────────────────────────────────
function _Score-Global {
    param($scores)
    $w = $script:Weights
    $global = [math]::Round(
        ($scores.Network.Score  * $w.Network  +
         $scores.System.Score   * $w.System   +
         $scores.Security.Score * $w.Security +
         $scores.Storage.Score  * $w.Storage  +
         $scores.Services.Score * $w.Services) / 100, 0
    )
    return [Math]::Min(100, [Math]::Max(0, [int]$global))
}

# ─────────────────────────────────────────────────────────────
# RAPPORT HTML SCORING
# ─────────────────────────────────────────────────────────────
function _Export-ScoreReport {
    param($AllScores, [string]$Computer, [string]$OutputPath, [bool]$Sim)

    $global     = $AllScores.Global
    $gColor     = Get-ScoreColor $global.Score
    $gLabel     = Get-ScoreLabel $global.Score
    $gIcon      = Get-ScoreIcon  $global.Score
    $simBadge   = if ($Sim) { "<span class='badge-sim'>SIMULATION</span>" } else { "" }

    # Génération des gauges SVG pour chaque domaine
    function Make-Gauge {
        param([int]$Score, [string]$Label, [string]$DomainName)
        $color   = Get-ScoreColor $Score
        $radius  = 52
        $circ    = [math]::Round(2 * 3.14159 * $radius, 1)
        $fill    = [math]::Round($circ * $Score / 100, 1)
        $gap     = $circ - $fill
        "<div class='gauge-wrap'>
          <svg width='130' height='130' viewBox='0 0 130 130'>
            <circle cx='65' cy='65' r='$radius' fill='none' stroke='#e9ecef' stroke-width='12'/>
            <circle cx='65' cy='65' r='$radius' fill='none' stroke='$color' stroke-width='12'
              stroke-dasharray='$fill $gap'
              stroke-dashoffset='$([math]::Round($circ / 4, 1))'
              stroke-linecap='round'/>
            <text x='65' y='60' text-anchor='middle' font-size='22' font-weight='800' fill='$color'>$Score</text>
            <text x='65' y='78' text-anchor='middle' font-size='11' fill='#888'>/100</text>
          </svg>
          <div class='gauge-label'>$DomainName</div>
          <div class='gauge-sub' style='color:$color'>$Label</div>
        </div>"
    }

    # Détails d'un domaine en tableau
    function Make-DomainTable {
        param($DomainScore, [string]$DomainName)
        $color  = Get-ScoreColor $DomainScore.Score
        $rows   = ($DomainScore.Details | ForEach-Object {
            $bg   = switch ($_.Sev) { "ok"{"#d4edda"} "warn"{"#fff3cd"} "critical"{"#f8d7da"} default{"#f8f9fa"} }
            $icon = switch ($_.Sev) { "ok"{"✅"} "warn"{"⚠️"} "critical"{"❌"} default{"ℹ️"} }
            $bar  = if ($_.Max -gt 0) {
                $pct = [math]::Round($_.Pts / $_.Max * 100)
                $bc  = if ($pct -ge 80) {"#28a745"} elseif ($pct -ge 50) {"#ffc107"} else {"#dc3545"}
                "<div class='mini-bar'><div class='mini-fill' style='width:$pct%;background:$bc'></div></div><span class='pts'>$($_.Pts)/$($_.Max)</span>"
            } else { "" }
            "<tr style='background:$bg'><td>$icon</td><td>$($_.Check)</td><td>$($_.Val)</td><td>$bar</td></tr>"
        }) -join "`n"

        $recRows = if ($DomainScore.Recommendations.Count -gt 0) {
            "<div class='recs'><strong>💡 Recommandations :</strong><ul>" +
            ($DomainScore.Recommendations | ForEach-Object { "<li>$_</li>" }) -join "" +
            "</ul></div>"
        } else { "<div class='recs ok-recs'>✅ Aucune recommandation — domaine sain</div>" }

        "<div class='domain-card'>
          <div class='domain-header' style='border-left:5px solid $color'>
            <span class='domain-title'>$DomainName</span>
            <span class='domain-score' style='color:$color'>$($DomainScore.Score)/100 — $($DomainScore.Label)</span>
          </div>
          <table class='check-table'>
            <tr><th></th><th>Vérification</th><th>Valeur</th><th>Points</th></tr>
            $rows
          </table>
          $recRows
        </div>"
    }

    # Toutes les recommandations triées par priorité
    $allRecs = @()
    foreach ($dom in @('Network','System','Security','Storage','Services')) {
        $AllScores[$dom].Recommendations | ForEach-Object {
            $pri = if ($_ -like "CRITIQUE*") { 1 } elseif ($_ -like "*élevé*" -or $_ -like "*danger*") { 2 } else { 3 }
            $allRecs += @{ Priority=$pri; Domain=$dom; Rec=$_ }
        }
    }
    $allRecs = $allRecs | Sort-Object Priority

    $recTableRows = ($allRecs | ForEach-Object {
        $bg   = switch ($_.Priority) { 1{"#f8d7da"} 2{"#fff3cd"} default{"#e2f3fd"} }
        $badge= switch ($_.Priority) { 1{"🔴 Critique"} 2{"🟡 Important"} default{"🔵 Info"} }
        "<tr style='background:$bg'><td>$badge</td><td><strong>$($_.Domain)</strong></td><td>$($_.Rec)</td></tr>"
    }) -join "`n"

    $simNote = if ($Sim) { "<div class='sim-note'>⚠️ Mode SIMULATION — Les valeurs reflètent l'état réel mais aucune action n'a été effectuée.</div>" } else { "" }

    $html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Score Santé Machine — $Computer</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'Segoe UI',Arial,sans-serif;background:#f0f2f5;color:#333;font-size:14px}
    .hdr{background:linear-gradient(135deg,#0d1b2a,#1b2838);color:#fff;padding:30px 40px}
    .hdr h1{font-size:1.6em;margin-bottom:8px}
    .hdr p{opacity:.8;font-size:.9em}
    .badge-sim{background:#ffc107;color:#000;padding:2px 10px;border-radius:10px;font-size:.8em;margin-left:10px;font-weight:700}
    .sim-note{background:#fff3cd;border:1px solid #ffc107;border-radius:8px;padding:12px 18px;margin:16px 0;font-weight:600}
    .container{max-width:1300px;margin:20px auto;padding:0 20px}

    /* Score global */
    .global-card{background:#fff;border-radius:14px;padding:30px;margin:16px 0;
                 box-shadow:0 4px 16px rgba(0,0,0,.1);text-align:center}
    .global-num{font-size:5em;font-weight:900;color:$gColor;line-height:1}
    .global-label{font-size:1.4em;font-weight:700;color:$gColor;margin-top:6px}
    .global-bar{height:22px;border-radius:11px;background:#e9ecef;overflow:hidden;
                max-width:600px;margin:16px auto}
    .global-fill{height:100%;border-radius:11px;background:$gColor;
                 width:$($global.Score)%;transition:width 1.2s}

    /* Gauges domaines */
    .gauges{display:flex;flex-wrap:wrap;justify-content:center;gap:20px;margin:20px 0}
    .gauge-wrap{text-align:center}
    .gauge-label{font-weight:700;font-size:.95em;margin-top:6px}
    .gauge-sub{font-size:.82em;margin-top:2px}

    /* Poids */
    .weights{display:flex;flex-wrap:wrap;gap:10px;justify-content:center;margin:10px 0}
    .weight-tag{background:#e8f0fe;color:#1a73e8;border-radius:20px;padding:4px 14px;
                font-size:.82em;font-weight:600}

    /* Domaines */
    .domain-card{background:#fff;border-radius:10px;padding:22px;margin:14px 0;
                 box-shadow:0 2px 8px rgba(0,0,0,.07)}
    .domain-header{display:flex;justify-content:space-between;align-items:center;
                   padding-left:12px;margin-bottom:14px}
    .domain-title{font-size:1.05em;font-weight:700}
    .domain-score{font-size:1em;font-weight:700}
    .check-table{width:100%;border-collapse:collapse;margin-bottom:14px}
    .check-table th{background:#1b2838;color:#fff;padding:8px 12px;text-align:left;font-size:.85em}
    .check-table td{padding:7px 12px;border-bottom:1px solid #f0f0f0;font-size:.87em;vertical-align:middle}
    .mini-bar{display:inline-block;width:80px;height:8px;background:#e9ecef;
              border-radius:4px;overflow:hidden;vertical-align:middle;margin-right:6px}
    .mini-fill{height:100%;border-radius:4px}
    .pts{font-size:.8em;color:#666}
    .recs{background:#f8f9fa;border-radius:8px;padding:12px 16px;margin-top:10px;font-size:.88em}
    .recs ul{margin:6px 0 0 18px}
    .recs li{margin:4px 0;line-height:1.5}
    .ok-recs{color:#155724}

    /* Tableau recommandations */
    .section{background:#fff;border-radius:10px;padding:22px;margin:14px 0;
             box-shadow:0 2px 8px rgba(0,0,0,.07)}
    .section h2{font-size:1em;font-weight:700;color:#0078d4;padding-bottom:10px;
                margin-bottom:14px;border-bottom:2px solid #f0f0f0}
    table.rec-table{width:100%;border-collapse:collapse}
    table.rec-table th{background:#0d1b2a;color:#fff;padding:9px 12px;text-align:left;font-size:.85em}
    table.rec-table td{padding:8px 12px;border-bottom:1px solid #f0f0f0;font-size:.87em}

    .footer{text-align:center;padding:24px;color:#aaa;font-size:.82em}
    @media print{body{background:#fff}.hdr{-webkit-print-color-adjust:exact;background:#0d1b2a!important}}
  </style>
</head>
<body>

<div class="hdr">
  <h1>💻 Score Santé Machine — $Computer $simBadge</h1>
  <p>$(Get-Date -Format 'dd/MM/yyyy HH:mm') &nbsp;|&nbsp; Opérateur : $env:USERNAME &nbsp;|&nbsp; ESN-Toolkit v2.0</p>
</div>

<div class="container">

  $simNote

  <!-- Score global -->
  <div class="global-card">
    <div class="global-num">$gIcon $($global.Score)</div>
    <div style="font-size:.8em;color:#888;margin-top:2px">/100</div>
    <div class="global-label">$gLabel</div>
    <div class="global-bar"><div class="global-fill"></div></div>
    <div class="weights">
$(($script:Weights.Keys | ForEach-Object { "<span class='weight-tag'>$_ : $($script:Weights[$_])%</span>" }) -join "`n")
    </div>
  </div>

  <!-- Gauges par domaine -->
  <div class="gauges">
    $(Make-Gauge $AllScores.Network.Score  $AllScores.Network.Label  "Réseau")
    $(Make-Gauge $AllScores.System.Score   $AllScores.System.Label   "Système")
    $(Make-Gauge $AllScores.Security.Score $AllScores.Security.Label "Sécurité")
    $(Make-Gauge $AllScores.Storage.Score  $AllScores.Storage.Label  "Stockage")
    $(Make-Gauge $AllScores.Services.Score $AllScores.Services.Label "Services")
  </div>

  <!-- Tableau des recommandations prioritaires -->
  $(if ($allRecs.Count -gt 0) {
    "<div class='section'>
    <h2>🎯 Recommandations prioritaires ($($allRecs.Count))</h2>
    <table class='rec-table'>
      <tr><th>Priorité</th><th>Domaine</th><th>Action recommandée</th></tr>
      $recTableRows
    </table>
    </div>"
  } else {
    "<div class='section'><h2>🎯 Recommandations</h2><p style='color:#155724;font-weight:600'>✅ Aucune recommandation — machine en excellente santé !</p></div>"
  })

  <!-- Détails par domaine -->
  $(Make-DomainTable $AllScores.Network  "🌐 Réseau    — Poids $($script:Weights.Network)%")
  $(Make-DomainTable $AllScores.System   "🖥️ Système   — Poids $($script:Weights.System)%")
  $(Make-DomainTable $AllScores.Security "🔒 Sécurité  — Poids $($script:Weights.Security)%")
  $(Make-DomainTable $AllScores.Storage  "💾 Stockage  — Poids $($script:Weights.Storage)%")
  $(Make-DomainTable $AllScores.Services "⚙️ Services  — Poids $($script:Weights.Services)%")

</div>

<div class="footer">
  ESN-Toolkit v2.0 — Score Santé Machine — Généré le $(Get-Date -Format 'dd/MM/yyyy à HH:mm:ss')
</div>
</body>
</html>
"@

    New-Item -Path (Split-Path $OutputPath) -ItemType Directory -Force | Out-Null
    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    return $OutputPath
}

# ─────────────────────────────────────────────────────────────
# FONCTION PRINCIPALE
# ─────────────────────────────────────────────────────────────
function Invoke-HealthScore {
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        [int]   $HoursBack    = 24,
        [switch]$OpenReport,
        [string]$ExportPath   = "",
        [switch]$Simulation,
        [switch]$PassThru
    )

    $isRemote = ($ComputerName -ne $env:COMPUTERNAME)

    # Banner
    Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  ESN-Toolkit — Score Santé Machine" -ForegroundColor Cyan
    Write-Host "║  Cible : $ComputerName" -ForegroundColor Cyan
    if ($Simulation) { Write-Host "║  ⚠️  MODE SIMULATION" -ForegroundColor Yellow }
    Write-Host "╚══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    # Connectivité si distant
    if ($isRemote -and -not (Test-Connection $ComputerName -Count 1 -Quiet -EA SilentlyContinue)) {
        Write-Host "[ERREUR] $ComputerName injoignable" -ForegroundColor Red
        return $null
    }

    # Collecte
    Write-Host "[*] Collecte des données..." -ForegroundColor Cyan
    try {
        $data = _Collect-MachineData -ComputerName $ComputerName -HoursBack $HoursBack
    } catch {
        Write-Host "[ERREUR] Collecte impossible : $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    Write-Host "[+] Données collectées" -ForegroundColor Green

    # Calcul des scores
    Write-Host "[*] Calcul des scores..." -ForegroundColor Cyan
    $scores = @{
        Network  = _Score-Network  $data.Net
        System   = _Score-System   $data.Sys
        Security = _Score-Security $data.Sec
        Storage  = _Score-Storage  $data.Storage
        Services = _Score-Services $data.Svc
    }
    $globalScore = _Score-Global $scores
    $scores.Global = @{
        Score = $globalScore
        Label = Get-ScoreLabel $globalScore
    }

    # Affichage console
    Write-Host ""
    $domains = [ordered]@{
        "Réseau"   = $scores.Network
        "Système"  = $scores.System
        "Sécurité" = $scores.Security
        "Stockage" = $scores.Storage
        "Services" = $scores.Services
    }

    foreach ($name in $domains.Keys) {
        $s   = $domains[$name]
        $col = if ($s.Score -ge 80) {"Green"} elseif ($s.Score -ge 60) {"Yellow"} else {"Red"}
        $bar = "█" * [math]::Round($s.Score / 5)
        $emp = "░" * (20 - [math]::Round($s.Score / 5))
        Write-Host ("  {0,-12} [{1}{2}] {3,3}/100  {4}" -f $name, $bar, $emp, $s.Score, $s.Label) -ForegroundColor $col
    }

    Write-Host ""
    $gc  = if ($globalScore -ge 80) {"Green"} elseif ($globalScore -ge 60) {"Yellow"} else {"Red"}
    $gbar= "█" * [math]::Round($globalScore / 5)
    $gemp= "░" * (20 - [math]::Round($globalScore / 5))
    Write-Host ("  {0,-12} [{1}{2}] {3,3}/100  {4}" -f "── GLOBAL ──", $gbar, $gemp, $globalScore, (Get-ScoreLabel $globalScore)) -ForegroundColor $gc
    Write-Host ""

    # Recommandations critiques en console
    $critRecs = @()
    foreach ($dom in $scores.Keys) {
        if ($scores[$dom].Recommendations) {
            $scores[$dom].Recommendations | Where-Object { $_ -like "CRITIQUE*" } |
                ForEach-Object { $critRecs += $_ }
        }
    }
    if ($critRecs.Count -gt 0) {
        Write-Host "  ❌ Points critiques à corriger :" -ForegroundColor Red
        $critRecs | ForEach-Object { Write-Host "     • $_" -ForegroundColor Red }
        Write-Host ""
    }

    # Rapport HTML
    if (-not $ExportPath) {
        $rBase      = if (Get-Command Get-ESNToolkitRoot -ErrorAction SilentlyContinue) { Get-ESNToolkitRoot -SubFolder "Reports" } elseif ($env:ESN_TOOLKIT_ROOT) { Join-Path $env:ESN_TOOLKIT_ROOT "Reports" } elseif ($env:SystemDrive) { "$($env:SystemDrive)\ESN-Toolkit\Reports" } else { Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports" }
        $rDir       = Join-Path $rBase (Get-Date -Format 'yyyy-MM-dd')
        $ExportPath = Join-Path $rDir "HealthScore_${ComputerName}_$(Get-Date -Format 'HHmm').html"
    }

    $reportPath = _Export-ScoreReport -AllScores $scores -Computer $ComputerName `
                    -OutputPath $ExportPath -Sim $Simulation.IsPresent

    Write-Host "  Rapport : $reportPath" -ForegroundColor Cyan

    if ($OpenReport) { Start-Process $reportPath }

    # Retour objet structuré
    $result = [PSCustomObject]@{
        ComputerName     = $ComputerName
        Timestamp        = Get-Date
        Global           = [PSCustomObject]@{ Score=$globalScore; Label=(Get-ScoreLabel $globalScore) }
        Network          = [PSCustomObject]@{ Score=$scores.Network.Score;  Label=$scores.Network.Label;  Recommendations=$scores.Network.Recommendations  }
        System           = [PSCustomObject]@{ Score=$scores.System.Score;   Label=$scores.System.Label;   Recommendations=$scores.System.Recommendations   }
        Security         = [PSCustomObject]@{ Score=$scores.Security.Score; Label=$scores.Security.Label; Recommendations=$scores.Security.Recommendations }
        Storage          = [PSCustomObject]@{ Score=$scores.Storage.Score;  Label=$scores.Storage.Label;  Recommendations=$scores.Storage.Recommendations  }
        Services         = [PSCustomObject]@{ Score=$scores.Services.Score; Label=$scores.Services.Label; Recommendations=$scores.Services.Recommendations }
        ReportPath       = $reportPath
        TotalRecommendations = ($scores.Values | ForEach-Object { $_.Recommendations.Count } | Measure-Object -Sum).Sum
    }

    if ($PassThru) { return $result }
    return $result
}

# ─────────────────────────────────────────────────────────────
# COMPARAISON SCORES (avant/après remédiation)
# ─────────────────────────────────────────────────────────────
function Compare-HealthScore {
<#
.SYNOPSIS
    Compare deux snapshots de score santé (avant/après).
.EXAMPLE
    $before = Invoke-HealthScore -PassThru
    Invoke-Remediation -AutoFix -Force
    $after  = Invoke-HealthScore -PassThru
    Compare-HealthScore -Before $before -After $after
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Before,
        [Parameter(Mandatory)][PSCustomObject]$After
    )

    Write-Host "`n╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  COMPARAISON SCORES — Avant / Après" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    $domains = @("Global","Network","System","Security","Storage","Services")
    foreach ($dom in $domains) {
        $b    = $Before.$dom.Score
        $a    = $After.$dom.Score
        $diff = $a - $b
        $col  = if ($diff -gt 0) {"Green"} elseif ($diff -lt 0) {"Red"} else {"DarkGray"}
        $sign = if ($diff -gt 0) {"▲ +$diff"} elseif ($diff -lt 0) {"▼ $diff"} else {"= 0"}
        Write-Host ("  {0,-12}  Avant: {1,3}  Après: {2,3}  {3}" -f $dom, $b, $a, $sign) -ForegroundColor $col
    }
    Write-Host ""
}

Export-ModuleMember -Function @('Invoke-HealthScore','Compare-HealthScore','Get-ScoreLabel','Get-ScoreColor')
