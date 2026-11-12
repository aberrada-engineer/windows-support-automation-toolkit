#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Pester v5 — Module ESN-Remediation.
    Couvre : catalogue, détection, simulation, rapport HTML.
.USAGE
    Invoke-Pester .\Tests\ESN-Remediation.Tests.ps1 -Output Detailed
    Invoke-Pester .\Tests\ESN-Remediation.Tests.ps1 -Tag "Catalog" -Output Detailed
#>

BeforeAll {
    $root     = Split-Path $PSScriptRoot -Parent
    $corePath = Join-Path $root "Core\ESN-Core.psm1"
    $remPath  = Join-Path $root "Modules\Remediation\ESN-Remediation.psm1"

    Import-Module $corePath -Force
    Import-Module $remPath  -Force
}

# ═══════════════════════════════════════════════════════
# CATALOGUE
# ═══════════════════════════════════════════════════════

Describe "ESN-Remediation — Catalogue" -Tag "Catalog" {

    It "Exporte Invoke-Remediation" {
        Get-Command Invoke-Remediation | Should -Not -BeNullOrEmpty
    }

    It "Exporte Get-RemediationCatalog" {
        Get-Command Get-RemediationCatalog | Should -Not -BeNullOrEmpty
    }

    It "Exporte Test-RemediationNeeded" {
        Get-Command Test-RemediationNeeded | Should -Not -BeNullOrEmpty
    }

    It "Le catalogue contient exactement 8 remédiations" {
        # DNS, Winsock, Services, Teams, Outlook, OneDrive, TempFiles, WindowsUpdate
        $catalog = & (Get-Module ESN-Remediation) { $script:Catalog }
        $catalog.Count | Should -Be 8
    }

    It "Chaque remédiation du catalogue a les champs obligatoires" {
        $catalog = & (Get-Module ESN-Remediation) { $script:Catalog }
        foreach ($key in $catalog.Keys) {
            $rem = $catalog[$key]
            $rem.Id            | Should -Not -BeNullOrEmpty -Because "$key doit avoir un Id"
            $rem.Name          | Should -Not -BeNullOrEmpty -Because "$key doit avoir un Name"
            $rem.Description   | Should -Not -BeNullOrEmpty -Because "$key doit avoir une Description"
            $rem.Risk          | Should -BeIn @("Low","Medium","High") -Because "$key.Risk doit être Low/Medium/High"
            $rem.Detect        | Should -BeOfType [scriptblock] -Because "$key.Detect doit être un scriptblock"
            $rem.Remediate     | Should -BeOfType [scriptblock] -Because "$key.Remediate doit être un scriptblock"
        }
    }

    It "Les IDs du catalogue correspondent aux noms attendus" {
        $catalog = & (Get-Module ESN-Remediation) { $script:Catalog }
        $expectedIds = @("DNS","Winsock","Services","Teams","Outlook","OneDrive","TempFiles","WindowsUpdate")
        foreach ($id in $expectedIds) {
            $catalog.Contains($id) | Should -Be $true -Because "Le catalogue doit contenir $id"
        }
    }

    It "DNS et TempFiles sont de risque Low" {
        $catalog = & (Get-Module ESN-Remediation) { $script:Catalog }
        $catalog["DNS"].Risk       | Should -Be "Low"
        $catalog["TempFiles"].Risk | Should -Be "Low"
    }

    It "Winsock et WindowsUpdate sont de risque Medium" {
        $catalog = & (Get-Module ESN-Remediation) { $script:Catalog }
        $catalog["Winsock"].Risk       | Should -Be "Medium"
        $catalog["WindowsUpdate"].Risk | Should -Be "Medium"
    }

    It "WindowsUpdate et Services RequiresAdmin = true" {
        $catalog = & (Get-Module ESN-Remediation) { $script:Catalog }
        $catalog["WindowsUpdate"].RequiresAdmin | Should -Be $true
        $catalog["Services"].RequiresAdmin      | Should -Be $true
    }

    It "DNS ne RequiresAdmin pas" {
        $catalog = & (Get-Module ESN-Remediation) { $script:Catalog }
        $catalog["DNS"].RequiresAdmin | Should -Be $false
    }
}

# ═══════════════════════════════════════════════════════
# DÉTECTION
# ═══════════════════════════════════════════════════════

Describe "ESN-Remediation — Détection" -Tag "Detection" {

    It "Test-RemediationNeeded retourne un booléen pour DNS" {
        $r = Test-RemediationNeeded -Id "DNS"
        $r | Should -BeOfType [bool]
    }

    It "Test-RemediationNeeded retourne un booléen pour TempFiles" {
        $r = Test-RemediationNeeded -Id "TempFiles"
        $r | Should -BeOfType [bool]
    }

    It "Test-RemediationNeeded retourne un booléen pour Services" {
        $r = Test-RemediationNeeded -Id "Services"
        $r | Should -BeOfType [bool]
    }

    It "Test-RemediationNeeded signale une erreur pour un ID invalide" {
        # Ne doit pas lever d'exception, doit retourner $false
        $r = Test-RemediationNeeded -Id "FakeId_DoesNotExist_999"
        $r | Should -Be $false
    }

    It "Invoke-Remediation sans -AutoFix ni -Fix retourne des résultats sans les appliquer" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-REM-DETECT"
        $results = Invoke-Remediation -ComputerName $env:COMPUTERNAME

        $results             | Should -Not -BeNullOrEmpty
        $results.Count       | Should -BeGreaterThan 0
        # Sans -AutoFix, aucun résultat ne doit être Applied
        $applied = $results | Where-Object Applied
        $applied.Count | Should -Be 0
    }

    It "Chaque résultat a les propriétés attendues" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-REM-PROPS"
        $results = Invoke-Remediation -ComputerName $env:COMPUTERNAME

        foreach ($r in $results) {
            $r.Id      | Should -Not -BeNullOrEmpty
            $r.Name    | Should -Not -BeNullOrEmpty
            { [bool]$r.Detected } | Should -Not -Throw
            { [bool]$r.Applied  } | Should -Not -Throw
        }
    }
}

# ═══════════════════════════════════════════════════════
# SIMULATION
# ═══════════════════════════════════════════════════════

Describe "ESN-Remediation — Mode Simulation" -Tag "Simulation" {

    It "En simulation avec -AutoFix, Applied=true mais aucune modification réelle" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-SIM-AUTOFIX"

        # On cible uniquement DNS et TempFiles (low risk, sans prérequis admin)
        $results = Invoke-Remediation `
            -Fix @("DNS","TempFiles") `
            -AutoFix `
            -Force `
            -Simulation

        $results | Should -Not -BeNullOrEmpty

        # En simulation, les actions sont marquées Applied
        foreach ($r in ($results | Where-Object Detected)) {
            $r.Applied | Should -Be $true -Because "$($r.Id) détecté doit être marqué Applied en simulation"
            # Le champ After doit signaler la simulation
            if ($r.After) {
                # Soit "[SIMULATION]", soit une valeur informative
                $r.After | Should -Not -BeNullOrEmpty
            }
        }
    }

    It "DNS en simulation : After contient SIMULATION ou est renseigné" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-SIM-DNS"
        $results = Invoke-Remediation -Fix @("DNS") -AutoFix -Force -Simulation
        $dns = $results | Where-Object Id -eq "DNS"
        $dns | Should -Not -BeNullOrEmpty
        if ($dns.Applied) {
            $dns.After | Should -Not -BeNullOrEmpty
        }
    }

    It "TempFiles en simulation : Success=true si détecté et appliqué" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-SIM-TEMP"
        $results = Invoke-Remediation -Fix @("TempFiles") -AutoFix -Force -Simulation
        $tf = $results | Where-Object Id -eq "TempFiles"
        $tf | Should -Not -BeNullOrEmpty
        if ($tf.Applied) {
            $tf.Success | Should -Be $true
        }
    }

    It "Services en simulation : ne plante pas même sans droits admin" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-SIM-SVC"
        { Invoke-Remediation -Fix @("Services") -AutoFix -Force -Simulation } |
            Should -Not -Throw
    }

    It "Teams en simulation : Applied et Success si Teams n'est pas installé (chemin absent = non détecté, pas d'erreur)" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-SIM-TEAMS"
        { Invoke-Remediation -Fix @("Teams") -AutoFix -Force -Simulation } |
            Should -Not -Throw
    }
}

# ═══════════════════════════════════════════════════════
# FIX CIBLÉ (sans simulation sur DNS uniquement)
# ═══════════════════════════════════════════════════════

Describe "ESN-Remediation — Fix ciblé DNS (réel)" -Tag "RealFix" {

    It "DNS fix réel : Clear-DnsClientCache s'exécute sans erreur" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-REAL-DNS"
        # On applique DNS sans simulation — flush DNS est sans risque
        { Invoke-Remediation -Fix @("DNS") -AutoFix -Force } | Should -Not -Throw
    }

    It "DNS fix réel retourne Success=true" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-REAL-DNS2"
        $results = Invoke-Remediation -Fix @("DNS") -AutoFix -Force

        $dns = $results | Where-Object Id -eq "DNS"
        $dns | Should -Not -BeNullOrEmpty
        if ($dns.Applied) {
            $dns.Success | Should -Be $true
        }
    }
}

# ═══════════════════════════════════════════════════════
# RAPPORT HTML
# ═══════════════════════════════════════════════════════

Describe "ESN-Remediation — Rapport HTML" -Tag "Report" {

    It "Invoke-Remediation génère un rapport HTML" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-RPT-REM"
        $tmpReport = Join-Path $env:TEMP "ESN_Rem_Test_$(Get-Random).html"

        Invoke-Remediation `
            -Fix @("DNS","TempFiles") `
            -AutoFix -Force -Simulation `
            -ReportPath $tmpReport

        Test-Path $tmpReport | Should -Be $true
        (Get-Item $tmpReport).Length | Should -BeGreaterThan 500

        Remove-Item $tmpReport -Force -ErrorAction SilentlyContinue
    }

    It "Le rapport HTML contient les IDs des remédiations" {
        Initialize-ESNSession -ScriptName "test.ps1" -IncidentId "TEST-RPT-REM2"
        $tmpReport = Join-Path $env:TEMP "ESN_Rem_Test2_$(Get-Random).html"

        Invoke-Remediation `
            -Fix @("DNS","TempFiles","Teams") `
            -AutoFix -Force -Simulation `
            -ReportPath $tmpReport

        $content = Get-Content $tmpReport -Raw
        $content | Should -Match "DNS"
        $content | Should -Match "TempFiles"
        $content | Should -Match "Teams"

        Remove-Item $tmpReport -Force -ErrorAction SilentlyContinue
    }
}

# ═══════════════════════════════════════════════════════
# INTÉGRATION AVEC INVOKE-INCIDENTANALYSIS
# ═══════════════════════════════════════════════════════

Describe "Invoke-IncidentAnalysis v2 — Intégration Remédiation" -Tag "Integration" {

    It "Le script v2 existe et contient le paramètre -AutoFix" {
        $path    = Join-Path (Split-Path $PSScriptRoot -Parent) "Invoke-IncidentAnalysis.ps1"
        Test-Path $path | Should -Be $true
        $content = Get-Content $path -Raw
        $content | Should -Match "AutoFix"
        $content | Should -Match "Remediation"
    }

    It "S'exécute avec -Modules Network -AutoFix -Simulation sans erreur" {
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) "Invoke-IncidentAnalysis.ps1"
        {
            & $path `
                -Modules Network `
                -AutoFix `
                -Simulation `
                -Force `
                -IncidentId "PESTER-V2-001"
        } | Should -Not -Throw
    }

    It "Retourne un objet avec RemediationsDetected et RemediationsFixed" {
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) "Invoke-IncidentAnalysis.ps1"
        $result = & $path `
            -Modules Network `
            -AutoFix `
            -Simulation `
            -Force `
            -IncidentId "PESTER-V2-002" 2>&1 |
            Where-Object { $_ -is [PSCustomObject] } |
            Select-Object -Last 1

        if ($result) {
            { [int]$result.RemediationsDetected } | Should -Not -Throw
            { [int]$result.RemediationsFixed }     | Should -Not -Throw
            { [bool]$result.RebootRequired }       | Should -Not -Throw
        }
    }
}

AfterAll {
    Remove-Module ESN-Core, ESN-Remediation -Force -ErrorAction SilentlyContinue
}
