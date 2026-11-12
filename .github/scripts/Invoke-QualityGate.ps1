param(
    [ValidateSet('All', 'AST', 'Analyzer', 'Pester')]
    [string]$Stage = 'All',
    [switch]$RunAnalyzer
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')

function Emit-GhaError([string]$Message) {
    $clean = ($Message -replace '\r?\n', ' | ').Trim()
    if ($clean.Length -gt 800) { $clean = $clean.Substring(0, 800) + '...' }
    Write-Host "::error::$clean"
}

function Ensure-GalleryModule([string]$Name, [string]$MinVersion = '') {
    $mods = Get-Module -ListAvailable -Name $Name
    $ok = if ($MinVersion) { $mods | Where-Object { $_.Version -ge [version]$MinVersion } } else { $mods }
    if ($ok) { return }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    $params = @{ Name = $Name; Scope = 'CurrentUser'; Force = $true; AllowClobber = $true; SkipPublisherCheck = $true; ErrorAction = 'Stop' }
    if ($MinVersion) { $params['MinimumVersion'] = $MinVersion }
    Install-Module @params
}

Push-Location $repoRoot
try {
    if ($Stage -in @('All', 'AST')) {
        Write-Host "=== Validation syntaxique AST ($($PSVersionTable.PSVersion)) ===" -ForegroundColor Cyan
        $scripts = Get-ChildItem -Path . -Include '*.ps1', '*.psm1' -Recurse | Where-Object { $_.FullName -notmatch '[/\\]Tests[/\\]' }
        $errorsCount = 0
        foreach ($s in $scripts) {
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$null, [ref]$parseErrors)
            foreach ($pe in $parseErrors) {
                Emit-GhaError "AST [$($s.Name):$($pe.Extent.StartLineNumber)] $($pe.Message)"
                $errorsCount++
            }
        }
        if ($errorsCount -gt 0) { throw "Echec AST : $errorsCount erreur(s) de syntaxe." }
        Write-Host "[OK] $($scripts.Count) scripts/modules valides sous $($PSVersionTable.PSVersion)." -ForegroundColor Green
    }

    if ($Stage -eq 'Analyzer' -or ($Stage -eq 'All' -and $RunAnalyzer)) {
        Ensure-GalleryModule -Name 'PSScriptAnalyzer'
        $findings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error | Where-Object { $_.ScriptPath -notmatch '[/\\]Tests[/\\]' })
        if ($findings.Count -gt 0) {
            $findings | Format-Table ScriptName, Line, RuleName, Message -AutoSize
            foreach ($f in ($findings | Select-Object -First 15)) {
                Emit-GhaError "PSScriptAnalyzer [$($f.ScriptName):$($f.Line)] $($f.RuleName): $($f.Message)"
            }
            throw "PSScriptAnalyzer a detecte $($findings.Count) erreur(s) critique(s)."
        }
        Write-Host "[OK] Zero erreur critique PSScriptAnalyzer." -ForegroundColor Green
    }

    if ($Stage -in @('All', 'Pester')) {
        Ensure-GalleryModule -Name 'Pester' -MinVersion '5.0.0'
        Import-Module Pester -MinimumVersion 5.0.0 -Force
        $res = Invoke-Pester -Path @('./Tests/ESN-EnterpriseModules.Tests.ps1', './Tests/WSAT-Enterprise.Tests.ps1') -Output Detailed -PassThru
        if ($res.FailedCount -gt 0) {
            foreach ($t in ($res.Failed | Select-Object -First 15)) {
                $errDetail = ($t.ErrorRecord | Out-String)
                Emit-GhaError "Pester FAIL [$($t.ExpandedPath)] $errDetail"
            }
            throw "Echec Pester : $($res.FailedCount) test(s) en erreur."
        }
        Write-Host "[OK] $($res.PassedCount) test(s) Pester reussis." -ForegroundColor Green
    }
}
catch {
    Emit-GhaError "QualityGate ($Stage) failed: $($_.Exception.Message)"
    exit 1
}
finally {
    Pop-Location
}
