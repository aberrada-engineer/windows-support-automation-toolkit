# Pester Tests - Enterprise Modules & Scripts Integrity Validation
# Requires Pester v5+ (BeforeDiscovery / -ForEach)

BeforeDiscovery {
    $script:RootFolder = Split-Path $PSScriptRoot -Parent
    $script:AllScripts = Get-ChildItem -Path $script:RootFolder -Include "*.ps1", "*.psm1" -Recurse | Where-Object { $_.FullName -notmatch "[/\\]Tests[/\\]" }
}

Describe "ESN-Toolkit Enterprise Architecture & Syntax Integrity" {
    BeforeAll {
        $script:RootFolder = Split-Path $PSScriptRoot -Parent
        $script:AllScripts = Get-ChildItem -Path $script:RootFolder -Include "*.ps1", "*.psm1" -Recurse | Where-Object { $_.FullName -notmatch "[/\\]Tests[/\\]" }
    }

    It "Should contain at least 25 operational PowerShell scripts & modules" {
        $script:AllScripts.Count | Should -BeGreaterThan 25
    }

    Context "Script Integrity: <Name>" -ForEach @(
        Get-ChildItem -Path (Split-Path $PSScriptRoot -Parent) -Include "*.ps1", "*.psm1" -Recurse |
            Where-Object { $_.FullName -notmatch "[/\\]Tests[/\\]" } |
            ForEach-Object { @{ Name = $_.Name; FullName = $_.FullName; Length = $_.Length } }
    ) {
        It "Should be non-empty and readable" {
            $Length | Should -BeGreaterThan 100
        }

        It "Should have valid PowerShell AST syntax without parse errors" {
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$null, [ref]$parseErrors)
            $parseErrors.Count | Should -Be 0
        }
    }
}
