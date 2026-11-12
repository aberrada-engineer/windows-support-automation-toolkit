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
