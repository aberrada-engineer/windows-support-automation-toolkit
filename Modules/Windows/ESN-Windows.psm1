#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-Windows — Diagnostic système Windows : OS, RAM, CPU, disques, services,
    events critiques, drivers, Windows Update, profil.
#>

function Invoke-WindowsDiag {
<#
.SYNOPSIS
    Analyse complète du système Windows d'un poste.
.PARAMETER ComputerName
    Poste cible (local par défaut).
.PARAMETER HoursBack
    Nombre d'heures pour l'analyse des events critiques (défaut 24h).
#>
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        [int]$HoursBack       = 24
    )

    $isRemote = $ComputerName -ne $env:COMPUTERNAME

    if ($isRemote -and -not (Test-Connection $ComputerName -Count 1 -Quiet -EA SilentlyContinue)) {
        Add-ESNResult "Windows" "Joignabilité $ComputerName" "ERROR" "INJOIGNABLE" "" 20
        return
    }

    $collect = {
        param([int]$hrs)
        $out = @{}

        # ── OS ────────────────────────────────────────────
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $out.OS        = $os.Caption
        $out.Build     = $os.BuildNumber
        $out.Arch      = $os.OSArchitecture
        $out.Uptime    = (Get-Date) - $os.LastBootUpTime
        $out.Domain    = $cs.Domain
        $out.Maker     = $cs.Manufacturer
        $out.Model     = $cs.Model
        $out.PSVer     = $PSVersionTable.PSVersion.ToString()
        $out.User      = $cs.UserName

        # ── RAM ──────────────────────────────────────────
        $out.RAM_TotalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        $out.RAM_FreeMB  = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
        $out.RAM_Pct     = [math]::Round(100 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100), 1)

        # ── CPU ──────────────────────────────────────────
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $out.CPU_Name  = $cpu.Name.Trim()
        $out.CPU_Cores = $cpu.NumberOfCores
        $out.CPU_Load  = $cpu.LoadPercentage

        # ── Disques ──────────────────────────────────────
        $out.Disks = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used + $_.Free -gt 0 } |
            Select-Object Name,
                @{N='TotalGB'; E={ [math]::Round(($_.Used+$_.Free)/1GB,1) }},
                @{N='FreeGB';  E={ [math]::Round($_.Free/1GB,1) }},
                @{N='UsedPct'; E={ [math]::Round($_.Used/($_.Used+$_.Free)*100,1) }}

        # ── Services auto arrêtés ────────────────────────
        $out.StoppedSvc = Get-Service |
            Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } |
            Select-Object Name, DisplayName

        # ── Events critiques ─────────────────────────────
        $since = (Get-Date).AddHours(-$hrs)
        $out.CritEvents = Get-WinEvent -FilterHashtable @{
            LogName='System','Application'; Level=1,2; StartTime=$since
        } -MaxEvents 200 -ErrorAction SilentlyContinue |
            Group-Object ProviderName |
            Sort-Object Count -Descending |
            Select-Object -First 8 |
            Select-Object Name, Count

        $critMeasure = $out.CritEvents | Measure-Object Count -Sum
        $out.CritEventsTotal = if ($critMeasure -and $critMeasure.PSObject.Properties['Sum'] -and $null -ne $critMeasure.Sum) {
            [int]$critMeasure.Sum
        } else { 0 }

        # ── Drivers en erreur ────────────────────────────
        $out.BadDrivers = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
            Select-Object Name, ConfigManagerErrorCode

        # ── Windows Update (en attente) ──────────────────
        try {
            $wu  = New-Object -ComObject Microsoft.Update.Session
            $res = $wu.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Software'")
            $out.WU_Pending  = $res.Updates.Count
            $out.WU_Critical = ($res.Updates | Where-Object { $_.MsrcSeverity -eq 'Critical' }).Count
        } catch {
            $out.WU_Pending  = -1
            $out.WU_Critical = -1
        }

        # ── Temp & crash ────────────────────────────────
        $out.CrashDumps = @(Get-ChildItem 'C:\Windows\Minidump' -Filter '*.dmp' -EA SilentlyContinue).Count
        $out.TempSizeMB = try {
            [math]::Round((Get-ChildItem $env:TEMP -Recurse -EA SilentlyContinue |
                Measure-Object Length -Sum).Sum / 1MB, 0)
        } catch { 0 }

        # ── BitLocker ───────────────────────────────────
        $bl = Get-BitLockerVolume -EA SilentlyContinue | Where-Object VolumeType -eq 'OperatingSystem' | Select-Object -First 1
        $out.BitLocker = if ($bl) { $bl.ProtectionStatus } else { "Indisponible" }

        # ── Defender ────────────────────────────────────
        $def = Get-MpComputerStatus -EA SilentlyContinue
        $out.DefenderON  = if ($def) { [bool]$def.AntivirusEnabled } else { $false }
        $out.DefUpdated  = if ($def -and $def.AntivirusSignatureLastUpdated) {
            ((Get-Date) - $def.AntivirusSignatureLastUpdated).TotalDays -lt 3
        } else { $false }

        return $out
    }

    $d = if ($isRemote) {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock $collect -ArgumentList $HoursBack -EA SilentlyContinue
    } else {
        & $collect -hrs $HoursBack
    }

    if (-not $d) {
        Add-ESNResult "Windows" "Collecte $ComputerName" "ERROR" "Échec" "" 15
        return
    }

    # ── Évaluation ────────────────────────────────────────

    # OS / info
    Add-ESNResult "Windows" "Système d'exploitation" "INFO" $d.OS "Build $($d.Build) $($d.Arch)"
    Add-ESNResult "Windows" "Modèle" "INFO" "$($d.Maker) $($d.Model)" "PowerShell $($d.PSVer)"
    Add-ESNResult "Windows" "Domaine" "INFO" $d.Domain "Utilisateur : $($d.User)"

    $uptDays = [math]::Round($d.Uptime.TotalDays, 1)
    $uptSt   = if ($uptDays -gt 30) { "WARN" } else { "OK" }
    Add-ESNResult "Windows" "Uptime" $uptSt "$uptDays jours" "Dernier redémarrage il y a $uptDays j"

    # RAM
    $ramSt = if ($d.RAM_Pct -ge 90) { "ERROR" } elseif ($d.RAM_Pct -ge 80) { "WARN" } else { "OK" }
    Add-ESNResult "Windows" "RAM" $ramSt "$($d.RAM_Pct)% utilisée" "$($d.RAM_FreeMB) Mo libres / $($d.RAM_TotalGB) Go total" `
        -ScoreImpact $(if($ramSt -eq "ERROR"){15}elseif($ramSt -eq "WARN"){5}else{0})

    # CPU
    $cpuSt = if ($d.CPU_Load -ge 90) { "ERROR" } elseif ($d.CPU_Load -ge 75) { "WARN" } else { "OK" }
    Add-ESNResult "Windows" "CPU" $cpuSt "$($d.CPU_Load)%" $d.CPU_Name `
        -ScoreImpact $(if($cpuSt -eq "ERROR"){10}elseif($cpuSt -eq "WARN"){3}else{0})

    # Disques
    foreach ($disk in $d.Disks) {
        $dSt = if ($disk.UsedPct -ge 90) { "ERROR" } elseif ($disk.UsedPct -ge 80) { "WARN" } else { "OK" }
        Add-ESNResult "Windows" "Disque $($disk.Name):" $dSt "$($disk.UsedPct)% utilisé" "$($disk.FreeGB) Go libres / $($disk.TotalGB) Go" `
            -ScoreImpact $(if($dSt -eq "ERROR"){20}elseif($dSt -eq "WARN"){8}else{0})
    }

    # Services
    $stoppedArr = @($d.StoppedSvc | Where-Object { $_ })
    if ($stoppedArr.Count -gt 0) {
        $names = ($stoppedArr | Select-Object -ExpandProperty Name) -join ', '
        Add-ESNResult "Windows" "Services auto arrêtés" "WARN" "$($stoppedArr.Count) service(s)" $names 5
    } else {
        Add-ESNResult "Windows" "Services auto" "OK" "Tous démarrés" ""
    }

    # Events
    $evSt = if ($d.CritEventsTotal -gt 50) { "ERROR" } elseif ($d.CritEventsTotal -gt 10) { "WARN" } else { "OK" }
    $evDetail = if ($d.CritEvents) { ($d.CritEvents | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ' | ' } else { "" }
    Add-ESNResult "Windows" "Events critiques ${HoursBack}h" $evSt "$($d.CritEventsTotal) événement(s)" $evDetail `
        -ScoreImpact $(if($evSt -eq "ERROR"){10}elseif($evSt -eq "WARN"){5}else{0})

    # Drivers
    $badDrvArr = @($d.BadDrivers | Where-Object { $_ })
    $drSt = if ($badDrvArr.Count -ge 3) { "ERROR" } elseif ($badDrvArr.Count -gt 0) { "WARN" } else { "OK" }
    Add-ESNResult "Windows" "Drivers en erreur" $drSt "$($badDrvArr.Count) driver(s)" "" `
        -ScoreImpact $(if($drSt -eq "ERROR"){10}elseif($drSt -eq "WARN"){5}else{0})

    # Windows Update
    if ($d.WU_Pending -ge 0) {
        $wuSt = if ($d.WU_Critical -gt 0) { "ERROR" } elseif ($d.WU_Pending -gt 0) { "WARN" } else { "OK" }
        Add-ESNResult "Windows" "Windows Update" $wuSt "$($d.WU_Pending) MAJ en attente" "$($d.WU_Critical) critique(s)" `
            -ScoreImpact $(if($wuSt -eq "ERROR"){10}elseif($wuSt -eq "WARN"){3}else{0})
    }

    # Crash dumps
    $crSt = if ($d.CrashDumps -ge 3) { "ERROR" } elseif ($d.CrashDumps -gt 0) { "WARN" } else { "OK" }
    Add-ESNResult "Windows" "Crash dumps (minidump)" $crSt "$($d.CrashDumps) fichier(s)" "C:\Windows\Minidump" `
        -ScoreImpact $(if($crSt -eq "ERROR"){15}elseif($crSt -eq "WARN"){5}else{0})

    # Temp
    $tmpSt = if ($d.TempSizeMB -gt 2000) { "WARN" } else { "OK" }
    Add-ESNResult "Windows" "Dossier Temp" $tmpSt "$($d.TempSizeMB) Mo" "%TEMP%"

    # BitLocker
    $blSt = if ($d.BitLocker -eq 'On') { "OK" } else { "WARN" }
    Add-ESNResult "Windows" "BitLocker" $blSt $d.BitLocker "Chiffrement disque OS"

    # Defender
    Add-ESNResult "Windows" "Windows Defender" $(if($d.DefenderON){"OK"}else{"ERROR"}) `
        $(if($d.DefenderON){"Actif"}else{"DÉSACTIVÉ"}) "" `
        -ScoreImpact $(if(-not $d.DefenderON){20}else{0})

    Add-ESNResult "Windows" "Signatures Defender" $(if($d.DefUpdated){"OK"}else{"WARN"}) `
        $(if($d.DefUpdated){"À jour"}else{"Obsolètes (>3j)"}) "" `
        -ScoreImpact $(if(-not $d.DefUpdated){5}else{0})
}

Export-ModuleMember -Function Invoke-WindowsDiag
