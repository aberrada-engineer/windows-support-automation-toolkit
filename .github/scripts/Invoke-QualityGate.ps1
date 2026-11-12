param([switch]$RunAnalyzer)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Push-Location $repoRoot
try {
    Write-Host "=== Validation syntaxique AST ($($PSVersionTable.PSVersion)) ===" -ForegroundColor Cyan
    $scripts = Get-ChildItem -Path . -Include '*.ps1', '*.psm1' -Recurse | Where-Object { $_.FullName -notmatch '[/\\]Tests[/\\]' }
    $errorsCount = 0
    foreach ($s in $scripts) {
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$null, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            Write-Error "Erreur syntaxe dans $($s.FullName) : $($parseErrors.Message)"
            $errorsCount++
        }
    }
    if ($errorsCount -gt 0) { throw "Echec AST : $errorsCount script(s) en erreur." }
    Write-Host "[OK] $($scripts.Count) scripts/modules valides sous $($PSVersionTable.PSVersion)." -ForegroundColor Green

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

    if ($RunAnalyzer) {
        Ensure-GalleryModule -Name 'PSScriptAnalyzer'
        $findings = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error | Where-Object { $_.ScriptPath -notmatch '[/\\]Tests[/\\]' }
        if ($findings) {
            $findings | Format-Table ScriptName, Line, RuleName, Message -AutoSize
            throw "PSScriptAnalyzer a detecte des erreurs critiques."
        }
        Write-Host "[OK] Zero erreur critique PSScriptAnalyzer." -ForegroundColor Green
    }

    Ensure-GalleryModule -Name 'Pester' -MinVersion '5.0.0'
    Import-Module Pester -MinimumVersion 5.0.0 -Force
    $res = Invoke-Pester -Path @('./Tests/ESN-EnterpriseModules.Tests.ps1', './Tests/WSAT-Enterprise.Tests.ps1') -Output Detailed -PassThru
    if ($res.FailedCount -gt 0) {
        throw "Echec Pester : $($res.FailedCount) test(s) en erreur."
    }
}
finally {
    Pop-Location
}
