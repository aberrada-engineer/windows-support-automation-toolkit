#Requires -Version 5.1
<#
.SYNOPSIS
    ESN-Migration v2 — Migration utilisateur avec score 0-100,
    comparaison avant/après, manifest JSON enrichi, détection anomalies.
    PATCH 4/5 — Phase industrialisation.

.DESCRIPTION
    Fonctions : Invoke-UserStateCapture, Invoke-UserStateRestore
    Nouveautés v2 (non-breaking) :
      - Score de réussite 0-100 calculé après restauration
      - Manifest JSON v2.0 avec stats par module (fichiers, Mo, delta)
      - Comparaison avant/après sur chaque dossier
      - Détection d'anomalies (fichiers manquants, dossiers absents)
      - Phase de validation post-restauration automatique
      - Rapport HTML intégré généré à la fin de la restauration
      - PostMigrationActions listées dans le manifest et le rapport
#>

Set-StrictMode -Version Latest

# ─────────────────────────────────────────────────────────────
# HELPERS INTERNES
# ─────────────────────────────────────────────────────────────

function _MIG-FolderStats {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @{ Exists=$false; Files=0; SizeMB=0; SizeBytes=0 } }
    $items = Get-ChildItem $Path -Recurse -ErrorAction SilentlyContinue
    $files = $items | Where-Object { -not $_.PSIsContainer }
    $sum   = ($files | Measure-Object Length -Sum).Sum
    return @{
        Exists    = $true
        Files     = @($files).Count
        SizeMB    = [math]::Round($sum / 1MB, 1)
        SizeBytes = [int64]$sum
    }
}

function _MIG-MigrationScore {
    param([hashtable]$Results)
    $score     = 0
    $maxPoints = 0
    $grid = @{
        DataCopied    = @{ Weight=30; Required=$true  }
        OutlookOK     = @{ Weight=20; Required=$false }
        BrowsersOK    = @{ Weight=10; Required=$false }
        PrintersOK    = @{ Weight=10; Required=$false }
        NetDrivesOK   = @{ Weight=10; Required=$false }
        IntegrityOK   = @{ Weight=15; Required=$true  }
        ManifestValid = @{ Weight=5;  Required=$true  }
    }
    foreach ($key in $grid.Keys) {
        $w = $grid[$key]
        $maxPoints += $w.Weight
        if ($Results[$key] -eq $true) {
            $score += $w.Weight
        } elseif (-not $w.Required -and $Results[$key] -eq "SKIP") {
            $maxPoints -= $w.Weight   # module non demandé : pas de pénalité
        }
    }
    if ($maxPoints -le 0) { return 100 }
    return [Math]::Min(100, [Math]::Round($score / $maxPoints * 100, 0))
}

function _MIG-HtmlReport {
    param(
        [PSCustomObject]$Manifest,
        [hashtable]$ValResults,
        [int]$Score,
        [string]$OutPath
    )
    $sc = if ($Score -ge 80) { "#28a745" } elseif ($Score -ge 60) { "#ffc107" } else { "#dc3545" }
    $sl = if ($Score -ge 80) { "Succès"  } elseif ($Score -ge 60) { "Partiel" } else { "Échec"  }

    $rows = ($ValResults.GetEnumerator() | ForEach-Object {
        $v  = $_.Value
        $st = if ($v -eq $true)   { "OK" }
              elseif ($v -eq "SKIP") { "Non demandé" }
              elseif ($v -eq $false) { "ÉCHEC" }
              else { [string]$v }
        $bg = if ($st -eq "OK")   { "#d4edda" }
              elseif ($st -eq "Non demandé") { "#f8f9fa" }
              else { "#f8d7da" }
        "<tr style='background:$bg'><td style='padding:7px 12px;font-size:13px'>$($_.Key)</td><td style='padding:7px 12px;font-size:13px;font-weight:700'>$st</td></tr>"
    }) -join ""

    $anoHtml = if ($Manifest.Anomalies -and $Manifest.Anomalies.Count -gt 0) {
        "<div style='background:#fff3cd;border-radius:8px;padding:14px 18px;margin:10px 0'>
          <strong style='color:#856404'>Anomalies détectées ($($Manifest.Anomalies.Count))</strong>
          <ul style='margin:8px 0 0 18px'>" +
        ($Manifest.Anomalies | ForEach-Object { "<li style='font-size:13px;margin:4px 0'>$_</li>" }) -join "" +
        "</ul></div>"
    } else { "<p style='color:#155724;font-size:13px;padding:8px'>&#10003; Aucune anomalie</p>" }

    $actHtml = if ($Manifest.PostMigrationActions -and $Manifest.PostMigrationActions.Count -gt 0) {
        "<ol style='padding-left:20px'>" +
        ($Manifest.PostMigrationActions | ForEach-Object { "<li style='font-size:13px;margin:5px 0'>$_</li>" }) -join "" +
        "</ol>"
    } else { "" }

    @"
<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8">
<title>Migration — $($Manifest.Username)</title>
<style>*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:#f0f2f5;color:#333;font-size:14px}
.hdr{background:linear-gradient(135deg,#0d1b2a,#1b3a5c);color:#fff;padding:26px 36px}
.hdr h1{font-size:1.35em;margin-bottom:6px}
.hdr p{opacity:.8;font-size:.88em}
.box{background:#fff;border-radius:10px;padding:20px;margin:14px auto;max-width:900px;
     box-shadow:0 2px 8px rgba(0,0,0,.07)}
.box h2{font-size:.92em;font-weight:700;color:#0078d4;margin-bottom:12px;
        padding-bottom:8px;border-bottom:2px solid #f0f0f0}
.score{text-align:center;padding:16px 0}
.score .num{font-size:5em;font-weight:900;color:$sc;line-height:1}
.score .lbl{font-size:1.1em;font-weight:700;color:$sc;margin-top:6px}
.meta{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px}
.mi{background:#f8f9fa;border-radius:6px;padding:10px 14px}
.mi .k{font-size:11px;color:#888;text-transform:uppercase;font-weight:600}
.mi .v{font-size:13px;font-weight:600;margin-top:3px;word-break:break-word}
table{width:100%;border-collapse:collapse}
th{background:#0078d4;color:#fff;padding:8px 12px;text-align:left;font-size:12px}
.footer{text-align:center;padding:16px;color:#aaa;font-size:11px}</style>
</head><body>
<div class="hdr">
<h1>Migration Poste Utilisateur — $($Manifest.Username)</h1>
<p>$($Manifest.SourceComputer) &rarr; $($Manifest.TargetComputer ?? 'Non défini') &nbsp;|&nbsp; Opérateur : $($Manifest.Operator) &nbsp;|&nbsp; $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
</div>
<div class="box"><div class="score"><div class="num">$Score</div><div style="color:#999;font-size:.8em">/100</div><div class="lbl">$sl</div></div></div>
<div class="box"><h2>Informations</h2>
<div class="meta">
<div class="mi"><div class="k">Utilisateur</div><div class="v">$($Manifest.Username)</div></div>
<div class="mi"><div class="k">Poste source</div><div class="v">$($Manifest.SourceComputer)</div></div>
<div class="mi"><div class="k">Poste cible</div><div class="v">$($Manifest.TargetComputer ?? 'N/A')</div></div>
<div class="mi"><div class="k">Date capture</div><div class="v">$($Manifest.CaptureDate)</div></div>
<div class="mi"><div class="k">Volume migré</div><div class="v">$($Manifest.SizeMB) Mo</div></div>
<div class="mi"><div class="k">Dossier backup</div><div class="v" style="font-size:11px;word-break:break-all">$($Manifest.BackupDir)</div></div>
</div></div>
<div class="box"><h2>Validation</h2><table><tr><th>Composant</th><th>Statut</th></tr>$rows</table></div>
<div class="box"><h2>Anomalies</h2>$anoHtml</div>
$(if($actHtml){"<div class='box'><h2>Actions post-migration</h2>$actHtml</div>"})
<div class="footer">ESN-Toolkit v3.0 — Migration Report — $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</div>
</body></html>
"@ | Out-File $OutPath -Encoding UTF8 -Force
}

# ─────────────────────────────────────────────────────────────
# CAPTURE
# ─────────────────────────────────────────────────────────────
function Invoke-UserStateCapture {
<#
.SYNOPSIS
    Capture l'état complet d'un profil utilisateur vers un dossier de sauvegarde.

.PARAMETER SourceComputer   Poste source (celui qu'on remplace).
.PARAMETER Username          SamAccountName / nom de profil local.
.PARAMETER BackupRoot        Racine du dossier de backup.
.PARAMETER IncludeOutlook    Capture PST + signatures + registre Office.
.PARAMETER IncludeBrowsers   Capture Chrome, Edge, Firefox.
.PARAMETER IncludePrinters   Documente imprimantes + script de réinstall.
.PARAMETER IncludeNetDrives  Documente lecteurs réseau + script de remap.
.PARAMETER All               Active tous les modules ci-dessus.
.PARAMETER Simulation        Aucune copie réelle — audit uniquement.

.EXAMPLE
    Invoke-UserStateCapture -SourceComputer PC-ANCIEN -Username jdupont -All
    Invoke-UserStateCapture -SourceComputer PC-ANCIEN -Username jdupont -IncludeOutlook -Simulation
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceComputer,
        [Parameter(Mandatory)][string]$Username,
        [string]$BackupRoot        = "C:\ESN-Toolkit\Migrations",
        [switch]$IncludeOutlook,
        [switch]$IncludeBrowsers,
        [switch]$IncludePrinters,
        [switch]$IncludeNetDrives,
        [switch]$All,
        [switch]$Simulation
    )

    if ($All) {
        $IncludeOutlook   = $true
        $IncludeBrowsers  = $true
        $IncludePrinters  = $true
        $IncludeNetDrives = $true
    }

    $stamp     = Get-Date -Format "yyyy-MM-dd_HHmm"
    $backupDir = Join-Path $BackupRoot "${Username}_${SourceComputer}_${stamp}"
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

    $logFile      = Join-Path $backupDir "capture.log"
    $anomalies    = [System.Collections.Generic.List[string]]::new()
    $captureStats = @{}

    function L {
        param([string]$m, [string]$l = "INFO")
        $ts  = Get-Date -Format "HH:mm:ss"
        $col = @{ OK="Green"; WARN="Yellow"; ERROR="Red"; INFO="Cyan" }
        Write-Host "[$ts][$l] $m" -ForegroundColor ($col[$l] ?? "White")
        Add-Content $logFile "[$ts][$l] $m" -Encoding UTF8
    }

    L "=== CAPTURE DÉMARRÉE ===" "INFO"
    L "Source : $SourceComputer | User : $Username | Backup : $backupDir" "INFO"
    if ($Simulation) { L "MODE SIMULATION — aucune copie réelle" "WARN" }

    # Vérification profil source
    $sourcePath = "\\$SourceComputer\C$\Users\$Username"
    if (-not (Test-Path $sourcePath)) {
        L "Profil source introuvable : $sourcePath" "ERROR"
        $anomalies.Add("Profil source introuvable : $sourcePath")
        return $null
    }
    L "Profil source accessible : $sourcePath" "OK"

    # ── 1. DONNÉES UTILISATEUR ────────────────────────────────
    $folders = [ordered]@{
        "Desktop"   = "Bureau"
        "Documents" = "Documents"
        "Downloads" = "Telechargements"
        "Pictures"  = "Images"
        "Music"     = "Musique"
        "Videos"    = "Videos"
        "Favorites" = "Favoris-IE"
    }

    $captureStats.Data = @{}
    foreach ($rel in $folders.Keys) {
        $src = Join-Path $sourcePath $rel
        $dst = Join-Path $backupDir  $folders[$rel]
        if (Test-Path $src) {
            $before = _MIG-FolderStats $src
            L "$rel : $($before.Files) fichiers, $($before.SizeMB) Mo — copie..." "INFO"
            if (-not $Simulation) {
                robocopy $src $dst /E /COPY:DAT /R:2 /W:3 /MT:4 /NP /NFL /NDL 2>&1 | Out-Null
                $ok = $LASTEXITCODE -le 7
            } else { $ok = $true }
            $after = if (-not $Simulation) { _MIG-FolderStats $dst } else { $before }
            $delta = $before.Files - $after.Files
            $captureStats.Data[$rel] = @{
                SourceFiles  = $before.Files
                SourceMB     = $before.SizeMB
                CopiedFiles  = $after.Files
                CopiedMB     = $after.SizeMB
                Success      = $ok
                MissingFiles = [Math]::Max(0, $delta)
            }
            if ($delta -gt 10) { $anomalies.Add("$rel : $delta fichier(s) non copiés (src=$($before.Files), dst=$($after.Files))") }
            if ($ok) { L "$rel OK ($($after.Files)/$($before.Files) fichiers)" "OK" }
            else      { L "$rel ERREUR Robocopy" "ERROR" }
        } else {
            L "$rel absent sur le profil source (normal)" "INFO"
        }
    }

    # ── 2. OUTLOOK ────────────────────────────────────────────
    $captureStats.Outlook = @{ Requested=$IncludeOutlook.IsPresent; PST=0; Signatures=$false; RegistryOK=$false }
    if ($IncludeOutlook) {
        $outlookSrc = Join-Path $sourcePath "AppData\Local\Microsoft\Outlook"
        $sigSrc     = Join-Path $sourcePath "AppData\Roaming\Microsoft\Signatures"
        $outlookDst = Join-Path $backupDir "Outlook"
        New-Item $outlookDst -ItemType Directory -Force | Out-Null

        # PST
        $pstFiles = Get-ChildItem $outlookSrc -Filter "*.pst" -ErrorAction SilentlyContinue
        foreach ($pst in $pstFiles) {
            if (-not $Simulation) { Copy-Item $pst.FullName $outlookDst -Force -EA SilentlyContinue }
            $captureStats.Outlook.PST++
            L "PST : $($pst.Name) ($([math]::Round($pst.Length/1MB,0)) Mo)" "OK"
        }
        # OST : info seulement
        $ostFiles = Get-ChildItem $outlookSrc -Filter "*.ost" -ErrorAction SilentlyContinue
        foreach ($ost in $ostFiles) {
            L "OST : $($ost.Name) ($([math]::Round($ost.Length/1GB,2)) Go) — non copié (sera recréé)" "INFO"
        }
        if ($captureStats.Outlook.PST -eq 0 -and @($ostFiles).Count -eq 0) {
            $anomalies.Add("Outlook : aucun PST/OST trouvé (boîte probablement Exchange Online uniquement)")
        }
        # Signatures
        if (Test-Path $sigSrc) {
            if (-not $Simulation) { robocopy $sigSrc "$outlookDst\Signatures" /E /COPY:DAT /NP /NFL /NDL | Out-Null }
            $captureStats.Outlook.Signatures = $true
            L "Signatures Outlook copiées" "OK"
        } else {
            $anomalies.Add("Outlook : aucune signature trouvée dans $sigSrc")
        }
        # Registre Office
        $regDst = Join-Path $outlookDst "Office-Registry.reg"
        if (-not $Simulation) {
            reg export "HKCU\Software\Microsoft\Office" $regDst /y 2>&1 | Out-Null
        }
        $captureStats.Outlook.RegistryOK = (Test-Path $regDst) -or $Simulation
        if ($captureStats.Outlook.RegistryOK) { L "Registre Office exporté" "OK" }
    }

    # ── 3. NAVIGATEURS ────────────────────────────────────────
    $captureStats.Browsers = @{ Requested=$IncludeBrowsers.IsPresent; Chrome=$false; Edge=$false; Firefox=$false }
    if ($IncludeBrowsers) {
        $navDst = Join-Path $backupDir "Navigateurs"
        # Chrome
        $chromeSrc = Join-Path $sourcePath "AppData\Local\Google\Chrome\User Data\Default"
        if (Test-Path $chromeSrc) {
            $cDst = Join-Path $navDst "Chrome"
            New-Item $cDst -ItemType Directory -Force | Out-Null
            foreach ($item in @("Bookmarks","Preferences","Extensions","Login Data","Web Data","Shortcuts")) {
                $s = Join-Path $chromeSrc $item
                if (Test-Path $s) {
                    if (-not $Simulation) { Copy-Item $s $cDst -Recurse -Force -EA SilentlyContinue }
                }
            }
            $captureStats.Browsers.Chrome = $true
            L "Chrome copié" "OK"
        } else { $anomalies.Add("Chrome : profil introuvable") }

        # Edge
        $edgeSrc = Join-Path $sourcePath "AppData\Local\Microsoft\Edge\User Data\Default"
        if (Test-Path $edgeSrc) {
            $eDst = Join-Path $navDst "Edge"
            New-Item $eDst -ItemType Directory -Force | Out-Null
            foreach ($item in @("Bookmarks","Preferences","Favorites","Login Data","Extensions")) {
                $s = Join-Path $edgeSrc $item
                if (Test-Path $s) {
                    if (-not $Simulation) { Copy-Item $s $eDst -Recurse -Force -EA SilentlyContinue }
                }
            }
            $captureStats.Browsers.Edge = $true
            L "Edge copié" "OK"
        }

        # Firefox
        $ffDir = Join-Path $sourcePath "AppData\Roaming\Mozilla\Firefox\Profiles"
        $ffProf = Get-ChildItem $ffDir -Directory -EA SilentlyContinue | Select-Object -First 1
        if ($ffProf) {
            $fDst = Join-Path $navDst "Firefox"
            New-Item $fDst -ItemType Directory -Force | Out-Null
            foreach ($item in @("places.sqlite","key4.db","logins.json","prefs.js","extensions","bookmarkbackups")) {
                $s = Join-Path $ffProf.FullName $item
                if (Test-Path $s) {
                    if (-not $Simulation) { Copy-Item $s $fDst -Recurse -Force -EA SilentlyContinue }
                }
            }
            $captureStats.Browsers.Firefox = $true
            L "Firefox copié ($($ffProf.Name))" "OK"
        }
    }

    # ── 4. IMPRIMANTES ────────────────────────────────────────
    $captureStats.Printers = @{ Requested=$IncludePrinters.IsPresent; Count=0 }
    if ($IncludePrinters) {
        $printDst = Join-Path $backupDir "Imprimantes"
        New-Item $printDst -ItemType Directory -Force | Out-Null
        $printers = Invoke-Command -ComputerName $SourceComputer -ScriptBlock {
            Get-Printer | Select-Object Name, DriverName, PortName, Shared, ShareName,
                @{N='IsNetwork';E={ $_.PortName -like 'IP_*' -or $_.PortName -like '\\*' }}
        } -ErrorAction SilentlyContinue

        if ($printers) {
            $printers | Export-Csv (Join-Path $printDst "printers.csv") -NoTypeInformation -Encoding UTF8
            $lines = @("# Réinstallation imprimantes — $Username", "# $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "")
            foreach ($p in $printers) {
                $lines += "# === $($p.Name) ==="
                if     ($p.PortName -like 'IP_*') {
                    $ip = $p.PortName -replace 'IP_',''
                    $lines += "Add-PrinterPort -Name '$($p.PortName)' -PrinterHostAddress '$ip'"
                    $lines += "Add-Printer -Name '$($p.Name)' -DriverName '$($p.DriverName)' -PortName '$($p.PortName)'"
                } elseif ($p.PortName -like '\\*') {
                    $lines += "Add-Printer -ConnectionName '$($p.PortName)'"
                } else {
                    $lines += "# Imprimante locale — réinstallation manuelle du driver"
                }
                $lines += ""
            }
            $lines | Out-File (Join-Path $printDst "Reinstall-Printers.ps1") -Encoding UTF8
            $captureStats.Printers.Count = @($printers).Count
            L "$(@($printers).Count) imprimante(s) documentée(s)" "OK"
        } else {
            $anomalies.Add("Imprimantes : aucune imprimante trouvée sur $SourceComputer")
        }
    }

    # ── 5. LECTEURS RÉSEAU ────────────────────────────────────
    $captureStats.NetDrives = @{ Requested=$IncludeNetDrives.IsPresent; Count=0 }
    if ($IncludeNetDrives) {
        $netDst = Join-Path $backupDir "LecteursReseau"
        New-Item $netDst -ItemType Directory -Force | Out-Null
        $drives = Invoke-Command -ComputerName $SourceComputer -ScriptBlock {
            if (Test-Path "HKCU:\Network") {
                Get-ChildItem "HKCU:\Network" | ForEach-Object {
                    $p = Get-ItemProperty $_.PSPath
                    [PSCustomObject]@{ Lettre=$_.PSChildName; UNC=$p.RemotePath }
                }
            }
        } -ErrorAction SilentlyContinue

        if ($drives) {
            @($drives) | Export-Csv (Join-Path $netDst "drives.csv") -NoTypeInformation -Encoding UTF8
            $lines = @("# Remappage lecteurs réseau — $Username", "# $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "")
            foreach ($d in @($drives)) { $lines += "net use $($d.Lettre): `"$($d.UNC)`" /persistent:yes" }
            $lines | Out-File (Join-Path $netDst "Remap-Drives.ps1") -Encoding UTF8
            $captureStats.NetDrives.Count = @($drives).Count
            L "$(@($drives).Count) lecteur(s) réseau documenté(s)" "OK"
        } else {
            $anomalies.Add("Lecteurs réseau : aucun lecteur persistant trouvé (registre HKCU:\Network vide)")
        }
    }

    # ── TAILLE TOTALE ─────────────────────────────────────────
    $totalMB = if (-not $Simulation) {
        [math]::Round((Get-ChildItem $backupDir -Recurse -EA SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Measure-Object Length -Sum).Sum / 1MB, 0)
    } else { 0 }

    # ── ACTIONS POST-MIGRATION ───────────────────────────────
    $postActions = [System.Collections.Generic.List[string]]::new()
    $postActions.Add("Connecter le nouveau poste au domaine si nécessaire")
    $postActions.Add("Faire se connecter l'utilisateur une première fois")
    $postActions.Add("Vérifier Bureau, Documents, Téléchargements")
    if ($IncludeOutlook)   { $postActions.Add("Ouvrir Outlook et importer le PST depuis $backupDir\Outlook si nécessaire") }
    if ($IncludePrinters)  { $postActions.Add("Exécuter en admin : $backupDir\Imprimantes\Reinstall-Printers.ps1") }
    if ($IncludeNetDrives) { $postActions.Add("Exécuter : $backupDir\LecteursReseau\Remap-Drives.ps1") }
    $postActions.Add("Tester les accès applicatifs et valider avec l'utilisateur")
    $postActions.Add("Signer le bon de migration")

    # ── MANIFEST JSON v2.0 ────────────────────────────────────
    $manifest = [PSCustomObject]@{
        SchemaVersion        = "2.0"
        CaptureDate          = (Get-Date -Format "o")
        SourceComputer       = $SourceComputer
        TargetComputer       = $null
        Username             = $Username
        Operator             = $env:USERNAME
        BackupDir            = $backupDir
        Simulation           = $Simulation.IsPresent
        SizeMB               = $totalMB
        AnomalyCount         = $anomalies.Count
        Anomalies            = $anomalies.ToArray()
        CaptureStats         = $captureStats
        Modules              = @{
            Data      = $true
            Outlook   = $IncludeOutlook.IsPresent
            Browsers  = $IncludeBrowsers.IsPresent
            Printers  = $IncludePrinters.IsPresent
            NetDrives = $IncludeNetDrives.IsPresent
        }
        PostMigrationActions = $postActions.ToArray()
        ValidationScore      = $null
        RestoreDate          = $null
        ValidationResults    = $null
    }

    $manifestPath = Join-Path $backupDir "manifest.json"
    $manifest | ConvertTo-Json -Depth 10 | Out-File $manifestPath -Encoding UTF8 -Force

    if ($anomalies.Count -gt 0) {
        L "$($anomalies.Count) anomalie(s) :" "WARN"
        $anomalies | ForEach-Object { L "  · $_" "WARN" }
    } else {
        L "Aucune anomalie détectée" "OK"
    }

    L "Capture terminée — $totalMB Mo — $backupDir" "OK"

    Write-Host ""
    Write-Host "  Backup    : $backupDir" -ForegroundColor Yellow
    Write-Host "  Restore   : " -NoNewline -ForegroundColor Cyan
    Write-Host ".\Invoke-Migration.ps1 -Action Restore -BackupDir `"$backupDir`" -TargetComputer NOM-PC -Username $Username" -ForegroundColor Cyan

    return $backupDir
}

# ─────────────────────────────────────────────────────────────
# RESTAURATION
# ─────────────────────────────────────────────────────────────
function Invoke-UserStateRestore {
<#
.SYNOPSIS
    Restaure l'état utilisateur depuis une capture.
    v2 : score de réussite 0-100, comparaison avant/après, rapport HTML.

.PARAMETER BackupDir       Dossier créé par Invoke-UserStateCapture.
.PARAMETER TargetComputer  Nouveau poste cible.
.PARAMETER Username        Nom du profil cible.
.PARAMETER Simulation      Dry-run, aucune copie réelle.

.EXAMPLE
    Invoke-UserStateRestore -BackupDir "C:\ESN-Toolkit\Migrations\jdupont_PC-ANCIEN_2025-05-15_1430" -TargetComputer PC-NOUVEAU -Username jdupont
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupDir,
        [Parameter(Mandatory)][string]$TargetComputer,
        [string]$Username   = $env:USERNAME,
        [switch]$Simulation
    )

    if (-not (Test-Path $BackupDir)) {
        Write-Host "[ERREUR] BackupDir introuvable : $BackupDir" -ForegroundColor Red
        return $null
    }

    $manifestPath = Join-Path $BackupDir "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Host "[ERREUR] manifest.json introuvable dans $BackupDir" -ForegroundColor Red
        return $null
    }

    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  RESTAURATION — $Username → $TargetComputer" -ForegroundColor Cyan
    Write-Host "║  Source  : $($manifest.SourceComputer)" -ForegroundColor Cyan
    Write-Host "║  Capture : $($manifest.CaptureDate)" -ForegroundColor Cyan
    if ($Simulation) { Write-Host "║  ⚠ MODE SIMULATION" -ForegroundColor Yellow }
    Write-Host "╚══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    $anomalies = [System.Collections.Generic.List[string]]::new()
    if ($manifest.Anomalies) { $manifest.Anomalies | ForEach-Object { $anomalies.Add($_) } }

    $valResults = @{
        DataCopied    = $false
        OutlookOK     = "SKIP"
        BrowsersOK    = "SKIP"
        PrintersOK    = "SKIP"
        NetDrivesOK   = "SKIP"
        IntegrityOK   = $false
        ManifestValid = $true
    }

    $targetProfile = "\\$TargetComputer\C$\Users\$Username"

    # ── 1. DONNÉES UTILISATEUR ────────────────────────────────
    $folderMap = [ordered]@{
        "Bureau"          = "Desktop"
        "Documents"       = "Documents"
        "Telechargements" = "Downloads"
        "Images"          = "Pictures"
        "Musique"         = "Music"
        "Videos"          = "Videos"
    }

    $ok = 0; $fail = 0
    foreach ($src in $folderMap.Keys) {
        $srcPath = Join-Path $BackupDir $src
        $dstPath = Join-Path $targetProfile $folderMap[$src]
        if (Test-Path $srcPath) {
            $statSrc = _MIG-FolderStats $srcPath
            if (-not $Simulation) {
                robocopy $srcPath $dstPath /E /COPY:DAT /R:2 /W:3 /MT:4 /NP /NFL /NDL 2>&1 | Out-Null
                if ($LASTEXITCODE -le 7) { $ok++ } else { $fail++; $anomalies.Add("Restore erreur $src (Robocopy code $LASTEXITCODE)") }
            } else { $ok++ }
            Write-Host "  [OK] $src : $($statSrc.Files) fichiers, $($statSrc.SizeMB) Mo" -ForegroundColor Green
        }
    }
    $valResults.DataCopied = ($ok -gt 0 -and $fail -eq 0)

    # ── 2. OUTLOOK ────────────────────────────────────────────
    if ($manifest.Modules.Outlook) {
        $valResults.OutlookOK = $false
        $outlookBackup = Join-Path $BackupDir "Outlook"
        if (Test-Path $outlookBackup) {
            $pstFiles = Get-ChildItem $outlookBackup -Filter "*.pst" -EA SilentlyContinue
            if ($pstFiles) {
                $outlookDst = Join-Path $targetProfile "AppData\Local\Microsoft\Outlook"
                if (-not $Simulation) {
                    New-Item $outlookDst -ItemType Directory -Force | Out-Null
                    $pstFiles | ForEach-Object { Copy-Item $_.FullName $outlookDst -Force -EA SilentlyContinue }
                }
                Write-Host "  [OK] PST : $(@($pstFiles).Count) fichier(s)" -ForegroundColor Green
            }
            $sigBackup = Join-Path $outlookBackup "Signatures"
            if (Test-Path $sigBackup) {
                $sigDst = Join-Path $targetProfile "AppData\Roaming\Microsoft\Signatures"
                if (-not $Simulation) {
                    New-Item $sigDst -ItemType Directory -Force | Out-Null
                    robocopy $sigBackup $sigDst /E /COPY:DAT /NP /NFL /NDL | Out-Null
                }
                Write-Host "  [OK] Signatures Outlook restaurées" -ForegroundColor Green
            }
            $valResults.OutlookOK = $true
        } else {
            $anomalies.Add("Outlook : dossier de backup absent dans $BackupDir")
        }
    }

    # ── 3. SCRIPTS IMPRIMANTES & LECTEURS (info) ──────────────
    if ($manifest.Modules.Printers) {
        $ps = Join-Path $BackupDir "Imprimantes\Reinstall-Printers.ps1"
        $valResults.PrintersOK = (Test-Path $ps)
        if ($valResults.PrintersOK) {
            Write-Host "  [INFO] Imprimantes : exécuter $ps" -ForegroundColor Cyan
        } else {
            $anomalies.Add("Reinstall-Printers.ps1 introuvable dans $BackupDir\Imprimantes")
        }
    }

    if ($manifest.Modules.NetDrives) {
        $ps = Join-Path $BackupDir "LecteursReseau\Remap-Drives.ps1"
        $valResults.NetDrivesOK = (Test-Path $ps)
        if ($valResults.NetDrivesOK) {
            Write-Host "  [INFO] Lecteurs réseau : exécuter $ps" -ForegroundColor Cyan
        } else {
            $anomalies.Add("Remap-Drives.ps1 introuvable dans $BackupDir\LecteursReseau")
        }
    }

    # ── 4. VÉRIFICATION INTÉGRITÉ ─────────────────────────────
    Write-Host "`n  [*] Vérification intégrité..." -ForegroundColor Cyan
    $intOK = $true
    foreach ($src in $folderMap.Keys) {
        $srcPath = Join-Path $BackupDir $src
        $dstPath = Join-Path $targetProfile $folderMap[$src]
        if (Test-Path $srcPath) {
            $sSrc = _MIG-FolderStats $srcPath
            $sDst = if (-not $Simulation) { _MIG-FolderStats $dstPath } else { $sSrc }
            $delta = $sSrc.Files - $sDst.Files
            if ($delta -gt 5) {
                $intOK = $false
                $anomalies.Add("Intégrité $src : $delta fichier(s) manquant(s) (src=$($sSrc.Files), dst=$($sDst.Files))")
                Write-Host "  [!!] $src : $delta fichier(s) manquant(s)" -ForegroundColor Yellow
            } else {
                Write-Host "  [OK] $src : $($sDst.Files)/$($sSrc.Files) fichiers" -ForegroundColor Green
            }
        }
    }
    $valResults.IntegrityOK = $intOK

    # ── SCORE ─────────────────────────────────────────────────
    $score      = _MIG-MigrationScore $valResults
    $scoreColor = if ($score -ge 80) { "Green" } elseif ($score -ge 60) { "Yellow" } else { "Red" }

    # ── MAJ MANIFEST ──────────────────────────────────────────
    $manifest.TargetComputer   = $TargetComputer
    $manifest.RestoreDate      = (Get-Date -Format "o")
    $manifest.ValidationScore  = $score
    $manifest.Anomalies        = $anomalies.ToArray()
    $manifest.AnomalyCount     = $anomalies.Count
    $manifest.ValidationResults = $valResults
    $manifest | ConvertTo-Json -Depth 10 | Out-File $manifestPath -Encoding UTF8 -Force

    # ── RAPPORT HTML ──────────────────────────────────────────
    $reportPath = Join-Path $BackupDir "Migration-Report.html"
    _MIG-HtmlReport -Manifest $manifest -ValResults $valResults -Score $score -OutPath $reportPath

    # ── RÉSUMÉ CONSOLE ────────────────────────────────────────
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  SCORE MIGRATION : " -NoNewline -ForegroundColor Cyan
    Write-Host "$score/100" -ForegroundColor $scoreColor -NoNewline; Write-Host "" -ForegroundColor Cyan
    Write-Host "║  Anomalies : $($anomalies.Count)" -ForegroundColor Cyan
    Write-Host "║  Rapport   : $reportPath" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Actions post-migration :" -ForegroundColor Yellow
    $manifest.PostMigrationActions | ForEach-Object { Write-Host "   · $_" -ForegroundColor Yellow }

    return [PSCustomObject]@{
        Score             = $score
        BackupDir         = $BackupDir
        TargetComputer    = $TargetComputer
        Username          = $Username
        ValidationResults = $valResults
        Anomalies         = $anomalies.ToArray()
        ReportPath        = $reportPath
        ManifestPath      = $manifestPath
    }
}

Export-ModuleMember -Function @('Invoke-UserStateCapture', 'Invoke-UserStateRestore')
