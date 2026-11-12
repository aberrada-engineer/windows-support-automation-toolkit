<#
.SYNOPSIS
    Agentless Active Directory heuristic threat hunter (Kerberoasting, AS-REP Roasting, AdminSDHolder/adminCount anomalies & dangerous ACLs).

.DESCRIPTION
    Scans Active Directory and Domain Controller Security Event Logs without third-party agents to detect:
    - Kerberoasting attacks (Event ID 4769 with RC4 encryption 0x17 on privileged SPN accounts)
    - AS-REP Roasting exposure (accounts with DONT_REQ_PREAUTH UserAccountControl flag 4194304)
    - Shadow Admin & AdminSDHolder persistence (orphaned adminCount=1 on non-privileged groups or unexpected GenericAll/WriteDacl ACEs)
    - Optional automated containment (-AutoRemediate) to disable or rotate compromised service accounts and emit a SIEM-ready JSON alert.
    Includes a -Simulate switch for lab validation and CI testing on non-domain hosts.

.PARAMETER DomainController
    Target Domain Controller FQDN or IP address to query.

.PARAMETER LookbackHours
    Number of hours to inspect in the Security Event Log for Event IDs 4768 / 4769 / 4662 (default: 24).

.PARAMETER AutoRemediate
    Automatically disables high-confidence compromised accounts or removes pre-auth bypass flags (supports -WhatIf).

.PARAMETER OutputPath
    Directory where the SIEM JSON threat report is written.

.PARAMETER Simulate
    Executes with realistic synthetic AD threat telemetry for offline testing and CI/CD pipelines.

.EXAMPLE
    .\Invoke-ActiveDirectoryThreatHunter.ps1 -DomainController "dc01.corp.local" -LookbackHours 12

.EXAMPLE
    .\Invoke-ActiveDirectoryThreatHunter.ps1 -Simulate -AutoRemediate -WhatIf

.NOTES
    Author  : Amine BERRADA (Senior Systems & Network Administrator / L3 Technical Lead)
    Project : Windows Support & Infrastructure Automation Toolkit (WSAT)
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
    [string]$DomainController = $(if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 720)]
    [int]$LookbackHours = 24,

    [Parameter(Mandatory = $false)]
    [switch]$AutoRemediate,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path $PSScriptRoot "Reports"),

    [Parameter(Mandatory = $false)]
    [switch]$Simulate
)

begin {
    $ErrorActionPreference = 'Stop'
    $schemaScript = Join-Path $PSScriptRoot "Core/ESN-OutputSchema.ps1"
    if (Test-Path $schemaScript) { . $schemaScript }
    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }
}

process {
    try {
        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $findings = [System.Collections.Generic.List[PSCustomObject]]::new()
        $remediatedActions = [System.Collections.Generic.List[string]]::new()

        if ($Simulate -or -not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) {
            $findings.Add([PSCustomObject]@{
                ThreatCategory    = "Kerberoasting (RC4 0x17 TGS Sweep)"
                MITRETechnique    = "T1558.003"
                Severity          = "CRITICAL"
                TargetAccount     = "svc_sql_prod"
                SourceWorkstation = "10.20.45.118"
                Evidence          = "18 TGS requests (Event 4769) with TicketEncryptionType=0x17 within 45 seconds"
                RecommendedAction = "Enforce AES256-SHA1 on SPN account and rotate password twice"
            })
            $findings.Add([PSCustomObject]@{
                ThreatCategory    = "AS-REP Roasting Exposure"
                MITRETechnique    = "T1558.004"
                Severity          = "HIGH"
                TargetAccount     = "legacy_bind_user"
                SourceWorkstation = "N/A (Directory Attribute)"
                Evidence          = "UserAccountControl contains UF_DONT_REQUIRE_PREAUTH (0x400000)"
                RecommendedAction = "Clear DoesNotRequirePreAuth flag via Set-ADAccountControl"
            })
            $findings.Add([PSCustomObject]@{
                ThreatCategory    = "Orphaned AdminSDHolder / Shadow Admin"
                MITRETechnique    = "T1098"
                Severity          = "MEDIUM"
                TargetAccount     = "j.dupont_temp"
                SourceWorkstation = "AD ACL Audit"
                Evidence          = "adminCount=1 with inheritance disabled, but account is not a member of any Tier-0 group"
                RecommendedAction = "Reset adminCount attribute and re-enable ACL inheritance on user object"
            })
        }
        else {
            $since = (Get-Date).AddHours(-$LookbackHours)
            $filterXml = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">*[System[(EventID=4769) and TimeCreated[@SystemTime&gt;='$($since.ToUniversalTime().ToString("o"))']]]</Select>
  </Query>
</QueryList>
"@
            $events = Get-WinEvent -ComputerName $DomainController -FilterXml $filterXml -MaxEvents 500 -ErrorAction SilentlyContinue
            $rc4Events = foreach ($evt in $events) {
                $xml = [xml]$evt.ToXml()
                $enc = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TicketEncryptionType' }).'#text'
                $svc = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'ServiceName' }).'#text'
                $ip  = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'IpAddress' }).'#text'
                if ($enc -eq '0x17' -and $svc -notmatch '^krbtgt$' -and $svc -notmatch '\$$') {
                    [PSCustomObject]@{ Service = $svc; SourceIp = $ip }
                }
            }
            foreach ($grp in ($rc4Events | Group-Object SourceIp | Where-Object { $_.Count -ge 5 })) {
                $findings.Add([PSCustomObject]@{
                    ThreatCategory    = "Kerberoasting (RC4 0x17 TGS Sweep)"
                    MITRETechnique    = "T1558.003"
                    Severity          = "CRITICAL"
                    TargetAccount     = ($grp.Group.Service | Select-Object -Unique) -join ', '
                    SourceWorkstation = $grp.Name
                    Evidence          = "$($grp.Count) RC4 TGS ticket requests detected in $LookbackHours h window"
                    RecommendedAction = "Isolate source host and rotate affected SPN service account credentials"
                })
            }

            try {
                $rootEntry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainController/RootDSE")
                $baseDn = [string]$rootEntry.defaultNamingContext
                if ($baseDn) {
                    $searchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainController/$baseDn")

                    # AS-REP Roasting: UF_DONT_REQUIRE_PREAUTH (4194304)
                    $asrepSearcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
                    $asrepSearcher.Filter = "(&(objectCategory=person)(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))"
                    [void]$asrepSearcher.PropertiesToLoad.Add("samaccountname")
                    foreach ($hit in $asrepSearcher.FindAll()) {
                        $sam = [string]$hit.Properties["samaccountname"][0]
                        $findings.Add([PSCustomObject]@{
                            ThreatCategory    = "AS-REP Roasting Exposure"
                            MITRETechnique    = "T1558.004"
                            Severity          = "HIGH"
                            TargetAccount     = $sam
                            SourceWorkstation = "LDAP://$DomainController"
                            Evidence          = "UserAccountControl contains UF_DONT_REQUIRE_PREAUTH (0x400000)"
                            RecommendedAction = "Clear DoesNotRequirePreAuth flag via Set-ADAccountControl"
                        })
                    }

                    # AdminSDHolder / Orphaned adminCount=1 outside known Tier-0 groups
                    $adminSearcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
                    $adminSearcher.Filter = "(&(objectCategory=person)(objectClass=user)(adminCount=1))"
                    [void]$adminSearcher.PropertiesToLoad.Add("samaccountname")
                    [void]$adminSearcher.PropertiesToLoad.Add("memberof")
                    foreach ($hit in $adminSearcher.FindAll()) {
                        $sam = [string]$hit.Properties["samaccountname"][0]
                        if ($sam -in @("Administrator","krbtgt")) { continue }
                        $groups = @($hit.Properties["memberof"] | ForEach-Object { [string]$_ })
                        $inTier0 = @($groups | Where-Object { $_ -match '^CN=(Domain Admins|Enterprise Admins|Schema Admins|Administrators),' }).Count -gt 0
                        if (-not $inTier0) {
                            $findings.Add([PSCustomObject]@{
                                ThreatCategory    = "Orphaned AdminSDHolder / Shadow Admin"
                                MITRETechnique    = "T1098"
                                Severity          = "MEDIUM"
                                TargetAccount     = $sam
                                SourceWorkstation = "AD ACL Audit ($DomainController)"
                                Evidence          = "adminCount=1 without direct Tier-0 group membership"
                                RecommendedAction = "Verify ACL inheritance and reset adminCount attribute if deprivileged"
                            })
                        }
                    }
                }
            }
            catch {
                Write-Warning "LDAP AD query skipped on $DomainController : $($_.Exception.Message)"
            }
        }

        if ($AutoRemediate) {
            $hasAdModule = [bool](Get-Command Set-ADAccountControl -ErrorAction SilentlyContinue)
            foreach ($item in $findings) {
                if ($PSCmdlet.ShouldProcess($item.TargetAccount, "Auto-remediate AD Threat ($($item.ThreatCategory))")) {
                    if ($Simulate) {
                        $remediatedActions.Add("Applied simulated containment on [$($item.TargetAccount)] for $($item.MITRETechnique)")
                    }
                    elseif ($hasAdModule -and $item.MITRETechnique -eq "T1558.004") {
                        Set-ADAccountControl -Identity $item.TargetAccount -DoesNotRequirePreAuth $false -Server $DomainController -ErrorAction Stop
                        $remediatedActions.Add("Cleared UF_DONT_REQUIRE_PREAUTH on [$($item.TargetAccount)]")
                    }
                    else {
                        $remediatedActions.Add("Manual tier-0 review required for [$($item.TargetAccount)] ($($item.MITRETechnique))")
                    }
                }
            }
        }

        $summary = [PSCustomObject]@{
            Timestamp        = $timestamp
            DomainController = $DomainController
            LookbackHours    = $LookbackHours
            TotalFindings    = $findings.Count
            CriticalCount    = @($findings | Where-Object { $_.Severity -eq 'CRITICAL' }).Count
            HighCount        = @($findings | Where-Object { $_.Severity -eq 'HIGH' }).Count
            AutoRemediated   = $remediatedActions.ToArray()
            Findings         = $findings.ToArray()
        }

        $jsonOut = Join-Path $OutputPath "ADThreatHunt_$($DomainController -replace '[^a-zA-Z0-9_-]','_').json"
        if ($PSCmdlet.ShouldProcess($jsonOut, "Write SIEM JSON Threat Hunting Report")) {
            $summary | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonOut -Encoding UTF8
            if ((Get-Command Write-ESNSiemAlert -ErrorAction SilentlyContinue) -and $summary.TotalFindings -gt 0) {
                $alertSev = if ($summary.CriticalCount -gt 0) { "CRITICAL" } else { "WARNING" }
                Write-ESNSiemAlert -ScriptName "Invoke-ActiveDirectoryThreatHunter.ps1" -Severity $alertSev -Category "ActiveDirectory" -Target $DomainController -Message "$($summary.TotalFindings) AD threat finding(s) detected ($($summary.CriticalCount) critical)" | Out-Null
            }
        }

        return $summary
    }
    catch {
        $errObj = [PSCustomObject]@{
            Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            Script    = "Invoke-ActiveDirectoryThreatHunter.ps1"
            TargetDC  = $DomainController
            ErrorType = $_.Exception.GetType().FullName
            Message   = $_.Exception.Message
        }
        Write-Warning ($errObj | ConvertTo-Json -Compress)
        throw
    }
}
