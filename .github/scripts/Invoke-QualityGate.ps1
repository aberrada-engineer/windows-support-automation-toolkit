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
        $secRules = @('PSAvoidUsingConvertToSecureStringWithPlainText', 'PSAvoidUsingPlainTextForPassword', 'PSAvoidUsingUsernameAndPasswordParams')
        $allFindings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Severity @('Error', 'Warning') -ExcludeRule @('PSAvoidUsingWriteHost') | Where-Object { $_.ScriptPath -notmatch '[/\\]Tests[/\\]' })
        $blocking = @($allFindings | Where-Object { $_.Severity -eq 'Error' -or $_.RuleName -in $secRules })
        $advisory = @($allFindings | Where-Object { $_.Severity -eq 'Warning' -and $_.RuleName -notin $secRules })
        if ($advisory.Count -gt 0) {
            Write-Host "[INFO] $($advisory.Count) avertissement(s) stylistique(s) PSScriptAnalyzer (non bloquants)." -ForegroundColor Yellow
            foreach ($w in ($advisory | Select-Object -First 10)) {
                if ($env:GITHUB_ACTIONS -eq 'true') {
                    Write-Host "::warning file=$($w.ScriptPath),line=$($w.Line)::PSScriptAnalyzer [$($w.ScriptName):$($w.Line)] $($w.RuleName): $($w.Message)"
                }
            }
        }
        if ($blocking.Count -gt 0) {
            $blocking | Format-Table ScriptName, Line, Severity, RuleName, Message -AutoSize
            foreach ($f in ($blocking | Select-Object -First 15)) {
                Emit-GhaError "PSScriptAnalyzer [$($f.ScriptName):$($f.Line)] $($f.RuleName): $($f.Message)"
            }
            throw "PSScriptAnalyzer a detecte $($blocking.Count) erreur(s) bloquante(s)."
        }
        Write-Host "[OK] Zero erreur bloquante PSScriptAnalyzer (Errors + SecOps)." -ForegroundColor Green
    }

    if ($Stage -in @('All', 'Pester')) {
        Ensure-GalleryModule -Name 'Pester' -MinVersion '5.0.0'
        Import-Module Pester -MinimumVersion 5.0.0 -Force
        $res = Invoke-Pester -Path './Tests' -Output Detailed -PassThru
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
