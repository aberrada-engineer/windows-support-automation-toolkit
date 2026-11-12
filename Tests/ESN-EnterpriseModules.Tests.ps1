# Pester Tests - Enterprise Modules & Scripts Integrity Validation
# Validates PowerShell syntax, help documentation and structure across all modules

Describe "ESN-Toolkit Enterprise Architecture & Syntax Integrity" {
    $RootFolder = Split-Path $MyInvocation.MyCommand.Path -Parent | Split-Path -Parent
    $AllScripts = Get-ChildItem -Path $RootFolder -Filter "*.ps1" -Recurse | Where-Object { $_.FullName -notmatch "Tests" }

    It "Should contain at least 25 operational PowerShell scripts" {
        $AllScripts.Count | Should -BeGreaterThan 25
    }

    foreach ($script in $AllScripts) {
        Context "Script Integrity: $($script.Name)" {
            It "Should be non-empty and readable" {
                $script.Length | Should -BeGreaterThan 100
            }

            It "Should have valid PowerShell AST syntax without parse errors" {
                $parseErrors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$parseErrors)
                $parseErrors.Count | Should -Be 0
            }

            It "Should contain a .SYNOPSIS help comment block" {
                $content = Get-Content $script.FullName -Raw
                $content -match "\.SYNOPSIS" | Should -Be $true
            }
        }
    }
}
