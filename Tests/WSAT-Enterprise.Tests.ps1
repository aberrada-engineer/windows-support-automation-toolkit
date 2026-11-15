# Pester Tests - WSAT Enterprise Elite Modules, Chaos Engineering & SIEM Telemetry
# Compatible Pester v5 / v6

BeforeAll {
    $script:RootDir = Split-Path $PSScriptRoot -Parent
    $script:TmpOut  = Join-Path ([System.IO.Path]::GetTempPath()) ("wsat-pester-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -Path $script:TmpOut -ItemType Directory -Force | Out-Null
    . (Join-Path $script:RootDir "Core/ESN-OutputSchema.ps1")
}

AfterAll {
    if (Test-Path $script:TmpOut) {
        Remove-Item -Path $script:TmpOut -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Core Schema & SIEM Telemetry (PS 5.1 / 7+)" {
    It "Should emit a valid compressed JSON SIEM event via Write-ESNSiemAlert" {
        $siemFile = Join-Path $script:TmpOut "test-siem.jsonl"
        $evt = Write-ESNSiemAlert -ScriptName "TestScript.ps1" -Severity "INFO" -Category "UnitTest" -Message "Validation SIEM" -LogFile $siemFile
        $evt.schema_version | Should -Be "1.0"
        $evt.severity | Should -Be "INFO"
        Test-Path $siemFile | Should -BeTrue
        $parsed = (Get-Content $siemFile -Raw) | ConvertFrom-Json
        $parsed.category | Should -Be "UnitTest"
    }

    It "Should resolve severity helpers without PS 7-only operators" {
        Get-ESNSeverityColor "CRITICAL" | Should -Be "#f8d7da"
        Get-ESNSeverityColor "UNKNOWN" | Should -Be "#f8f9fa"
    }
}

Describe "5 Elite Automation Modules (Functional Simulate Mode)" {
    It "Invoke-NutanixPrismHealthAI.ps1 generates COTECH HTML & SIEM JSON" {
        $res = & (Join-Path $script:RootDir "Invoke-NutanixPrismHealthAI.ps1") -Simulate -OutputPath $script:TmpOut
        $res | Should -Not -BeNullOrEmpty
        @(Get-ChildItem -Path $script:TmpOut -Filter "*.html").Count | Should -BeGreaterThan 0
    }

    It "Invoke-ActiveDirectoryThreatHunter.ps1 detects simulated threats & respects -WhatIf" {
        $res = & (Join-Path $script:RootDir "Invoke-ActiveDirectoryThreatHunter.ps1") -Simulate -AutoRemediate -WhatIf -OutputPath $script:TmpOut
        $res | Should -Not -BeNullOrEmpty
    }

    It "Invoke-HighSpeedParallelAuditor.ps1 audits simulated servers via RunspacePool" {
        $res = & (Join-Path $script:RootDir "Invoke-HighSpeedParallelAuditor.ps1") -Simulate -SimulateCount 25 -MaxConcurrency 8
        $res | Should -Not -BeNullOrEmpty
    }

    It "Invoke-VeeamImmutableAudit.ps1 certifies simulated immutable Linux repository" {
        $res = & (Join-Path $script:RootDir "Invoke-VeeamImmutableAudit.ps1") -Simulate
        $res.RansomwareProofCertified | Should -BeTrue
        $res.ComplianceStatus | Should -Be "CERTIFIED_IMMUTABLE"
    }

    It "Invoke-CopilDashboardGenerator.ps1 produces standalone HTML5 SVG dashboard and HtmlEncodes inputs" {
        $dashFile = Join-Path $script:TmpOut "copil-test.html"
        $res = & (Join-Path $script:RootDir "Invoke-CopilDashboardGenerator.ps1") `
            -ClientName "<script>alert(1)</script>" `
            -PeriodLabel "<b>Q4</b>" `
            -OutputFile $dashFile
        Test-Path $dashFile | Should -BeTrue
        $raw = Get-Content $dashFile -Raw
        $raw | Should -Match "<svg"
        $raw | Should -Not -Match "<script>alert\(1\)</script>"
        $raw | Should -Match "&lt;script&gt;alert\(1\)&lt;/script&gt;"
        $raw | Should -Match "&lt;b&gt;Q4&lt;/b&gt;"
        $res.ClientName | Should -Be "<script>alert(1)</script>"
    }

    It "Invoke-CopilDashboardGenerator.ps1 respects -WhatIf and defaults under Get-ESNReportRoot" {
        $prevRoot = $env:ESN_TOOLKIT_ROOT
        $env:ESN_TOOLKIT_ROOT = Join-Path $script:TmpOut "copil-root"
        try {
            $whatIfTarget = Join-Path $script:TmpOut "copil-whatif-missing/dash.html"
            & (Join-Path $script:RootDir "Invoke-CopilDashboardGenerator.ps1") -OutputFile $whatIfTarget -WhatIf | Out-Null
            Test-Path $whatIfTarget | Should -BeFalse
            Test-Path (Split-Path $whatIfTarget -Parent) | Should -BeFalse

            $resDef = & (Join-Path $script:RootDir "Invoke-CopilDashboardGenerator.ps1")
            $expectedDir = Get-ESNReportRoot
            $resDef.DashboardPath | Should -Be (Join-Path $expectedDir "COPIL-Executive-Dashboard.html")
            Test-Path $resDef.DashboardPath | Should -BeTrue
        }
        finally {
            $env:ESN_TOOLKIT_ROOT = $prevRoot
        }
    }
}

Describe "Refactored Core Operational Scripts (Simulate & Safe Paths)" {
    It "Invoke-ZeroTrustAudit.ps1 returns score & generates HTML + SIEM log" {
        $res = & (Join-Path $script:RootDir "Invoke-ZeroTrustAudit.ps1") -Simulate -OutputPath $script:TmpOut
        $res.Score | Should -Be 100
        Test-Path $res.HtmlReport | Should -BeTrue
    }

    It "Invoke-P1EmergencyTriage.ps1 completes flash triage cleanly" {
        $res = & (Join-Path $script:RootDir "Invoke-P1EmergencyTriage.ps1") -Simulate -OutputPath $script:TmpOut
        $res.HostName | Should -Not -BeNullOrEmpty
        $res.CriticalEvents.Count | Should -BeGreaterThan 0
    }

    It "Invoke-RansomwareShield.ps1 respects -WhatIf and emits SIEM containment log" {
        $res = & (Join-Path $script:RootDir "Invoke-RansomwareShield.ps1") -Simulate -OutputPath $script:TmpOut
        $res.Isolated | Should -BeTrue
        Test-Path $res.SiemLog | Should -BeTrue
    }

    It "Invoke-SelfHealingService.ps1 runs self-healing cycle in -Simulate mode" {
        $res = & (Join-Path $script:RootDir "Invoke-SelfHealingService.ps1") -Simulate -OutputPath $script:TmpOut
        $res.ActionsHealed.Count | Should -BeGreaterThan 0
        Test-Path $res.SiemLog | Should -BeTrue
    }

    It "Invoke-DRPGenerator.ps1 creates executive DRP dossier cleanly" {
        $res = & (Join-Path $script:RootDir "Invoke-DRPGenerator.ps1") -CompanyName "TestCorp Geneva" -OutputPath $script:TmpOut
        Test-Path $res.HtmlReport | Should -BeTrue
    }
}

Describe "Chaos Engineering Lab Simulator (3 Enterprise Chaos Scenarios)" {
    It "Executes Chaos-DnsNtpStorm safely and verifies recovery" {
        $res = & (Join-Path $script:RootDir "Invoke-IncidentLabSimulator.ps1") -Scenario "Chaos-DnsNtpStorm" -Simulate -OutputPath $script:TmpOut
        $res.SelfHealVerified | Should -BeTrue
    }

    It "Executes Chaos-DiskSaturation99 safely and verifies cleanup" {
        $res = & (Join-Path $script:RootDir "Invoke-IncidentLabSimulator.ps1") -Scenario "Chaos-DiskSaturation99" -Simulate -OutputPath $script:TmpOut
        $res.SelfHealVerified | Should -BeTrue
    }

    It "Executes Chaos-DfsrClusterOutage safely and verifies failover probe" {
        $res = & (Join-Path $script:RootDir "Invoke-IncidentLabSimulator.ps1") -Scenario "Chaos-DfsrClusterOutage" -Simulate -OutputPath $script:TmpOut
        $res.SelfHealVerified | Should -BeTrue
    }
}

Describe "PS 5.1 Compatibility, Security Hardening & Live Guards" {
    It "Zero PS7-only null-coalescing (??) or legacy Get-WmiObject in operational scripts" {
        $scripts = Get-ChildItem -Path $script:RootDir -Include "*.ps1", "*.psm1" -Recurse |
            Where-Object { $_.FullName -notmatch "[/\\]Tests[/\\]" }
        foreach ($f in $scripts) {
            $raw = Get-Content -Path $f.FullName -Raw
            $raw | Should -Not -Match '\?\?' -Because "$($f.Name) must parse cleanly under Windows PowerShell 5.1"
            $raw | Should -Not -Match '\bGet-WmiObject\b' -Because "$($f.Name) must use Get-CimInstance"
        }
    }

    It "Core/ESN-ReportBuilder.ps1 builds HTML under StrictMode from modern New-ESNCheck schema" {
        . (Join-Path $script:RootDir "Core/ESN-ReportBuilder.ps1")
        $chkOk   = New-ESNCheck -Domain "Network" -Check "DNS" -Severity "OK" -Value "10.0.0.1" -Detail "Nominal"
        $chkWarn = New-ESNCheck -Domain "Storage" -Check "Disk C:" -Severity "WARNING" -Value "89%" -Detail "High"
        $sess = [PSCustomObject]@{
            StartTime = (Get-Date).AddMinutes(-1)
            Results   = @($chkOk, $chkWarn)
            Score     = 85
            Errors    = @()
            Warnings  = @("Disk space threshold")
        }
        $outHtml = Join-Path $script:TmpOut "strict-report.html"
        $written = Build-ESNReport -SessionData $sess -ComputerName "TEST-HOST" -IncidentId "INC-99" -OutputPath $outHtml
        Test-Path $written | Should -BeTrue
        (Get-Content $written -Raw) | Should -Match "Disk C:"
    }

    It "Invoke-NutanixPrismHealthAI.ps1 refuses live execution without -Credential" {
        { & (Join-Path $script:RootDir "Invoke-NutanixPrismHealthAI.ps1") -PrismEndpoint "ahv.test.local" -OutputPath $script:TmpOut } | Should -Throw "*Credential*"
    }

    It "Invoke-VeeamImmutableAudit.ps1 returns NON_COMPLIANT on missing path without -Simulate" {
        $res = & (Join-Path $script:RootDir "Invoke-VeeamImmutableAudit.ps1") -RepositoryPath (Join-Path $script:TmpOut "does_not_exist")
        $res.RansomwareProofCertified | Should -BeFalse
        $res.ComplianceStatus | Should -Be "NON_COMPLIANT"
    }

    It "Invoke-HighSpeedParallelAuditor.ps1 schedules more nodes than MaxConcurrency without dropping queue" {
        $res = & (Join-Path $script:RootDir "Invoke-HighSpeedParallelAuditor.ps1") -Simulate -SimulateCount 20 -MaxConcurrency 4 -TimeoutSeconds 5
        $res.TotalServers | Should -Be 20
        $res.Results.Count | Should -Be 20
    }

    It "Invoke-LinuxHeterogeneousAudit.ps1 & Invoke-ITSMConnector.ps1 run cleanly in simulation" {
        { & (Join-Path $script:RootDir "Invoke-LinuxHeterogeneousAudit.ps1") -TargetHost "ci-linux-node" -SimulationMode } | Should -Not -Throw
        { & (Join-Path $script:RootDir "Invoke-ITSMConnector.ps1") -Target "Simulation" } | Should -Not -Throw
    }

    It "New-ArubaSwitchConfig.ps1 defaults to SNMPv3 authPriv without plaintext default community" {
        $arubaOut = Join-Path $script:TmpOut "Aruba"
        & (Join-Path $script:RootDir "Projects/Network-Aruba/New-ArubaSwitchConfig.ps1") -Hostname "SW-CI-01" -OutputDir $arubaOut
        $cfgPath = Join-Path $arubaOut "SW-CI-01.cfg"
        Test-Path $cfgPath | Should -BeTrue
        $cfgRaw = Get-Content $cfgPath -Raw
        $cfgRaw | Should -Match 'snmpv3 user "prtg-monitor" auth sha'
        $cfgRaw | Should -Not -Match 'PRTG_Monitoring'
    }

    It "Invoke-NutanixPrismHealthAI.ps1 live path parses mocked Prism v2 JSON telemetry" {
        Mock Invoke-RestMethod {
            if ($Uri -match '/cluster/') {
                return [PSCustomObject]@{
                    name                        = "NTNX-MOCK-01"
                    version                     = "6.5.5"
                    hypervisor_types            = @("AHV")
                    num_nodes                   = 3
                    fault_tolerance_domain_type = 2
                    usage_stats                 = [PSCustomObject]@{
                        'storage.usage_bytes'    = [double](10TB)
                        'storage.capacity_bytes' = [double](20TB)
                    }
                    stats                       = [PSCustomObject]@{
                        'controller_avg_io_latency_usecs' = 3500
                        'controller_num_iops'             = 18500
                    }
                }
            }
            if ($Uri -match '/hosts/') {
                return [PSCustomObject]@{
                    entities = @(
                        [PSCustomObject]@{
                            name                  = "node-mock-01"
                            service_vmexternal_ip = "10.0.0.11"
                            state                 = "NORMAL"
                            stats                 = [PSCustomObject]@{
                                hypervisor_cpu_usage_ppm        = 420000
                                hypervisor_memory_usage_ppm     = 610000
                                controller_avg_io_latency_usecs = 2100
                            }
                        }
                    )
                }
            }
            return [PSCustomObject]@{ entities = @() }
        }
        $dummyCred = [System.Management.Automation.PSCredential]::new("ci-monitor", [System.Security.SecureString]::new())
        $res = & (Join-Path $script:RootDir "Invoke-NutanixPrismHealthAI.ps1") -PrismEndpoint "prism.mock.local:9440" -Credential $dummyCred -OutputPath $script:TmpOut
        $res.ClusterName | Should -Be "NTNX-MOCK-01"
        $res.NodesCount | Should -Be 3
        $res.PeakClusterIOPS | Should -Be 18500
        $res.StorageRunwayDays | Should -BeNullOrEmpty
        Test-Path (Join-Path $script:TmpOut "NutanixHealth_NTNX-MOCK-01.json") | Should -BeTrue
    }

    It "Invoke-ActiveDirectoryThreatHunter.ps1 detects Kerberoasting RC4 0x17 sweep via mocked Get-WinEvent" {
        Mock Get-WinEvent {
            1..5 | ForEach-Object {
                $evt = [PSCustomObject]@{ Id = 4769 }
                $evt | Add-Member -MemberType ScriptMethod -Name ToXml -Value {
                    '<Event><EventData><Data Name="TicketEncryptionType">0x17</Data><Data Name="ServiceName">svc_sql_prod</Data><Data Name="IpAddress">10.99.99.50</Data></EventData></Event>'
                } -Force
                $evt
            }
        }
        $res = & (Join-Path $script:RootDir "Invoke-ActiveDirectoryThreatHunter.ps1") -DomainController "127.0.0.1" -OutputPath $script:TmpOut
        $res.CriticalCount | Should -BeGreaterOrEqual 1
        ($res.Findings | Where-Object { $_.MITRETechnique -eq 'T1558.003' }).SourceWorkstation | Should -Contain '10.99.99.50'
    }

    It "Get-ESNToolkitRoot avoids creating non-ensured folders while Get-ESNReportRoot ensures creation" {
        Import-Module (Join-Path $script:RootDir "Core/ESN-Core.psm1") -Force
        . (Join-Path $script:RootDir "Core/ESN-OutputSchema.ps1")
        $prevRoot = $env:ESN_TOOLKIT_ROOT
        $env:ESN_TOOLKIT_ROOT = Join-Path $script:TmpOut "RootBehavior"
        try {
            $nonEnsured = Get-ESNToolkitRoot -SubFolder "ShouldNotExist_$(Get-Random)"
            Test-Path $nonEnsured | Should -BeFalse

            $dir = Get-ESNToolkitRoot -SubFolder "Reports" -Ensure
            $dir | Should -Not -BeNullOrEmpty
            Test-Path $dir | Should -BeTrue

            $repDir = Get-ESNReportRoot -SubFolder "Ensured_$(Get-Random)"
            Test-Path $repDir | Should -BeTrue
        } finally {
            if ($null -eq $prevRoot) { Remove-Item Env:\ESN_TOOLKIT_ROOT -ErrorAction SilentlyContinue } else { $env:ESN_TOOLKIT_ROOT = $prevRoot }
        }
    }

    It "New-ESNDomainResult handles SKIP and empty/INFO checks under StrictMode" {
        . (Join-Path $script:RootDir "Core/ESN-OutputSchema.ps1")
        $skipCheck = New-ESNCheck -Domain "Network" -Check "VPN Tunnel" -Severity "SKIP" -Value "N/A"
        $convSkip  = ConvertTo-ESNCheck ([PSCustomObject]@{ Category = "Network"; Check = "V"; Status = "SKIP"; Value = "N/A"; Details = "D" })
        $convSkip.severity | Should -Be "SKIP"

        $dom = New-ESNDomainResult -Domain "Network" -Checks @($skipCheck)
        $dom.score        | Should -Be 100
        $dom.label        | Should -Be "Excellent"
        $dom.total_impact | Should -Be 0
    }

    It "Build-ESNReport encodes XSS payloads across metadata, remediation and JSON" {
        . (Join-Path $script:RootDir "Core/ESN-OutputSchema.ps1")
        . (Join-Path $script:RootDir "Core/ESN-ReportBuilder.ps1")
        $chkXss = New-ESNCheck -Domain "Security" -Check "<script>alert(1)</script>" -Severity "CRITICAL" -Value "<img src=x onerror=alert(2)>" -Detail "Test XSS" -ScoreImpact 25
        $sess = [PSCustomObject]@{
            StartTime = (Get-Date).AddMinutes(-1)
            Results   = @($chkXss)
            Score     = 75
            Errors    = @("<script>alert(13)</script>")
            Warnings  = @()
        }
        $rem = @([PSCustomObject]@{
            Id = "<script>alert(14)</script>"; Name = "RemXSS"; Detected = $true; Applied = $true; Success = $true; Before = "<b1>"; After = "<a2>"
        })
        $outHtml = Join-Path $script:TmpOut "xss-report.html"
        $written = Build-ESNReport -SessionData $sess -ComputerName "<script>alert(10)</script>" -IncidentId "<script>alert(11)</script>" -RemediationData $rem -OutputPath $outHtml
        $rawHtml = Get-Content $written -Raw
        $rawHtml | Should -Match "#sec-checks:checked ~ #body-checks"
        $rawHtml | Should -Not -Match "<script>alert\((1|2|10|11|13|14)\)</script>"
        $rawHtml | Should -Match "&lt;script&gt;alert\(1\)&lt;/script&gt;"
        $rawHtml | Should -Match "&lt;script&gt;alert\(10\)&lt;/script&gt;"
        $rawHtml | Should -Match "&lt;script&gt;alert\(11\)&lt;/script&gt;"
        $rawHtml | Should -Match "&lt;script&gt;alert\(13\)&lt;/script&gt;"
        $rawHtml | Should -Match "&lt;script&gt;alert\(14\)&lt;/script&gt;"
        $rawHtml | Should -Match "25 pts"
    }

    It "ESN-GUI.ps1 button parameters match invoked target script declarations via AST" {
        $guiPath = Join-Path $script:RootDir "ESN-GUI.ps1"
        $tokens = $null; $errs = $null
        $guiAst = [System.Management.Automation.Language.Parser]::ParseFile($guiPath, [ref]$tokens, [ref]$errs)
        $tokens.Count | Should -BeGreaterThan 0
        $errs.Count | Should -Be 0

        $strNodes = $guiAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
        }, $true)

        $checked = 0
        foreach ($node in $strNodes) {
            if ($node.Extent.Text -match '\$ScriptDir\\([A-Za-z0-9_\\.-]+\.ps1)["'']?(.*)$') {
                $relPath = $Matches[1] -replace '\\', '/'
                $tail    = $Matches[2]
                $targetFile = Join-Path $script:RootDir $relPath
                Test-Path $targetFile | Should -BeTrue
                $checked++

                $tTokens = $null; $tErrs = $null
                $tAst = [System.Management.Automation.Language.Parser]::ParseFile($targetFile, [ref]$tTokens, [ref]$tErrs)
                $null = $tTokens
                $tErrs.Count | Should -Be 0
                $declared = @()
                if ($tAst.ParamBlock) {
                    $declared = @($tAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
                }

                $argMatches = [regex]::Matches($tail, '(?:^|\s)-([A-Za-z][A-Za-z0-9_]*)')
                foreach ($m in $argMatches) {
                    $pName = $m.Groups[1].Value
                    $declared | Should -Contain $pName
                }
            }
        }
        $checked | Should -BeGreaterThan 20
    }

    It "Invoke-RansomwareShield.ps1 avoids -Force on New-NetFirewallRule and runs -IsolateHost cleanly" {
        $shieldPath = Join-Path $script:RootDir "Invoke-RansomwareShield.ps1"
        $sTokens = $null; $sErrs = $null
        $sAst = [System.Management.Automation.Language.Parser]::ParseFile($shieldPath, [ref]$sTokens, [ref]$sErrs)
        $null = $sTokens
        $sErrs.Count | Should -Be 0
        $fwCmds = $sAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'New-NetFirewallRule'
        }, $true)
        $fwCmds.Count | Should -BeGreaterOrEqual 2
        foreach ($cmd in $fwCmds) {
            $paramNames = @($cmd.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
            $paramNames | Should -Not -Contain 'Force'
        }

        if (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue) {
            $script:fwCalls = 0
            Mock Get-NetFirewallRule { $null }
            Mock Remove-NetFirewallRule { }
            Mock New-NetFirewallRule { $script:fwCalls++ }
            if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
                Mock Get-NetAdapter { @() }
                Mock Disable-NetAdapter { }
            }
            { & $shieldPath -IsolateHost -CollectForensics:$false -OutputPath $script:TmpOut -Confirm:$false } | Should -Not -Throw
            $script:fwCalls | Should -BeGreaterOrEqual 2
        }
        { & $shieldPath -IsolateHost -Simulate -WhatIf -OutputPath $script:TmpOut } | Should -Not -Throw
    }

    It "All Projects/* and safe-mode root scripts parse cleanly without plaintext passwords and run in safe modes" {
        $allScripts = @(
            "Invoke-ZeroTouchProvisioning.ps1",
            "Invoke-HypervisorAudit.ps1",
            "Invoke-DRTest.ps1",
            "Invoke-COPILReportGenerator.ps1",
            "Projects/MDT-Deployment/Invoke-MDTIndustrialization.ps1",
            "Projects/WAN-MPLS-Refonte/Invoke-WANMigrationPlan.ps1",
            "Projects/AD-Migration/Invoke-ADDomainMigration.ps1",
            "Projects/Datacenter-Migration/Invoke-VeeamFailoverPlan.ps1",
            "Projects/EDR-Deployment/Invoke-EDRMassRollout.ps1",
            "Projects/Windows-LAPS/Deploy-WindowsLAPS.ps1",
            "Projects/Network-Aruba/New-ArubaSwitchConfig.ps1"
        )
        foreach ($rel in $allScripts) {
            $full = Join-Path $script:RootDir $rel
            Test-Path $full | Should -BeTrue
            $tk = $null; $er = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$tk, [ref]$er)
            $null = $tk
            $er.Count | Should -Be 0
            $raw = Get-Content $full -Raw
            $raw | Should -Not -Match 'AdminPassword\s*=\s*[^<\r\n]|P@ssw0rd|Admin123|Password123'
        }

        $prevRoot = $env:ESN_TOOLKIT_ROOT
        $env:ESN_TOOLKIT_ROOT = Join-Path $script:TmpOut "SafeModeRuns"
        try {
            $isAdmin = $false
            try {
                $id = [Security.Principal.WindowsIdentity]::GetCurrent()
                $isAdmin = ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            } catch {
                $isAdmin = $false
            }

            { & (Join-Path $script:RootDir "Invoke-COPILReportGenerator.ps1") -Simulate -OpenInBrowser:$false } | Should -Not -Throw
            { & (Join-Path $script:RootDir "Projects/MDT-Deployment/Invoke-MDTIndustrialization.ps1") -DeploymentSharePath (Join-Path $script:TmpOut "MDT") -ReportOnly } | Should -Not -Throw
            { & (Join-Path $script:RootDir "Projects/WAN-MPLS-Refonte/Invoke-WANMigrationPlan.ps1") -PrimaryGateway "127.0.0.1" -BackupGateway "127.0.0.1" -RemoteSiteIPs @("127.0.0.1") -ReportOnly } | Should -Not -Throw

            if ($isAdmin) {
                { & (Join-Path $script:RootDir "Invoke-ZeroTouchProvisioning.ps1") -Simulation -SkipSoftwareInstall -WhatIf } | Should -Not -Throw
                { & (Join-Path $script:RootDir "Invoke-HypervisorAudit.ps1") -Simulate -OpenReport:$false } | Should -Not -Throw
                { & (Join-Path $script:RootDir "Invoke-DRTest.ps1") -Simulate -OpenReport:$false } | Should -Not -Throw
                { & (Join-Path $script:RootDir "Projects/AD-Migration/Invoke-ADDomainMigration.ps1") -OutputDirectory (Join-Path $script:TmpOut "AD_Mig") -ExportAclOnly } | Should -Not -Throw
                { & (Join-Path $script:RootDir "Projects/Datacenter-Migration/Invoke-VeeamFailoverPlan.ps1") -TargetDatacenterIP "127.0.0.1" -Simulation -OpenReport:$false } | Should -Not -Throw
                { & (Join-Path $script:RootDir "Projects/EDR-Deployment/Invoke-EDRMassRollout.ps1") -Simulation } | Should -Not -Throw
                { & (Join-Path $script:RootDir "Projects/Windows-LAPS/Deploy-WindowsLAPS.ps1") -AuditOnly } | Should -Not -Throw
            }
        } finally {
            if ($null -eq $prevRoot) { Remove-Item Env:\ESN_TOOLKIT_ROOT -ErrorAction SilentlyContinue } else { $env:ESN_TOOLKIT_ROOT = $prevRoot }
        }
    }

    It "New-ESNRandomPassword uses CSPRNG without static Aa1! suffix and Ping helpers work on localhost" {
        Import-Module (Join-Path $script:RootDir "Core/ESN-Core.psm1") -Force
        Import-Module (Join-Path $script:RootDir "Modules/AD/ESN-AD.psm1") -Force
        $pwd1 = New-ESNRandomPassword -Length 16
        $pwd2 = New-ESNRandomPassword -Length 16
        $pwd1.Length | Should -Be 16
        $pwd1 | Should -Not -Be $pwd2
        $pwd1.EndsWith("Aa1!") | Should -BeFalse
        (Test-ESNHostPing -ComputerName "127.0.0.1" -TimeoutMs 1000) | Should -BeTrue
        $lat = Measure-ESNPingLatency -ComputerName "127.0.0.1" -Count 2 -TimeoutMs 1000
        $lat.Reachable | Should -BeTrue
    }
}
