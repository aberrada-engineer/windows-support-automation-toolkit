#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-ReportBuilder — Générateur de rapport HTML unifié offline.
    PATCH 3/5 — Industrialisation & cohérence globale.

.DESCRIPTION
    Produit un rapport HTML autonome (CSS inline, zéro dépendance externe)
    exploitable sans connexion internet, intégrant :
      - Score global + scores par domaine avec jauges SVG
      - Résumé exécutif (machine info + verdict)
      - Impacts détaillés sur le score (traçabilité)
      - Erreurs et recommandations actionnables
      - Remédiations exécutées
      - Base de connaissances incidents (IncidentPatterns)
      - Sections pliables (HTML/CSS pur, pas de JS obligatoire)
      - Export JSON intégré (bouton copier)
#>

Set-StrictMode -Version Latest

function Build-ESNReport {
<#
.SYNOPSIS
    Génère le rapport HTML complet à partir des données collectées.

.PARAMETER SessionData
    Objet session ESN-Core (Get-ESNSession).
.PARAMETER HealthData
    Objet retourné par Invoke-HealthScore -PassThru (optionnel).
.PARAMETER RemediationData
    Tableau retourné par Invoke-Remediation (optionnel).
.PARAMETER ComputerName
    Nom du poste analysé.
.PARAMETER IncidentId
    ID du ticket.
.PARAMETER OutputPath
    Chemin du fichier HTML à générer.
.PARAMETER IncidentPatternsPath
    Chemin vers IncidentPatterns.json.
.PARAMETER Open
    Ouvre le rapport dans le navigateur par défaut.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$SessionData,
        [PSCustomObject] $HealthData            = $null,
        [PSCustomObject[]]$RemediationData      = @(),
        [string]  $ComputerName                 = $env:COMPUTERNAME,
        [string]  $IncidentId                   = "REPORT",
        [string]  $OutputPath                   = "",
        [string]  $IncidentPatternsPath         = "",
        [switch]  $Open
    )

    function Get-ESNProp {
        param([object]$Obj, [string[]]$Names, $Default = "")
        if ($null -eq $Obj) { return $Default }
        foreach ($n in $Names) {
            $p = $Obj.PSObject.Properties[$n]
            if ($null -ne $p -and $null -ne $p.Value -and "$($p.Value)" -ne "") { return $p.Value }
        }
        return $Default
    }

    # ── Résolution des chemins ────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $repRoot = if (Get-Command Get-ESNReportRoot -ErrorAction SilentlyContinue) { Get-ESNReportRoot } else { "C:\ESN-Toolkit\Reports" }
        $OutputPath = Join-Path $repRoot "report_$(Get-Date -Format 'yyyyMMdd_HHmm').html"
    }
    if (-not $IncidentPatternsPath) {
        $IncidentPatternsPath = Join-Path $PSScriptRoot "IncidentPatterns.json"
    }

    # ── Chargement base de connaissances ─────────────────────
    $patterns = @()
    if (Test-Path $IncidentPatternsPath) {
        try {
            $kb = Get-Content $IncidentPatternsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $patterns = $kb.patterns
        } catch {
            Write-Warning "IncidentPatterns load skipped ($IncidentPatternsPath): $($_.Exception.Message)"
        }
    }

    # ── Données dérivées ─────────────────────────────────────
    $duration   = if (Get-ESNProp $SessionData @("StartTime") $null) {
        ((Get-Date) - $SessionData.StartTime).ToString("h\h\ mm\m\ ss\s")
    } else { "N/A" }

    $results    = @(Get-ESNProp $SessionData @("Results") @())
    $cntOK      = @($results | Where-Object { (Get-ESNProp $_ @("Status","severity")) -eq "OK" }).Count
    $cntWarn    = @($results | Where-Object { (Get-ESNProp $_ @("Status","severity")) -in "WARN","WARNING" }).Count
    $cntErr     = @($results | Where-Object { (Get-ESNProp $_ @("Status","severity")) -in "ERROR","CRITICAL" }).Count
    $cntTotal   = $results.Count

    # Score global (priorité à HealthScore, sinon session ESN-Core)
    $globalScore = if ($HealthData) { $HealthData.Global.Score } else { [int](Get-ESNProp $SessionData @("Score","global_score") 0) }
    $globalLabel = if ($globalScore -ge 80) {"Bon"} elseif ($globalScore -ge 60) {"Dégradé"} elseif ($globalScore -ge 40) {"Mauvais"} else {"Critique"}
    $globalColor = if ($globalScore -ge 80) {"#28a745"} elseif ($globalScore -ge 60) {"#ffc107"} elseif ($globalScore -ge 40) {"#fd7e14"} else {"#dc3545"}

    # Machine info depuis les résultats
    $machineOS    = Get-ESNProp ($results | Where-Object { (Get-ESNProp $_ @("Check","check")) -eq "Système d'exploitation" } | Select-Object -First 1) @("Value","value")
    $machineRAM   = Get-ESNProp ($results | Where-Object { (Get-ESNProp $_ @("Check","check")) -eq "RAM" } | Select-Object -First 1) @("Value","value")
    $machineCPU   = Get-ESNProp ($results | Where-Object { (Get-ESNProp $_ @("Check","check")) -eq "CPU" } | Select-Object -First 1) @("Value","value")
    $machineUp    = Get-ESNProp ($results | Where-Object { (Get-ESNProp $_ @("Check","check")) -eq "Uptime" } | Select-Object -First 1) @("Value","value")
    $machineDom   = Get-ESNProp ($results | Where-Object { (Get-ESNProp $_ @("Check","check")) -eq "Domaine" } | Select-Object -First 1) @("Value","value")

    # ── Fonctions helpers HTML ────────────────────────────────
    function Make-Gauge([int]$Score, [string]$Label, [string]$DomLabel) {
        $c   = if ($Score -ge 80) {"#28a745"} elseif ($Score -ge 60) {"#ffc107"} elseif ($Score -ge 40) {"#fd7e14"} else {"#dc3545"}
        $r   = 44
        $ci  = [math]::Round(2 * 3.14159 * $r, 1)
        $f   = [math]::Round($ci * $Score / 100, 1)
        $g   = $ci - $f
        $off = [math]::Round($ci / 4, 1)
        return @"
<div style='display:inline-block;text-align:center;margin:0 10px'>
  <svg width='110' height='110' viewBox='0 0 110 110'>
    <circle cx='55' cy='55' r='$r' fill='none' stroke='#e9ecef' stroke-width='10'/>
    <circle cx='55' cy='55' r='$r' fill='none' stroke='$c' stroke-width='10'
      stroke-dasharray='$f $g' stroke-dashoffset='$off' stroke-linecap='round'/>
    <text x='55' y='50' text-anchor='middle' font-size='20' font-weight='800' fill='$c'>$Score</text>
    <text x='55' y='65' text-anchor='middle' font-size='9' fill='#999'>/100</text>
  </svg>
  <div style='font-weight:700;font-size:12px;margin-top:2px'>$DomLabel</div>
  <div style='font-size:11px;color:$c'>$Label</div>
</div>
"@
    }

    function Make-SeverityBadge([string]$Status) {
        $bg   = switch ($Status) { "OK"{"#d4edda"} "WARN"{"#fff3cd"} "WARNING"{"#fff3cd"} "ERROR"{"#f8d7da"} "CRITICAL"{"#f8d7da"} "INFO"{"#e2f3fd"} default{"#f8f9fa"} }
        $tc   = switch ($Status) { "OK"{"#155724"} "WARN"{"#856404"} "WARNING"{"#856404"} "ERROR"{"#721c24"} "CRITICAL"{"#721c24"} "INFO"{"#0c5460"} default{"#333"} }
        $lbl  = switch ($Status) { "WARN"{"WARNING"} "ERROR"{"CRITICAL"} default{$Status} }
        return "<span style='background:$bg;color:$tc;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:700'>$lbl</span>"
    }

    function Make-Collapsible([string]$Id, [string]$Title, [string]$Count, [string]$TitleColor, [string]$Body) {
        return @"
<div style='margin:12px 0;border:1px solid #e0e0e0;border-radius:8px;overflow:hidden'>
  <input type='checkbox' id='sec-$Id' style='display:none'>
  <label for='sec-$Id' style='display:flex;justify-content:space-between;align-items:center;
    padding:12px 18px;background:#fff;cursor:pointer;font-weight:700;color:$TitleColor;
    font-size:14px;border-bottom:1px solid #e0e0e0'>
    $Title
    <span style='display:flex;align-items:center;gap:10px'>
      <span style='background:$TitleColor;color:#fff;border-radius:10px;
        padding:2px 10px;font-size:12px'>$Count</span>
      <span style='font-size:18px'>&#9660;</span>
    </span>
  </label>
  <div style='display:none' id='body-$Id'>$Body</div>
</div>
<style>#sec-$Id:checked ~ * #body-$Id { display:block !important }</style>
"@
    }

    # ── Résultats par check ────────────────────────────────────
    $checkRows = ($results | ForEach-Object {
        $rTime = Get-ESNProp $_ @("Time","timestamp")
        $rCat  = Get-ESNProp $_ @("Category","domain")
        $rChk  = Get-ESNProp $_ @("Check","check")
        $rSt   = Get-ESNProp $_ @("Status","severity") "INFO"
        $rVal  = Get-ESNProp $_ @("Value","value")
        $rDet  = Get-ESNProp $_ @("Details","detail")
        $bg    = switch ($rSt) { "OK"{"#d4edda"} "WARN"{"#fff3cd"} "WARNING"{"#fff3cd"} "ERROR"{"#f8d7da"} "CRITICAL"{"#f8d7da"} "INFO"{"#e2f3fd"} default{"#f8f9fa"} }
        "<tr style='background:$bg'>
          <td style='padding:6px 10px;font-size:12px'>$rTime</td>
          <td style='padding:6px 10px;font-size:12px'><strong>$rCat</strong></td>
          <td style='padding:6px 10px;font-size:12px'>$rChk</td>
          <td style='padding:6px 10px;font-size:12px'>$(Make-SeverityBadge $rSt)</td>
          <td style='padding:6px 10px;font-size:12px'>$rVal</td>
          <td style='padding:6px 10px;font-size:11px;color:#555'>$rDet</td>
        </tr>"
    }) -join "`n"

    $checksTable = "<table style='width:100%;border-collapse:collapse'>
      <tr>
        <th style='background:#1b2838;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Heure</th>
        <th style='background:#1b2838;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Domaine</th>
        <th style='background:#1b2838;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Check</th>
        <th style='background:#1b2838;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Statut</th>
        <th style='background:#1b2838;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Valeur</th>
        <th style='background:#1b2838;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Détail</th>
      </tr>$checkRows</table>"

    # ── Impacts sur le score ───────────────────────────────────
    $impactItems = @($results | Where-Object { (Get-ESNProp $_ @("Status","severity")) -in "WARN","WARNING","ERROR","CRITICAL" })
    $impactRows  = ($impactItems | ForEach-Object {
        $iSt  = Get-ESNProp $_ @("Status","severity")
        $imp  = if ($iSt -in "ERROR","CRITICAL") { "−15 pts" } elseif ($iSt -in "WARN","WARNING") { "−5 pts" } else { "0 pt" }
        $col  = if ($iSt -in "ERROR","CRITICAL") { "#dc3545" } else { "#856404" }
        "<tr>
          <td style='padding:6px 10px;font-size:12px'><strong>$(Get-ESNProp $_ @("Category","domain"))</strong></td>
          <td style='padding:6px 10px;font-size:12px'>$(Get-ESNProp $_ @("Check","check"))</td>
          <td style='padding:6px 10px;font-size:12px'>$(Get-ESNProp $_ @("Value","value"))</td>
          <td style='padding:6px 10px;font-size:12px;color:$col;font-weight:700'>$imp</td>
        </tr>"
    }) -join "`n"

    $impactTable = if ($impactItems.Count -gt 0) {
        "<table style='width:100%;border-collapse:collapse'>
          <tr>
            <th style='background:#dc3545;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Domaine</th>
            <th style='background:#dc3545;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Problème</th>
            <th style='background:#dc3545;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Valeur</th>
            <th style='background:#dc3545;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Impact</th>
          </tr>$impactRows</table>"
    } else {
        "<p style='color:#155724;font-weight:600;padding:10px'>&#10003; Aucun impact négatif sur le score</p>"
    }

    # ── Recommandations ───────────────────────────────────────
    $recErrors = @(Get-ESNProp $SessionData @("Errors") @()) + @(Get-ESNProp $SessionData @("Warnings") @())
    $recHtml   = if ($recErrors.Count -gt 0) {
        "<ul style='margin:0;padding-left:20px'>" +
        ($recErrors | ForEach-Object {
            $isCrit = $_ -like "*CRITIQUE*" -or $_ -like "*CRITICAL*"
            $col    = if ($isCrit) { "#721c24" } else { "#856404" }
            "<li style='margin:6px 0;color:$col;font-size:13px'>$_</li>"
        }) -join "" + "</ul>"
    } else {
        "<p style='color:#155724;font-weight:600'>&#10003; Aucune recommandation — poste en bonne santé</p>"
    }

    # ── Remédiations ──────────────────────────────────────────
    $remRows = ""
    if ($RemediationData.Count -gt 0) {
        $remRows = ($RemediationData | ForEach-Object {
            $status = if (-not $_.Detected)         { "Non détecté" }
                      elseif ($_.Applied -and $_.Success) { "Corrigé" }
                      elseif ($_.Applied)            { "Échec" }
                      else                           { "Détecté, non corrigé" }
            $bg     = if (-not $_.Detected)          { "#d4edda" }
                      elseif ($_.Applied -and $_.Success) { "#cce5ff" }
                      elseif ($_.Applied)            { "#f8d7da" }
                      else                           { "#fff3cd" }
            "<tr style='background:$bg'>
              <td style='padding:6px 10px;font-size:12px'><strong>$($_.Id)</strong></td>
              <td style='padding:6px 10px;font-size:12px'>$($_.Name)</td>
              <td style='padding:6px 10px;font-size:12px'>$status</td>
              <td style='padding:6px 10px;font-size:11px'>$($_.Before)</td>
              <td style='padding:6px 10px;font-size:11px'>$($_.After)</td>
            </tr>"
        }) -join "`n"
    }

    $remTable = if ($remRows) {
        "<table style='width:100%;border-collapse:collapse'>
          <tr>
            <th style='background:#0078d4;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>ID</th>
            <th style='background:#0078d4;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Remédiation</th>
            <th style='background:#0078d4;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Statut</th>
            <th style='background:#0078d4;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Avant</th>
            <th style='background:#0078d4;color:#fff;padding:8px 10px;text-align:left;font-size:12px'>Après</th>
          </tr>$remRows</table>"
    } else {
        "<p style='color:#555;padding:10px;font-size:13px'>Aucune remédiation exécutée lors de cette session.</p>"
    }

    # ── Base de connaissances — patterns détectés ─────────────
    $matchedPatterns = @()
    if ($patterns.Count -gt 0) {
        $allText = ($results | ForEach-Object { "$(Get-ESNProp $_ @('Category','domain')) $(Get-ESNProp $_ @('Check','check')) $(Get-ESNProp $_ @('Value','value')) $(Get-ESNProp $_ @('Details','detail')) $(Get-ESNProp $_ @('Status','severity'))" }) -join " "
        foreach ($pat in $patterns) {
            $matched = $false
            foreach ($kw in $pat.keywords) {
                if ($allText -match [Regex]::Escape($kw)) { $matched = $true; break }
            }
            if ($matched) { $matchedPatterns += $pat }
        }
    }

    $kbHtml = if ($matchedPatterns.Count -gt 0) {
        ($matchedPatterns | ForEach-Object {
            $sevCol = if ($_.severity -eq "CRITICAL") { "#dc3545" } else { "#856404" }
            $steps  = ($_.remediation_steps | ForEach-Object { "<li style='margin:4px 0;font-size:12px'>$_</li>" }) -join ""
            $cmd    = if ($_.powershell_fix) { "<div style='background:#1e1e1e;color:#dcdcdc;padding:10px;border-radius:6px;margin-top:8px;font-family:monospace;font-size:11px'>PS> $($_.powershell_fix)</div>" } else { "" }
            "<div style='background:#f8f9fa;border-left:4px solid $sevCol;border-radius:0 8px 8px 0;padding:12px 16px;margin:8px 0'>
              <div style='font-weight:700;font-size:13px;color:$sevCol'>[$($_.id)] $($_.symptom)</div>
              <div style='font-size:12px;color:#555;margin:4px 0'><strong>Cause probable :</strong> $($_.likely_cause)</div>
              <ul style='margin:6px 0 0 18px'>$steps</ul>
              $cmd
            </div>"
        }) -join "`n"
    } else {
        "<p style='color:#155724;font-size:13px;padding:10px'>&#10003; Aucun pattern d'incident connu correspondant aux problèmes détectés.</p>"
    }

    # ── Jauges par domaine ────────────────────────────────────
    $gaugesHtml = ""
    if ($HealthData) {
        $gaugesHtml = @"
<div style='text-align:center;margin:16px 0;flex-wrap:wrap;display:flex;justify-content:center;gap:8px'>
  $(Make-Gauge $HealthData.Network.Score  $HealthData.Network.Label  "Réseau")
  $(Make-Gauge $HealthData.System.Score   $HealthData.System.Label   "Système")
  $(Make-Gauge $HealthData.Security.Score $HealthData.Security.Label "Sécurité")
  $(Make-Gauge $HealthData.Storage.Score  $HealthData.Storage.Label  "Stockage")
  $(Make-Gauge $HealthData.Services.Score $HealthData.Services.Label "Services")
</div>
"@
    }

    # ── JSON export ───────────────────────────────────────────
    $jsonPayload = @{
        incident_id  = $IncidentId
        computer     = $ComputerName
        generated_at = (Get-Date -Format "o")
        global_score = $globalScore
        checks_total = $cntTotal
        checks_ok    = $cntOK
        checks_warn  = $cntWarn
        checks_error = $cntErr
    } | ConvertTo-Json -Compress

    # ── Construction HTML ─────────────────────────────────────
    $html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Rapport ESN — $IncidentId — $ComputerName</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'Segoe UI',Arial,sans-serif;background:#f0f2f5;color:#333;font-size:14px}
    a{color:#0078d4}
    .hdr{background:linear-gradient(135deg,#0d1b2a,#1b3a5c);color:#fff;padding:28px 36px}
    .hdr h1{font-size:1.4em;margin-bottom:6px;letter-spacing:.3px}
    .hdr p{opacity:.8;font-size:.88em}
    .container{max-width:1200px;margin:16px auto;padding:0 16px}
    .card{background:#fff;border-radius:10px;padding:20px;margin:12px 0;
          box-shadow:0 2px 8px rgba(0,0,0,.07)}
    .card h2{font-size:.95em;font-weight:700;color:#0078d4;margin-bottom:14px;
             padding-bottom:8px;border-bottom:2px solid #f0f0f0}
    .meta-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px}
    .meta-item{background:#f8f9fa;border-radius:6px;padding:10px 14px}
    .meta-item .key{font-size:11px;color:#888;text-transform:uppercase;font-weight:600}
    .meta-item .val{font-size:13px;font-weight:600;margin-top:3px;word-break:break-word}
    .counter-row{display:flex;gap:12px;flex-wrap:wrap;margin:12px 0}
    .counter{background:#f8f9fa;border-radius:8px;padding:12px 16px;text-align:center;flex:1;min-width:100px}
    .counter .num{font-size:2em;font-weight:800}
    .counter .lbl{font-size:11px;color:#777;margin-top:3px}
    .verdict-box{border-radius:10px;padding:16px 20px;margin:12px 0;
                 border-left:6px solid $globalColor;background:#fff;
                 box-shadow:0 2px 8px rgba(0,0,0,.07)}
    .footer{text-align:center;padding:20px;color:#aaa;font-size:11px}
    @media print{body{background:#fff}.hdr{-webkit-print-color-adjust:exact;background:#0d1b2a!important}}
  </style>
</head>
<body>

<!-- HEADER -->
<div class="hdr">
  <h1>&#128187; Rapport Analyse ESN — $IncidentId</h1>
  <p>
    Poste&nbsp;<strong>$ComputerName</strong>&nbsp;|&nbsp;
    Op&eacute;rateur&nbsp;<strong>$env:USERNAME</strong>&nbsp;|&nbsp;
    $(Get-Date -Format 'dd/MM/yyyy HH:mm')&nbsp;|&nbsp;
    Dur&eacute;e&nbsp;<strong>$duration</strong>
  </p>
</div>

<div class="container">

<!-- VERDICT EXÉCUTIF -->
<div class="verdict-box">
  <div style="display:flex;align-items:center;gap:16px">
    <div style="font-size:3em;font-weight:900;color:$globalColor;line-height:1">$globalScore</div>
    <div>
      <div style="font-size:1.1em;font-weight:700;color:$globalColor">Score Global — $globalLabel</div>
      <div style="font-size:12px;color:#555;margin-top:4px">
        $cntOK check(s) OK &nbsp;&#183;&nbsp;
        $cntWarn avertissement(s) &nbsp;&#183;&nbsp;
        $cntErr erreur(s) &nbsp;&#183;&nbsp;
        $cntTotal total
      </div>
      $(if ($cntErr -gt 0) {
        "<div style='margin-top:8px;font-size:13px;color:#721c24;font-weight:600'>
          &#9888;&nbsp;$cntErr probl&egrave;me(s) critique(s) n&eacute;cessite(nt) une action imm&eacute;diate.
        </div>"
      } elseif ($cntWarn -gt 0) {
        "<div style='margin-top:8px;font-size:13px;color:#856404;font-weight:600'>
          &#9888;&nbsp;$cntWarn avertissement(s) &agrave; traiter.
        </div>"
      } else {
        "<div style='margin-top:8px;font-size:13px;color:#155724;font-weight:600'>
          &#10003;&nbsp;Aucun probl&egrave;me d&eacute;tect&eacute; — machine en bonne sant&eacute;.
        </div>"
      })
    </div>
  </div>
  $gaugesHtml
</div>

<!-- INFORMATIONS MACHINE -->
<div class="card">
  <h2>&#128187; Informations Machine</h2>
  <div class="meta-grid">
    <div class="meta-item"><div class="key">Nom du poste</div><div class="val">$ComputerName</div></div>
    <div class="meta-item"><div class="key">Syst&egrave;me d'exploitation</div><div class="val">$(if($machineOS){$machineOS}else{"N/A"})</div></div>
    <div class="meta-item"><div class="key">RAM</div><div class="val">$(if($machineRAM){$machineRAM}else{"N/A"})</div></div>
    <div class="meta-item"><div class="key">CPU</div><div class="val">$(if($machineCPU){$machineCPU}else{"N/A"})</div></div>
    <div class="meta-item"><div class="key">Uptime</div><div class="val">$(if($machineUp){$machineUp}else{"N/A"})</div></div>
    <div class="meta-item"><div class="key">Domaine</div><div class="val">$(if($machineDom){$machineDom}elseif($env:USERDNSDOMAIN){$env:USERDNSDOMAIN}else{"Workgroup"})</div></div>
    <div class="meta-item"><div class="key">Op&eacute;rateur</div><div class="val">$env:USERNAME</div></div>
    <div class="meta-item"><div class="key">ID Incident</div><div class="val">$IncidentId</div></div>
    <div class="meta-item"><div class="key">Dur&eacute;e analyse</div><div class="val">$duration</div></div>
    <div class="meta-item"><div class="key">Date rapport</div><div class="val">$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</div></div>
  </div>
</div>

<!-- COMPTEURS -->
<div class="counter-row">
  <div class="counter"><div class="num" style="color:$globalColor">$globalScore</div><div class="lbl">Score global</div></div>
  <div class="counter"><div class="num" style="color:#28a745">$cntOK</div><div class="lbl">OK</div></div>
  <div class="counter"><div class="num" style="color:#856404">$cntWarn</div><div class="lbl">Avertissements</div></div>
  <div class="counter"><div class="num" style="color:#dc3545">$cntErr</div><div class="lbl">Critiques</div></div>
  <div class="counter"><div class="num">$cntTotal</div><div class="lbl">Total checks</div></div>
  $(if ($RemediationData.Count -gt 0) {
    $fixed = @($RemediationData | Where-Object { $_.Applied -and $_.Success }).Count
    "<div class='counter'><div class='num' style='color:#0078d4'>$fixed</div><div class='lbl'>Corrig&eacute;s</div></div>"
  })
</div>

<!-- RECOMMANDATIONS -->
$(Make-Collapsible "recs" "&#128161; Recommandations actionnables" "$($recErrors.Count)" "#856404" $recHtml)

<!-- IMPACTS SUR LE SCORE -->
$(Make-Collapsible "impacts" "&#128200; Impacts d&eacute;taill&eacute;s sur le score" "$($impactItems.Count)" "#dc3545" $impactTable)

<!-- BASE DE CONNAISSANCES -->
$(if ($matchedPatterns.Count -gt 0) {
    Make-Collapsible "kb" "&#128218; Base de connaissances — $($matchedPatterns.Count) pattern(s) d&eacute;tect&eacute;(s)" "$($matchedPatterns.Count)" "#0d1b2a" $kbHtml
})

<!-- REMÉDIATIONS -->
$(Make-Collapsible "rem" "&#128295; R&eacute;m&eacute;diations ex&eacute;cut&eacute;es" "$($RemediationData.Count)" "#0078d4" $remTable)

<!-- TOUS LES CHECKS -->
$(Make-Collapsible "checks" "&#128203; D&eacute;tail de tous les checks" "$cntTotal" "#555" $checksTable)

<!-- EXPORT JSON -->
<div class="card">
  <h2>&#123;&#125; Export JSON</h2>
  <div style="background:#1e1e1e;color:#dcdcdc;padding:12px;border-radius:6px;
    font-family:monospace;font-size:11px;word-break:break-all">$jsonPayload</div>
</div>

</div><!-- /container -->

<div class="footer">
  ESN-Toolkit v3.0 — Build-ESNReport — G&eacute;n&eacute;r&eacute; le $(Get-Date -Format 'dd/MM/yyyy &agrave; HH:mm:ss') — $env:USERNAME
</div>
</body>
</html>
"@

    $dir = Split-Path $OutputPath
    if ($dir -and -not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

    if ($Open) { Start-Process $OutputPath }
    return $OutputPath
}

# Fichier chargé par dot-sourcing : toutes ses fonctions sont visibles, Export-ModuleMember y est interdit.
