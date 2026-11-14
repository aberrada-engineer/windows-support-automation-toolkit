#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-Network — Diagnostic réseau complet (IP, DNS, latence, VPN, proxy, partages).
#>

function Invoke-NetworkDiag {
<#
.SYNOPSIS
    Diagnostic réseau complet d'un poste.
.PARAMETER ComputerName
    Poste cible (local par défaut).
.PARAMETER AutoFix
    Tenter des corrections automatiques (flush DNS, renouveau DHCP).
#>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        [switch]$AutoFix
    )

    $isRemote = $ComputerName -ne $env:COMPUTERNAME

    if ($isRemote -and -not (Test-Connection $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Add-ESNResult "Réseau" "Joignabilité $ComputerName" "ERROR" "INJOIGNABLE" "Ping échoué" 20
        return
    }

    $collect = {
        param([bool]$autoFix)

        $out = @{}

        # ── Adaptateurs actifs ──────────────────────────
        $out.Adapters = Get-NetAdapter | Where-Object Status -eq Up |
            Select-Object Name, InterfaceDescription, LinkSpeed,
                @{N='MAC';E={$_.MacAddress}}

        # ── Adresses IP (hors loopback / vEthernet) ─────
        $out.IPs = Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet' } |
            Select-Object InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin

        $out.APIPA = $out.IPs | Where-Object { $_.IPAddress -like '169.254.*' }

        # ── Passerelle ──────────────────────────────────
        $gw = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
              Sort-Object RouteMetric | Select-Object -First 1
        $out.Gateway     = if ($gw) { $gw.NextHop } else { $null }
        $out.GatewayPing = if ($gw -and $gw.NextHop) {
            Test-Connection $gw.NextHop -Count 2 -Quiet -ErrorAction SilentlyContinue
        } else { $false }

        # ── DNS ─────────────────────────────────────────
        $out.DNS = Get-DnsClientServerAddress -AddressFamily IPv4 |
                   Where-Object { $_.ServerAddresses -and $_.InterfaceAlias -notmatch 'Loopback' } |
                   Select-Object -First 1 | Select-Object -ExpandProperty ServerAddresses

        $out.DNSResolve = try {
            (Resolve-DnsName 'google.com' -ErrorAction Stop | Select-Object -First 1).IPAddress
        } catch { $null }

        # ── Internet ────────────────────────────────────
        $out.InternetPing = Test-Connection '8.8.8.8' -Count 1 -Quiet -ErrorAction SilentlyContinue

        # ── Latence (5 pings) ───────────────────────────
        $pings = Test-Connection '8.8.8.8' -Count 5 -ErrorAction SilentlyContinue
        $out.LatencyAvg = if ($pings) {
            [math]::Round(($pings | Measure-Object ResponseTime -Average).Average, 0)
        } else { 9999 }
        $out.LatencyMax = if ($pings) {
            ($pings | Measure-Object ResponseTime -Maximum).Maximum
        } else { 9999 }

        # ── Proxy ────────────────────────────────────────
        $prx = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -EA SilentlyContinue
        $out.ProxyEnabled = if ($prx -and $prx.PSObject.Properties['ProxyEnable']) { $prx.ProxyEnable -eq 1 } else { $false }
        $out.ProxyServer  = if ($prx -and $prx.PSObject.Properties['ProxyServer']) { $prx.ProxyServer } else { $null }

        # ── Lecteurs réseau ──────────────────────────────
        $out.NetworkDrives = Get-PSDrive -PSProvider FileSystem |
                             Where-Object { $_.Root -like '\\*' } |
                             Select-Object Name, Root

        # ── Auto-fix ────────────────────────────────────
        $out.AutoFixDone = @()
        if ($autoFix) {
            if ($out.APIPA) {
                ipconfig /release 2>&1 | Out-Null
                Start-Sleep 2
                ipconfig /renew  2>&1 | Out-Null
                $out.AutoFixDone += 'DHCP Renew'
            }
            Clear-DnsClientCache
            $out.AutoFixDone += 'DNS Flush'
        }

        return $out
    }

    $data = if ($isRemote) {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock $collect -ArgumentList $AutoFix.IsPresent -ErrorAction SilentlyContinue
    } else {
        & $collect -autoFix $AutoFix.IsPresent
    }

    if (-not $data) {
        Add-ESNResult "Réseau" "Collecte données $ComputerName" "ERROR" "Échec" "Invoke-Command a échoué" 15
        return
    }

    # ── Évaluation ────────────────────────────────────────
    # Adaptateurs
    if ($data.Adapters) {
        $adapArr = @($data.Adapters)
        $names = ($adapArr | Select-Object -ExpandProperty Name) -join ', '
        Add-ESNResult "Réseau" "Adaptateurs actifs" "OK" "$($adapArr.Count) actif(s)" $names
    } else {
        Add-ESNResult "Réseau" "Adaptateurs actifs" "ERROR" "Aucun" "Aucun adaptateur Up" 20
    }

    # APIPA
    if ($data.APIPA) {
        Add-ESNResult "Réseau" "Adresse IP" "ERROR" "APIPA $($data.APIPA.IPAddress)" "Problème DHCP" 25
    } else {
        $ipList = ($data.IPs | Select-Object -ExpandProperty IPAddress) -join ', '
        Add-ESNResult "Réseau" "Adresse IP" "OK" $ipList ""
    }

    # Passerelle
    if (-not $data.Gateway) {
        Add-ESNResult "Réseau" "Passerelle" "ERROR" "Non configurée" "" 20
    } elseif (-not $data.GatewayPing) {
        Add-ESNResult "Réseau" "Passerelle" "ERROR" "$($data.Gateway) injoignable" "" 20
    } else {
        Add-ESNResult "Réseau" "Passerelle" "OK" $data.Gateway ""
    }

    # DNS
    $dnsStr = $data.DNS -join ', '
    if (-not $data.DNSResolve) {
        Add-ESNResult "Réseau" "Résolution DNS" "ERROR" "Echec google.com" "Serveurs : $dnsStr" 20
    } else {
        Add-ESNResult "Réseau" "Résolution DNS" "OK" "google.com → $($data.DNSResolve)" "Serveurs : $dnsStr"
    }

    # Internet
    if (-not $data.InternetPing) {
        Add-ESNResult "Réseau" "Connectivité internet" "ERROR" "8.8.8.8 injoignable" "" 20
    } else {
        Add-ESNResult "Réseau" "Connectivité internet" "OK" "8.8.8.8 joignable" ""
    }

    # Latence
    $latStatus = if ($data.LatencyAvg -gt 200) { "ERROR" } elseif ($data.LatencyAvg -gt 80) { "WARN" } else { "OK" }
    Add-ESNResult "Réseau" "Latence internet" $latStatus "$($data.LatencyAvg) ms moy / $($data.LatencyMax) ms max" "vers 8.8.8.8" `
        -ScoreImpact $(if($latStatus -eq "ERROR"){10}elseif($latStatus -eq "WARN"){3}else{0})

    # Proxy
    if ($data.ProxyEnabled) {
        Add-ESNResult "Réseau" "Proxy" "WARN" $data.ProxyServer "Proxy activé dans IE/Edge" 3
    } else {
        Add-ESNResult "Réseau" "Proxy" "OK" "Aucun proxy" ""
    }

    # Lecteurs réseau
    if ($data.NetworkDrives) {
        $ndArr = @($data.NetworkDrives)
        $drives = ($ndArr | ForEach-Object { "$($_.Name): → $($_.Root)" }) -join ' | '
        Add-ESNResult "Réseau" "Lecteurs réseau" "INFO" "$($ndArr.Count) mappage(s)" $drives
    } else {
        Add-ESNResult "Réseau" "Lecteurs réseau" "INFO" "Aucun lecteur réseau mappé" ""
    }

    # Auto-fix
    if ($data.AutoFixDone) {
        Add-ESNResult "Réseau" "Auto-fix appliqué" "INFO" ($data.AutoFixDone -join ', ') ""
    }
}

Export-ModuleMember -Function Invoke-NetworkDiag
