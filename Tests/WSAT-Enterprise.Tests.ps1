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

    It "Invoke-CopilDashboardGenerator.ps1 produces standalone HTML5 SVG dashboard" {
        $dashFile = Join-Path $script:TmpOut "copil-test.html"
        & (Join-Path $script:RootDir "Invoke-CopilDashboardGenerator.ps1") -OutputFile $dashFile | Out-Null
        Test-Path $dashFile | Should -BeTrue
        (Get-Content $dashFile -Raw) | Should -Match "<svg"
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
}
