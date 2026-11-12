#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-Core — Module fondation du toolkit ESN.
    Logging centralisé, rapport HTML, export ZIP incident.
#>

Set-StrictMode -Version Latest

# ─────────────────────────────────────────────
# CONFIG GLOBALE
# ─────────────────────────────────────────────
$script:ESNConfig = @{
    Version      = "1.0.0"
    LogRoot      = "C:\ESN-Toolkit\Logs"
    ReportRoot   = "C:\ESN-Toolkit\Reports"
    ZipRoot      = "C:\ESN-Toolkit\ZipIncidents"
    MaxLogDays   = 30
    TeamsWebhook = ""          # optionnel
    SmtpServer   = ""          # optionnel
    AlertMail    = ""          # optionnel
}

# Session courante
$script:Session = @{
    Id         = ""
    ScriptName = ""
    StartTime  = $null
    LogFile    = ""
    Results    = [System.Collections.Generic.List[PSCustomObject]]::new()
    Errors     = [System.Collections.Generic.List[string]]::new()
    Warnings   = [System.Collections.Generic.List[string]]::new()
    Score      = 100
}

# ─────────────────────────────────────────────
# INIT SESSION
# ─────────────────────────────────────────────
function Initialize-ESNSession {
    [CmdletBinding()]
    param(
        [string]$ScriptName   = $(if ($MyInvocation.PSCommandPath) { Split-Path $MyInvocation.PSCommandPath -Leaf } else { 'Interactive' }),
        [string]$IncidentId   = "INC-$(Get-Date -Format 'yyyyMMdd-HHmm')",
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $script:Session.Id         = $IncidentId
    $script:Session.ScriptName = $ScriptName
    $script:Session.StartTime  = Get-Date
    $script:Session.Results    = [System.Collections.Generic.List[PSCustomObject]]::new()
    $script:Session.Errors     = [System.Collections.Generic.List[string]]::new()
    $script:Session.Warnings   = [System.Collections.Generic.List[string]]::new()
    $script:Session.Score      = 100

    $logDir = Join-Path $script:ESNConfig.LogRoot (Get-Date -Format "yyyy-MM-dd")
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    $script:Session.LogFile = Join-Path $logDir "$IncidentId`_$ScriptName.log"

    $banner = @"
════════════════════════════════════════════════════════
  ESN Toolkit v$($script:ESNConfig.Version)
  Script    : $ScriptName
  Incident  : $IncidentId
  Cible     : $ComputerName
  Opérateur : $env:USERNAME
  Démarrage : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  Log       : $($script:Session.LogFile)
════════════════════════════════════════════════════════
"@
    Write-Host $banner -ForegroundColor Cyan
    _WriteLogFile $banner

    return $script:Session.LogFile
}

# ─────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────
function Write-ESNLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("OK","WARN","ERROR","INFO","SECTION","DEBUG")]
        [string]$Level = "INFO"
    )

    $ts     = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        "OK"      { "[+]" } "WARN"  { "[!]" } "ERROR"   { "[X]" }
        "INFO"    { "[i]" } "SECTION"{"[=]" } "DEBUG"   { "[D]" }
        default   { "[?]" }
    }
    $color = switch ($Level) {
        "OK"      { "Green"   } "WARN"    { "Yellow"  } "ERROR"   { "Red"     }
        "INFO"    { "Cyan"    } "SECTION" { "Magenta" } "DEBUG"   { "DarkGray"}
        default   { "White"   }
    }

    $line = "[$ts][$Level]$prefix $Message"

    if ($Level -eq "SECTION") {
        Write-Host "`n$("─" * 55)" -ForegroundColor $color
        Write-Host "  $Message"    -ForegroundColor $color
        Write-Host "$("─" * 55)"  -ForegroundColor $color
    } else {
        Write-Host $line -ForegroundColor $color
    }

    _WriteLogFile $line

    if ($Level -eq "ERROR")   { $script:Session.Errors.Add($Message) }
    if ($Level -eq "WARN")    { $script:Session.Warnings.Add($Message) }
}

function _WriteLogFile {
    param([string]$Line)
    if ($script:Session.LogFile -and (Test-Path (Split-Path $script:Session.LogFile))) {
        Add-Content -Path $script:Session.LogFile -Value $Line -Encoding UTF8
    }
}

Set-Alias -Name Log -Value Write-ESNLog

# ─────────────────────────────────────────────
# RÉSULTATS DE CHECKS
# ─────────────────────────────────────────────
function Add-ESNResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)]
        [ValidateSet("OK","WARN","ERROR","INFO","SKIP")]
        [string]$Status,
        [string]$Value   = "",
        [string]$Details = "",
        [int]$ScoreImpact = 0
    )

    $obj = [PSCustomObject]@{
        Time     = Get-Date -Format "HH:mm:ss"
        Category = $Category
        Check    = $Check
        Status   = $Status
        Value    = $Value
        Details  = $Details
    }
    $script:Session.Results.Add($obj)

    $impact = if ($ScoreImpact -gt 0) { $ScoreImpact } else {
        switch ($Status) { "ERROR" { 10 } "WARN" { 5 } default { 0 } }
    }
    $script:Session.Score = [Math]::Max(0, $script:Session.Score - $impact)

    $lvl = switch ($Status) { "ERROR"{"ERROR"} "WARN"{"WARN"} "OK"{"OK"} default{"INFO"} }
    Write-ESNLog "$Category → $Check : $Value $(if($Details){"($Details)"})" $lvl
}

Set-Alias -Name Result -Value Add-ESNResult

# ─────────────────────────────────────────────
# RAPPORT HTML
# ─────────────────────────────────────────────
function Export-ESNReport {
    [CmdletBinding()]
    param(
        [string]$Title      = "Rapport ESN — $($script:Session.ScriptName)",
        [string]$OutputPath = "",
        [switch]$Open
    )

    if (-not $OutputPath) {
        $rDir = Join-Path $script:ESNConfig.ReportRoot (Get-Date -Format "yyyy-MM-dd")
        New-Item -Path $rDir -ItemType Directory -Force | Out-Null
        $OutputPath = Join-Path $rDir "$($script:Session.Id)_rapport.html"
    }

    $duration   = ((Get-Date) - $script:Session.StartTime).ToString("h\h\ mm\m\ ss\s")
    $score      = $script:Session.Score
    $scoreColor = if ($score -ge 80) { "#28a745" } elseif ($score -ge 50) { "#ffc107" } else { "#dc3545" }
    $scoreLabel = if ($score -ge 80) { "Bon" }     elseif ($score -ge 50) { "Dégradé" } else { "Critique" }

    $cntOK   = ($script:Session.Results | Where-Object Status -eq "OK").Count
    $cntWARN = ($script:Session.Results | Where-Object Status -eq "WARN").Count
    $cntERR  = ($script:Session.Results | Where-Object Status -eq "ERROR").Count
    $cntTOT  = $script:Session.Results.Count

    # Lignes tableau
    $rows = ($script:Session.Results | ForEach-Object {
        $bg   = switch ($_.Status) {
            "OK"    { "#d4edda" } "WARN" { "#fff3cd" }
            "ERROR" { "#f8d7da" } "INFO" { "#e2f3fd" }
            default { "#f8f9fa" }
        }
        $icon = switch ($_.Status) {
            "OK"    { "✅" } "WARN" { "⚠️" } "ERROR" { "❌" }
            "INFO"  { "ℹ️" } default { "⏭️" }
        }
        "<tr style='background:$bg'>
          <td>$($_.Time)</td>
          <td><strong>$($_.Category)</strong></td>
          <td>$($_.Check)</td>
          <td>$icon&nbsp;<strong>$($_.Status)</strong></td>
          <td>$($_.Value)</td>
          <td style='color:#555;font-size:.85em'>$($_.Details)</td>
        </tr>"
    }) -join "`n"

    # Blocs erreurs / warnings
    $errBlock  = if ($script:Session.Errors.Count -gt 0) {
        "<div class='alert alert-danger'><strong>❌ Erreurs ($($script:Session.Errors.Count))</strong><ul>" +
        ($script:Session.Errors | ForEach-Object { "<li>$_</li>" }) -join "" + "</ul></div>"
    } else { "" }

    $warnBlock = if ($script:Session.Warnings.Count -gt 0) {
        "<div class='alert alert-warning'><strong>⚠️ Avertissements ($($script:Session.Warnings.Count))</strong><ul>" +
        ($script:Session.Warnings | ForEach-Object { "<li>$_</li>" }) -join "" + "</ul></div>"
    } else { "" }

    $html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>$Title</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'Segoe UI',Arial,sans-serif;background:#f4f6f9;color:#333;font-size:14px}
    .header{background:linear-gradient(135deg,#0078d4,#005a9e);color:#fff;padding:28px 36px}
    .header h1{font-size:1.5em;margin-bottom:6px}
    .header p{opacity:.85;font-size:.9em}
    .container{max-width:1300px;margin:20px auto;padding:0 20px}
    .score-card{background:#fff;border-radius:12px;padding:24px;margin:16px 0;
                box-shadow:0 2px 10px rgba(0,0,0,.08);text-align:center}
    .score-num{font-size:4.5em;font-weight:800;color:$scoreColor;line-height:1}
    .score-label{font-size:1.2em;font-weight:600;color:$scoreColor;margin-top:6px}
    .progress{height:18px;border-radius:9px;background:#e9ecef;overflow:hidden;margin:14px auto;max-width:500px}
    .progress-bar{height:100%;border-radius:9px;background:$scoreColor;width:${score}%}
    .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin:16px 0}
    .card{background:#fff;border-radius:10px;padding:16px;text-align:center;
          box-shadow:0 2px 8px rgba(0,0,0,.07)}
    .card .val{font-size:2.2em;font-weight:700}
    .card .lbl{font-size:.8em;color:#666;margin-top:4px}
    .section{background:#fff;border-radius:10px;padding:22px;margin:14px 0;
             box-shadow:0 2px 8px rgba(0,0,0,.07)}
    .section h2{font-size:1em;font-weight:700;color:#0078d4;margin-bottom:14px;
                padding-bottom:8px;border-bottom:2px solid #f0f0f0}
    table{width:100%;border-collapse:collapse}
    th{background:#0078d4;color:#fff;padding:9px 12px;text-align:left;font-weight:600;font-size:.85em}
    td{padding:7px 12px;border-bottom:1px solid #f0f0f0;font-size:.88em}
    tr:hover td{background:rgba(0,120,212,.04)}
    .alert{border-radius:8px;padding:14px 18px;margin:10px 0}
    .alert-danger{background:#f8d7da;border:1px solid #f5c2c7;color:#842029}
    .alert-warning{background:#fff3cd;border:1px solid #ffecb5;color:#664d03}
    .alert ul{margin:8px 0 0 20px}
    .meta{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px;margin:10px 0}
    .meta-item{background:#f8f9fa;border-radius:6px;padding:10px 14px}
    .meta-item .key{font-size:.75em;color:#888;text-transform:uppercase;font-weight:600}
    .meta-item .val2{font-size:.95em;font-weight:600;margin-top:3px}
    .footer{text-align:center;padding:20px;color:#aaa;font-size:.8em}
    @media print{body{background:#fff}.header{-webkit-print-color-adjust:exact}}
  </style>
</head>
<body>

<div class="header">
  <h1>🖥️ $Title</h1>
  <p>
    Incident&nbsp;<strong>$($script:Session.Id)</strong>&nbsp;|&nbsp;
    Opérateur&nbsp;<strong>$env:USERNAME</strong>&nbsp;|&nbsp;
    $(Get-Date -Format 'dd/MM/yyyy HH:mm')&nbsp;|&nbsp;
    Durée&nbsp;<strong>$duration</strong>
  </p>
</div>

<div class="container">

  <!-- Score -->
  <div class="score-card">
    <div class="score-num">$score<span style="font-size:.4em;color:#888">/100</span></div>
    <div class="score-label">$scoreLabel</div>
    <div class="progress"><div class="progress-bar"></div></div>
  </div>

  <!-- Compteurs -->
  <div class="cards">
    <div class="card"><div class="val" style="color:#28a745">$cntOK</div><div class="lbl">OK</div></div>
    <div class="card"><div class="val" style="color:#ffc107">$cntWARN</div><div class="lbl">Avertissements</div></div>
    <div class="card"><div class="val" style="color:#dc3545">$cntERR</div><div class="lbl">Erreurs</div></div>
    <div class="card"><div class="val">$cntTOT</div><div class="lbl">Total checks</div></div>
    <div class="card"><div class="val" style="font-size:1.4em">$duration</div><div class="lbl">Durée</div></div>
  </div>

  <!-- Métadonnées -->
  <div class="section">
    <h2>📋 Informations de session</h2>
    <div class="meta">
      <div class="meta-item"><div class="key">ID Incident</div><div class="val2">$($script:Session.Id)</div></div>
      <div class="meta-item"><div class="key">Script</div><div class="val2">$($script:Session.ScriptName)</div></div>
      <div class="meta-item"><div class="key">Opérateur</div><div class="val2">$env:USERNAME</div></div>
      <div class="meta-item"><div class="key">Poste opérateur</div><div class="val2">$env:COMPUTERNAME</div></div>
      <div class="meta-item"><div class="key">Démarrage</div><div class="val2">$(Get-Date $script:Session.StartTime -Format 'dd/MM/yyyy HH:mm:ss')</div></div>
      <div class="meta-item"><div class="key">Fin</div><div class="val2">$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</div></div>
      <div class="meta-item"><div class="key">Log</div><div class="val2" style="font-size:.8em;word-break:break-all">$($script:Session.LogFile)</div></div>
      <div class="meta-item"><div class="key">Rapport</div><div class="val2" style="font-size:.8em;word-break:break-all">$OutputPath</div></div>
    </div>
  </div>

  $errBlock
  $warnBlock

  <!-- Tableau de résultats -->
  <div class="section">
    <h2>📊 Résultats détaillés ($cntTOT checks)</h2>
    <table>
      <thead>
        <tr>
          <th>Heure</th><th>Catégorie</th><th>Vérification</th>
          <th>Statut</th><th>Valeur</th><th>Détails</th>
        </tr>
      </thead>
      <tbody>
        $rows
      </tbody>
    </table>
  </div>

</div>

<div class="footer">
  ESN Toolkit v$($script:ESNConfig.Version) — Généré le $(Get-Date -Format 'dd/MM/yyyy à HH:mm:ss') — $env:USERNAME
</div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-ESNLog "Rapport HTML généré : $OutputPath" "OK"
    if ($Open) { Start-Process $OutputPath }
    return $OutputPath
}

# ─────────────────────────────────────────────
# EXPORT ZIP INCIDENT
# ─────────────────────────────────────────────
function Export-ESNZip {
    [CmdletBinding()]
    param(
        [string[]]$ExtraFiles = @(),
        [string]$OutputDir    = $script:ESNConfig.ZipRoot
    )

    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    $zipName = "$($script:Session.Id)_$(Get-Date -Format 'yyyyMMdd-HHmm').zip"
    $zipPath = Join-Path $OutputDir $zipName
    $tmpDir  = Join-Path $env:TEMP "ESN_ZIP_$(Get-Random)"
    New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null

    # Log courant
    if ($script:Session.LogFile -and (Test-Path $script:Session.LogFile)) {
        Copy-Item $script:Session.LogFile $tmpDir -Force
    }

    # Fichiers supplémentaires (ex: rapport HTML)
    foreach ($f in $ExtraFiles) {
        if (Test-Path $f) { Copy-Item $f $tmpDir -Force -ErrorAction SilentlyContinue }
    }

    # Fiche incident JSON
    @{
        IncidentId   = $script:Session.Id
        ScriptName   = $script:Session.ScriptName
        Operator     = $env:USERNAME
        Computer     = $env:COMPUTERNAME
        Domain       = $env:USERDNSDOMAIN
        StartTime    = $script:Session.StartTime.ToString("o")
        EndTime      = (Get-Date).ToString("o")
        Score        = $script:Session.Score
        ErrorCount   = $script:Session.Errors.Count
        WarningCount = $script:Session.Warnings.Count
        Errors       = $script:Session.Errors
        Warnings     = $script:Session.Warnings
    } | ConvertTo-Json | Out-File (Join-Path $tmpDir "incident.json") -Encoding UTF8

    # CSV résultats
    $script:Session.Results |
        Export-Csv (Join-Path $tmpDir "results.csv") -NoTypeInformation -Encoding UTF8

    Compress-Archive -Path "$tmpDir\*" -DestinationPath $zipPath -Force
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-ESNLog "ZIP incident créé : $zipPath" "OK"
    return $zipPath
}

# ─────────────────────────────────────────────
# RÉSUMÉ CONSOLE
# ─────────────────────────────────────────────
function Show-ESNSummary {
    $dur   = ((Get-Date) - $script:Session.StartTime).ToString("h\h\ mm\m\ ss\s")
    $score = $script:Session.Score
    $col   = if ($score -ge 80) { "Green" } elseif ($score -ge 50) { "Yellow" } else { "Red" }

    Write-Host "`n╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  RÉSUMÉ SESSION ESN TOOLKIT" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Score    : " -NoNewline -ForegroundColor Cyan
    Write-Host "$score/100" -ForegroundColor $col -NoNewline
    Write-Host "" -ForegroundColor Cyan
    Write-Host "║  Durée    : $dur" -ForegroundColor Cyan
    Write-Host "║  OK       : " -NoNewline -ForegroundColor Cyan
    Write-Host "$(($script:Session.Results | Where-Object Status -eq 'OK').Count)" -ForegroundColor Green
    Write-Host "║  Warnings : " -NoNewline -ForegroundColor Cyan
    Write-Host "$(($script:Session.Results | Where-Object Status -eq 'WARN').Count)" -ForegroundColor Yellow
    Write-Host "║  Erreurs  : " -NoNewline -ForegroundColor Cyan
    Write-Host "$(($script:Session.Results | Where-Object Status -eq 'ERROR').Count)" -ForegroundColor Red
    Write-Host "║  Log      : $($script:Session.LogFile)" -ForegroundColor DarkGray
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
}

# ─────────────────────────────────────────────
# HELPER : TEST CONNECTIVITÉ
# ─────────────────────────────────────────────
function Test-ESNPort {
    # $Host est une variable automatique en lecture seule : le paramètre s'appelle ComputerName (alias Host conservé)
    param([Alias('Host')][string]$ComputerName, [int]$Port, [int]$TimeoutMs = 1000)
    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        $r = $tcp.BeginConnect($ComputerName, $Port, $null, $null)
        # WaitOne est vrai aussi quand la connexion est REFUSÉE : il faut vérifier Connected
        if (-not $r.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $tcp.EndConnect($r)
        return $tcp.Connected
    } catch { return $false }
    finally { $tcp.Close() }
}

function Test-ESNAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ESNConfig { return $script:ESNConfig }
function Get-ESNSession { return $script:Session }

# ─────────────────────────────────────────────
# EXPORTS
# ─────────────────────────────────────────────
Export-ModuleMember -Function @(
    'Initialize-ESNSession', 'Write-ESNLog',    'Add-ESNResult',
    'Export-ESNReport',      'Export-ESNZip',   'Show-ESNSummary',
    'Test-ESNPort',          'Test-ESNAdmin',
    'Get-ESNConfig',         'Get-ESNSession'
) -Alias 'Log','Result'
