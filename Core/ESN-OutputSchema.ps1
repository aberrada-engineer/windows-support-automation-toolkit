#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-OutputSchema — Schéma de sortie JSON unifié pour tous les modules ESN-Toolkit.
    PATCH 1/5 — Industrialisation & cohérence globale.

.DESCRIPTION
    Fournit les types, niveaux de gravité, et fonctions de construction
    d'objets de sortie standardisés utilisés par tous les modules.

    Niveaux de gravité unifiés :
        OK       → Aucun problème
        WARNING  → Dégradation non bloquante, action recommandée
        CRITICAL → Blocage ou risque élevé, action immédiate requise
        INFO     → Information sans impact sur le score

    Format JSON de sortie d'un check :
    {
      "id":          "NET-001",
      "domain":      "Network",
      "check":       "Adresse IP",
      "severity":    "OK|WARNING|CRITICAL|INFO",
      "value":       "192.168.1.42",
      "detail":      "DHCP, interface Ethernet0",
      "score_impact": 0,
      "remediation": "ipconfig /renew",
      "timestamp":   "2025-05-15T14:32:00"
    }
#>

Set-StrictMode -Version Latest

# ── Niveaux de gravité ────────────────────────────────────────
enum ESNSeverity {
    OK       = 0
    INFO     = 1
    WARNING  = 2
    CRITICAL = 3
}

# ── Mappage gravité → impact score par défaut ─────────────────
$script:DefaultImpacts = @{
    OK       = 0
    INFO     = 0
    WARNING  = 5
    CRITICAL = 15
}

# ── Mappage gravité → couleur HTML ───────────────────────────
$script:SeverityColors = @{
    OK       = "#d4edda"
    INFO     = "#e2f3fd"
    WARNING  = "#fff3cd"
    CRITICAL = "#f8d7da"
}

$script:SeverityIcons = @{
    OK       = "&#10003;"   # ✓
    INFO     = "&#9432;"    # ℹ
    WARNING  = "&#9888;"    # ⚠
    CRITICAL = "&#10007;"   # ✗
}

$script:SeverityTextColors = @{
    OK       = "#155724"
    INFO     = "#0c5460"
    WARNING  = "#856404"
    CRITICAL = "#721c24"
}

# ── Compteurs d'IDs par domaine ───────────────────────────────
$script:CheckCounters = @{}

function Get-ESNCheckId {
    param([string]$Domain)
    $prefix = switch ($Domain) {
        "Network"  { "NET" }
        "System"   { "SYS" }
        "Security" { "SEC" }
        "Storage"  { "STO" }
        "Services" { "SVC" }
        "AD"       { "AD"  }
        "M365"     { "M365"}
        "Migration"{ "MIG" }
        default    { "GEN" }
    }
    if (-not $script:CheckCounters[$prefix]) { $script:CheckCounters[$prefix] = 0 }
    $script:CheckCounters[$prefix]++
    return "$prefix-{0:D3}" -f $script:CheckCounters[$prefix]
}

# ── Constructeur d'objet check unifié ────────────────────────
function New-ESNCheck {
<#
.SYNOPSIS
    Crée un objet check standardisé exploitable par le reporting et le scoring.
.PARAMETER Domain
    Domaine technique : Network | System | Security | Storage | Services | AD | M365 | Migration
.PARAMETER Check
    Nom lisible du check (ex: "Adresse IP", "Windows Defender").
.PARAMETER Severity
    OK | WARNING | CRITICAL | INFO
.PARAMETER Value
    Valeur mesurée (ex: "192.168.1.42", "95%", "Activé").
.PARAMETER Detail
    Détail contextuel (ex: "Interface Ethernet0, DHCP").
.PARAMETER ScoreImpact
    Impact sur le score du domaine (0 = aucun, nombre positif = malus).
    Si non précisé, utilise le défaut par sévérité.
.PARAMETER Remediation
    Commande ou action corrective courte (ex: "ipconfig /flushdns").
.PARAMETER Tags
    Tags libres pour la recherche dans la base de connaissance.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet("OK","WARNING","CRITICAL","INFO")][string]$Severity,
        [string]  $Value       = "",
        [string]  $Detail      = "",
        [int]     $ScoreImpact = -1,
        [string]  $Remediation = "",
        [string[]]$Tags        = @()
    )

    $impact = if ($ScoreImpact -ge 0) { $ScoreImpact } else { $script:DefaultImpacts[$Severity] }

    return [PSCustomObject]@{
        id           = Get-ESNCheckId $Domain
        domain       = $Domain
        check        = $Check
        severity     = $Severity
        value        = $Value
        detail       = $Detail
        score_impact = $impact
        remediation  = $Remediation
        tags         = $Tags
        timestamp    = (Get-Date -Format "o")
    }
}

# ── Constructeur de résultat de domaine ──────────────────────
function New-ESNDomainResult {
<#
.SYNOPSIS
    Agrège les checks d'un domaine en un résultat structuré avec score calculé.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][PSCustomObject[]]$Checks,
        [int]$BaseScore = 100
    )

    $score       = $BaseScore
    $criticals   = @($Checks | Where-Object severity -eq "CRITICAL")
    $warnings    = @($Checks | Where-Object severity -eq "WARNING")
    $totalImpact = ($Checks | Where-Object { $_.severity -in "WARNING","CRITICAL" } |
                    Measure-Object score_impact -Sum).Sum

    $score = [Math]::Max(0, [Math]::Min(100, $score - $totalImpact))

    $label = if ($score -ge 80) { "Bon" } elseif ($score -ge 60) { "Dégradé" } elseif ($score -ge 40) { "Mauvais" } else { "Critique" }

    $recs = @($Checks | Where-Object { $_.remediation -and $_.severity -in "WARNING","CRITICAL" } |
              Select-Object -ExpandProperty remediation | Select-Object -Unique)

    return [PSCustomObject]@{
        domain          = $Domain
        score           = $score
        label           = $label
        critical_count  = $criticals.Count
        warning_count   = $warnings.Count
        ok_count        = @($Checks | Where-Object severity -eq "OK").Count
        total_impact    = $totalImpact
        checks          = $Checks
        recommendations = $recs
        timestamp       = (Get-Date -Format "o")
    }
}

# ── Helpers de formatage (Compatibles PS 5.1 & 7+) ────────────
function Get-ESNSeverityColor([string]$Severity) {
    if ($script:SeverityColors.ContainsKey($Severity)) { return $script:SeverityColors[$Severity] }
    return "#f8f9fa"
}
function Get-ESNSeverityIcon([string]$Severity) {
    if ($script:SeverityIcons.ContainsKey($Severity)) { return $script:SeverityIcons[$Severity] }
    return "?"
}
function Get-ESNSeverityTextColor([string]$Severity) {
    if ($script:SeverityTextColors.ContainsKey($Severity)) { return $script:SeverityTextColors[$Severity] }
    return "#333"
}

function Get-ESNReportRoot {
    [CmdletBinding()]
    param([string]$SubFolder = "")
    $base = if ($env:OS -match 'Windows' -and $env:SystemDrive) {
        Join-Path "$($env:SystemDrive)\ESN-Toolkit" "Reports"
    } else {
        Join-Path ([System.IO.Path]::GetTempPath()) "ESN-Toolkit/Reports"
    }
    $target = if ([string]::IsNullOrWhiteSpace($SubFolder)) { $base } else { Join-Path $base $SubFolder }
    if (-not (Test-Path -Path $target)) {
        New-Item -Path $target -ItemType Directory -Force | Out-Null
    }
    return $target
}

function Write-ESNSiemAlert {
<#
.SYNOPSIS
    Émet une alerte structurée JSON prête pour ingestion SIEM (Sentinel / LogRhythm / Splunk).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptName,
        [Parameter(Mandatory)][ValidateSet("OK","INFO","WARNING","CRITICAL")][string]$Severity,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Message,
        [string]$ErrorType = "",
        [string]$Target    = $(if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }),
        [hashtable]$Metadata = @{},
        [string]$LogFile   = ""
    )
    $payload = [PSCustomObject]@{
        schema_version = "1.0"
        timestamp      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        host           = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
        script         = $ScriptName
        category       = $Category
        severity       = $Severity
        error_type     = $ErrorType
        target         = $Target
        message        = $Message
        metadata       = $Metadata
    }
    $jsonLine = $payload | ConvertTo-Json -Depth 6 -Compress
    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        $LogFile = Join-Path (Get-ESNReportRoot -SubFolder "SIEM") "wsat-siem-events.jsonl"
    }
    $dir = Split-Path -Path $LogFile -Parent
    if ($dir -and -not (Test-Path -Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    Add-Content -Path $LogFile -Value $jsonLine -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($Severity -in @("WARNING", "CRITICAL")) {
        Write-Warning $jsonLine
    }
    return $payload
}

# ── Conversion depuis l'ancien format ESN-Core ───────────────
function ConvertTo-ESNCheck {
<#
.SYNOPSIS
    Convertit un résultat Add-ESNResult (ancien format) en New-ESNCheck (nouveau format).
    Assure la rétro-compatibilité sans casser les modules existants.
#>
    param([PSCustomObject]$LegacyResult)

    $sev = switch ($LegacyResult.Status) {
        "OK"    { "OK"       }
        "WARN"  { "WARNING"  }
        "ERROR" { "CRITICAL" }
        "INFO"  { "INFO"     }
        "SKIP"  { "INFO"     }
        default { "INFO"     }
    }

    $domain = $LegacyResult.Category -replace " .*",""

    return New-ESNCheck `
        -Domain      $domain `
        -Check       $LegacyResult.Check `
        -Severity    $sev `
        -Value       $LegacyResult.Value `
        -Detail      $LegacyResult.Details
}

# ── Export JSON d'un résultat complet ────────────────────────
function Export-ESNResultJson {
<#
.SYNOPSIS
    Exporte un tableau de résultats de domaines en JSON standardisé.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject[]]$DomainResults,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$ComputerName = $env:COMPUTERNAME,
        [string]$IncidentId   = "EXPORT"
    )

    $payload = [PSCustomObject]@{
        schema_version = "1.0"
        incident_id    = $IncidentId
        computer       = $ComputerName
        operator       = $env:USERNAME
        generated_at   = (Get-Date -Format "o")
        global_score   = [math]::Round(($DomainResults | Measure-Object score -Average).Average, 0)
        domains        = $DomainResults
    }

    $dir = Split-Path $OutputPath
    if ($dir -and -not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    $payload | ConvertTo-Json -Depth 10 | Out-File $OutputPath -Encoding UTF8 -Force
    return $OutputPath
}

# Fichier chargé par dot-sourcing : toutes ses fonctions sont visibles, Export-ModuleMember y est interdit.
