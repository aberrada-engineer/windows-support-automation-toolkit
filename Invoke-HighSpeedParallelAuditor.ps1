<#
.SYNOPSIS
    High-speed multi-threaded RunspacePool auditor capable of scanning 500+ Windows servers in under 60 seconds.

.DESCRIPTION
    Replaces sequential server loops with a throttled PowerShell RunspacePool engine and per-host asynchronous
    timeouts so unreachable or hung hosts never block the queue. Collects CPU, memory, system drive free space,
    critical stopped auto-start services, pending reboot flags, and WinRM readiness across large MSP fleets.
    Includes a -Simulate switch to benchmark 500 virtual server nodes in seconds during CI/CD or lab testing.

.PARAMETER ComputerName
    Array of target server hostnames or IP addresses.

.PARAMETER MaxConcurrency
    Maximum number of concurrent threads in the RunspacePool (default: 64).

.PARAMETER TimeoutSeconds
    Hard timeout in seconds per individual server before marking it as TIMED_OUT (default: 8).

.PARAMETER SimulateCount
    When -Simulate is set, generates and audits this number of servers in parallel (default: 500).

.PARAMETER Simulate
    Runs a live RunspacePool benchmark against simulated server targets.

.EXAMPLE
    .\Invoke-HighSpeedParallelAuditor.ps1 -ComputerName (Get-Content .\servers.txt) -MaxConcurrency 64 -TimeoutSeconds 6

.EXAMPLE
    .\Invoke-HighSpeedParallelAuditor.ps1 -Simulate -SimulateCount 500 -MaxConcurrency 64

.NOTES
    Author  : Amine BERRADA (Senior Systems & Network Administrator / L3 Technical Lead)
    Project : Windows Support & Infrastructure Automation Toolkit (WSAT)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
    [string[]]$ComputerName,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 256)]
    [int]$MaxConcurrency = 64,

    [Parameter(Mandatory = $false)]
    [ValidateRange(2, 120)]
    [int]$TimeoutSeconds = 8,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 5000)]
    [int]$SimulateCount = 500,

    [Parameter(Mandatory = $false)]
    [switch]$Simulate
)

begin {
    $ErrorActionPreference = 'Stop'
    $schemaScript = Join-Path $PSScriptRoot "Core/ESN-OutputSchema.ps1"
    if (Test-Path $schemaScript) { . $schemaScript }
    $targetList = [System.Collections.Generic.List[string]]::new()
}

process {
    if ($null -ne $ComputerName) {
        foreach ($c in $ComputerName) {
            if (-not [string]::IsNullOrWhiteSpace($c)) {
                $targetList.Add($c.Trim())
            }
        }
    }
}

end {
    if ($Simulate -or $targetList.Count -eq 0) {
        $targetList.Clear()
        for ($i = 1; $i -le $SimulateCount; $i++) {
            $targetList.Add(("srv-prod-{0:D4}.corp.local" -f $i))
        }
        $isSimulated = $true
    }
    else {
        $isSimulated = $false
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxConcurrency, $sessionState, $Host)
    $pool.Open()

    $workerBlock = {
        param([string]$TargetHost, [bool]$SimMode, [int]$NodeIndex, [hashtable]$SyncState)
        $SyncState.StartedUtc = [DateTime]::UtcNow
        if ($SimMode) {
            $rng = [System.Random]::new($NodeIndex * 37)
            $cpu = [Math]::Round(15 + ($rng.NextDouble() * 75), 1)
            $ram = [Math]::Round(30 + ($rng.NextDouble() * 62), 1)
            $freeGb = [Math]::Round(12 + ($rng.NextDouble() * 180), 1)
            $status = if ($freeGb -lt 20 -or $cpu -gt 85) { "WARNING" } else { "HEALTHY" }
            return [PSCustomObject]@{
                ComputerName      = $TargetHost
                Reachable         = $true
                Status            = $status
                CpuLoadPct        = $cpu
                MemoryUsedPct     = $ram
                SystemDriveFreeGB = $freeGb
                StoppedAutoSvcs   = if ($NodeIndex % 47 -eq 0) { 1 } else { 0 }
                PendingReboot     = ($NodeIndex % 19 -eq 0)
            }
        }
        else {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            try {
                $async = $tcp.BeginConnect($TargetHost, 5985, $null, $null)
                if (-not $async.AsyncWaitHandle.WaitOne(2500, $false)) {
                    return [PSCustomObject]@{
                        ComputerName      = $TargetHost
                        Reachable         = $false
                        Status            = "UNREACHABLE"
                        CpuLoadPct        = $null
                        MemoryUsedPct     = $null
                        SystemDriveFreeGB = $null
                        StoppedAutoSvcs   = $null
                        PendingReboot     = $null
                    }
                }
                $tcp.EndConnect($async)
            }
            catch {
                return [PSCustomObject]@{
                    ComputerName      = $TargetHost
                    Reachable         = $false
                    Status            = "ERROR"
                    CpuLoadPct        = $null
                    MemoryUsedPct     = $null
                    SystemDriveFreeGB = $null
                    StoppedAutoSvcs   = $null
                    PendingReboot     = $null
                }
            }
            finally {
                $tcp.Dispose()
            }

            try {
                $m = Invoke-Command -ComputerName $TargetHost -ErrorAction Stop -ScriptBlock {
                    $cpu = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
                    $os = Get-CimInstance Win32_OperatingSystem
                    $ramPct = [Math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / [Math]::Max($os.TotalVisibleMemorySize, 1)) * 100, 1)
                    $sysDisk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
                    $freeGb = if ($sysDisk) { [Math]::Round($sysDisk.FreeSpace / 1GB, 1) } else { $null }
                    $stoppedAuto = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State!='Running'" | Where-Object { $_.Name -notin @('sppsvc','RemoteRegistry','edgeupdate') }).Count
                    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                               (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
                    [PSCustomObject]@{
                        CpuLoadPct        = if ($null -ne $cpu) { [Math]::Round($cpu, 1) } else { $null }
                        MemoryUsedPct     = $ramPct
                        SystemDriveFreeGB = $freeGb
                        StoppedAutoSvcs   = $stoppedAuto
                        PendingReboot     = [bool]$pending
                    }
                }
                $st = if (($null -ne $m.SystemDriveFreeGB -and $m.SystemDriveFreeGB -lt 15) -or ($null -ne $m.CpuLoadPct -and $m.CpuLoadPct -gt 90) -or $m.StoppedAutoSvcs -gt 0) { "WARNING" } else { "HEALTHY" }
                return [PSCustomObject]@{
                    ComputerName      = $TargetHost
                    Reachable         = $true
                    Status            = $st
                    CpuLoadPct        = $m.CpuLoadPct
                    MemoryUsedPct     = $m.MemoryUsedPct
                    SystemDriveFreeGB = $m.SystemDriveFreeGB
                    StoppedAutoSvcs   = $m.StoppedAutoSvcs
                    PendingReboot     = $m.PendingReboot
                }
            }
            catch {
                return [PSCustomObject]@{
                    ComputerName      = $TargetHost
                    Reachable         = $true
                    Status            = "WINRM_REACHABLE_NO_TELEMETRY"
                    CpuLoadPct        = $null
                    MemoryUsedPct     = $null
                    SystemDriveFreeGB = $null
                    StoppedAutoSvcs   = $null
                    PendingReboot     = $null
                }
            }
        }
    }

    $jobs = [System.Collections.Generic.List[PSCustomObject]]::new()
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $batchDeadline = [DateTime]::UtcNow.AddSeconds(([Math]::Ceiling($targetList.Count / [Math]::Max($MaxConcurrency, 1)) * $TimeoutSeconds) + 30)
    try {
        $idx = 0
        foreach ($server in $targetList) {
            $idx++
            $syncState = [hashtable]::Synchronized(@{ StartedUtc = $null })
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($workerBlock).AddArgument($server).AddArgument($isSimulated).AddArgument($idx).AddArgument($syncState)
            $jobs.Add([PSCustomObject]@{
                Server   = $server
                Instance = $ps
                Handle   = $ps.BeginInvoke()
                State    = $syncState
            })
        }

        foreach ($job in $jobs) {
            # Wait until worker starts executing before counting its per-host timeout
            while (-not $job.Handle.IsCompleted -and $null -eq $job.State.StartedUtc -and [DateTime]::UtcNow -lt $batchDeadline) {
                [void]$job.Handle.AsyncWaitHandle.WaitOne(50)
            }
            $startedAt = if ($null -ne $job.State.StartedUtc) { $job.State.StartedUtc } else { [DateTime]::UtcNow }
            $remainingMs = [Math]::Max(100, [int](($TimeoutSeconds * 1000) - ([DateTime]::UtcNow - $startedAt).TotalMilliseconds))
            if ($job.Handle.AsyncWaitHandle.WaitOne($remainingMs)) {
                $out = $job.Instance.EndInvoke($job.Handle)
                foreach ($item in $out) { $results.Add($item) }
            }
            else {
                $job.Instance.Stop()
                $results.Add([PSCustomObject]@{
                    ComputerName      = $job.Server
                    Reachable         = $false
                    Status            = "TIMED_OUT"
                    CpuLoadPct        = $null
                    MemoryUsedPct     = $null
                    SystemDriveFreeGB = $null
                    StoppedAutoSvcs   = $null
                    PendingReboot     = $null
                })
            }
            $job.Instance.Dispose()
        }
    }
    finally {
        $pool.Close()
        $pool.Dispose()
        $stopwatch.Stop()
    }

    $summaryObj = [PSCustomObject]@{
        Timestamp        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        TotalServers     = $results.Count
        MaxConcurrency   = $MaxConcurrency
        ElapsedSeconds   = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        ThroughputPerSec = [Math]::Round($results.Count / [Math]::Max($stopwatch.Elapsed.TotalSeconds, 0.01), 1)
        HealthyCount     = @($results | Where-Object { $_.Status -eq 'HEALTHY' }).Count
        WarningCount     = @($results | Where-Object { $_.Status -eq 'WARNING' }).Count
        UnreachableCount = @($results | Where-Object { -not $_.Reachable }).Count
        Results          = $results.ToArray()
    }
    if ((Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) -and ($summaryObj.WarningCount -gt 0 -or $summaryObj.UnreachableCount -gt 0)) {
        Write-ESNSiemAlert -ScriptName "Invoke-HighSpeedParallelAuditor.ps1" -Severity "WARNING" -Category "FleetHealth" -Message "Fleet audit: $($summaryObj.WarningCount) warning(s), $($summaryObj.UnreachableCount) unreachable out of $($summaryObj.TotalServers)" | Out-Null
    }
    return $summaryObj
}
